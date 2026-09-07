# frozen_string_literal: true

require "json"
require "galaaz"

module Risk
  # Engine B: forward Monte Carlo (GBM calibrated to historical portfolio returns).
  #
  # Local: Arrow IPC / table_from → numeric vector, then GBM in R referenced by handle.
  # Remote @eval: IPC file, else Feather, else RDS.
  class MonteCarloEngine
    Result = Struct.new(
      :sim_var_30d, :sim_expected_max_drawdown, :tail_risk_probability,
      :elapsed_ms, :payload,
      keyword_init: true
    )

    def self.call(rows, portfolio_value:, mode: :local, eval: nil, r_version_label: nil, n_paths: nil, sample_paths: nil)
      new(
        rows,
        portfolio_value: portfolio_value,
        mode: mode,
        eval: eval,
        r_version_label: r_version_label,
        n_paths: n_paths,
        sample_paths: sample_paths
      ).call
    end

    def initialize(rows, portfolio_value:, mode: :local, eval: nil, r_version_label: nil, n_paths: nil, sample_paths: nil)
      @rows = rows
      @portfolio_value = portfolio_value.to_f
      @mode = mode
      @eval = eval
      @r_version_label = r_version_label
      @n_paths = McPaths.resolve(n_paths)
      @horizon = ENV.fetch("MC_HORIZON_DAYS", "30").to_i
      @sample_paths = sample_paths.presence&.to_i
      @sample_paths = McPaths.sample_paths_for(@n_paths) if @sample_paths.nil? || @sample_paths <= 0
    end

    def call
      raise ArgumentError, "ReturnPanel is empty" if @rows.empty?

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      _times, port_returns = RJsonJob.portfolio_returns(@rows)

      raw =
        if @eval
          remote_arrow_eval(port_returns)
        else
          local_arrow_gbm(port_returns)
        end

      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      Result.new(
        sim_var_30d: raw.fetch("sim_var_30d").to_f,
        sim_expected_max_drawdown: raw.fetch("sim_expected_max_drawdown").to_f,
        tail_risk_probability: raw.fetch("tail_risk_probability").to_f,
        elapsed_ms: elapsed_ms,
        payload: raw.merge(
          "horizon_label" => "#{raw['horizon_days']}-day Monte Carlo",
          "var_95" => raw.fetch("sim_var_30d").to_f,
          "var_99" => raw.fetch("sim_var_99_30d").to_f,
          "r_version_label" => @r_version_label || raw["r_version"]
        )
      )
    rescue McPaths::InsufficientMemory
      raise
    rescue StandardError => e
      raise McPaths.wrap_runtime_failure(e, n_paths: @n_paths)
    end

    # Calibrate μ/σ from Arrow-backed returns via R.* (showcase helpers).
    def mean_return(returns_vec)
      RValues.scalar_f(R.as__numeric(R.mean(returns_vec)))
    end

    def sd_return(returns_vec)
      RValues.scalar_f(R.as__numeric(R.sd(returns_vec)))
    end

    private

    def local_arrow_gbm(port_returns)
      returns_vec = ArrowHandoff.to_returns_numeric(port_returns)
      mu = mean_return(returns_vec)
      sig = sd_return(returns_vec)
      sig = 1e-4 unless sig.finite? && sig.positive?

      # Long path simulation stays in R; inputs are the Arrow-derived vector handle.
      js = R::Support.eval(gbm_r_body(
        x_expr: "as.numeric(#{returns_vec.r_interop})",
        mu: mu,
        sig: sig,
        write_json_path: nil
      ))
      JSON.parse(RValues.scalar_s(js)).merge("handoff" => ArrowHandoff.local_handoff_tag)
    end

    def remote_arrow_eval(port_returns)
      ArrowHandoff.with_returns_remote(port_returns, mode: @mode) do |paths|
        r_code = <<~R
          #{ArrowHandoff.remote_load_returns_r(paths)}
          mu <- mean(x)
          sig <- sd(x)
          if (!is.finite(sig) || sig <= 0) sig <- 1e-4
          #{gbm_r_body(x_expr: "x", mu: nil, sig: nil, write_json_path: paths[:r_out], handoff_expr: "handoff")}
          TRUE
        R
        RJsonJob.eval_r!(r_code, eval: @eval)
        raise "R engine wrote no result JSON at #{paths[:host_out]}" unless File.file?(paths[:host_out])

        JSON.parse(File.read(paths[:host_out]))
      end
    end

    # Shared GBM body. When mu/sig are nil, expects R locals mu/sig already set.
    def gbm_r_body(x_expr:, mu:, sig:, write_json_path:, handoff_expr: '"arrow_ipc"')
      mu_line = mu.nil? ? "" : "mu <- #{mu};"
      sig_line = sig.nil? ? "" : "sig <- #{sig};"
      out =
        if write_json_path
          "writeLines(json, #{write_json_path.inspect}); json"
        else
          "json"
        end

      <<~R
        #{mu_line}
        #{sig_line}
        x_cal <- #{x_expr}
        n_paths <- #{@n_paths}
        horizon <- #{@horizon}
        n_sample <- #{@sample_paths}
        s0 <- #{@portfolio_value}
        set.seed(42)
        rver <- paste(R.version$major, R.version$minor, sep = ".")
        handoff_tag <- #{handoff_expr}

        z <- matrix(rnorm(n_paths * horizon), nrow = n_paths, ncol = horizon)
        rets <- mu + sig * z
        log_growth <- t(apply(rets, 1, cumsum))
        paths <- s0 * exp(log_growth)

        terminal <- paths[, horizon]
        term_ret <- terminal / s0 - 1
        sim_var_30d <- as.numeric(quantile(term_ret, probs = 0.05, names = FALSE, type = 7))
        sim_var_99 <- as.numeric(quantile(term_ret, probs = 0.01, names = FALSE, type = 7))

        mdd <- apply(paths, 1, function(p) {
          peak <- p[1]
          max_dd <- 0
          for (v in p) {
            if (v > peak) peak <- v
            dd <- (peak - v) / peak
            if (dd > max_dd) max_dd <- dd
          }
          max_dd
        })
        sim_mdd <- mean(mdd)
        tail_prob <- mean(term_ret < -0.05)

        dens <- density(term_ret, n = 128)
        qs <- apply(paths, 2, quantile, probs = c(0.05, 0.25, 0.5, 0.75, 0.95), names = FALSE)

        sample_idx <- seq_len(min(n_sample, n_paths))
        dens_json <- paste0('{"x":', dens$x, ',"y":', dens$y, "}", collapse = ",")
        env_parts <- character(horizon)
        for (d in seq_len(horizon)) {
          env_parts[d] <- paste0(
            '{"t":', d,
            ',"p05":', qs[1, d],
            ',"p25":', qs[2, d],
            ',"p50":', qs[3, d],
            ',"p75":', qs[4, d],
            ',"p95":', qs[5, d], "}"
          )
        }
        path_parts <- character(length(sample_idx))
        for (i in seq_along(sample_idx)) {
          row <- paths[sample_idx[i], ]
          pts <- paste0('{"t":', seq_len(horizon), ',"value":', row, "}", collapse = ",")
          path_parts[i] <- paste0("[", pts, "]")
        }

        json <- paste0(
          '{"sim_var_30d":', sim_var_30d,
          ',"sim_var_99_30d":', sim_var_99,
          ',"sim_expected_max_drawdown":', sim_mdd,
          ',"tail_risk_probability":', tail_prob,
          ',"engine":"monte_carlo_gbm"',
          ',"handoff":"', handoff_tag, '"',
          ',"r_version":"', rver, '"',
          ',"n_paths":', n_paths,
          ',"horizon_days":', horizon,
          ',"s0":', s0,
          ',"terminal_density":[', dens_json, "]",
          ',"quantile_envelopes":[', paste(env_parts, collapse = ","), "]",
          ',"sample_paths":[', paste(path_parts, collapse = ","), "]",
          "}"
        )
        #{out}
      R
    end
  end
end
