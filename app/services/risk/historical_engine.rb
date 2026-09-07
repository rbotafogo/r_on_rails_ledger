# frozen_string_literal: true

require "json"
require "galaaz"

module Risk
  # Engine A: empirical VaR / ES, density, rolling VaR + breaches.
  #
  # Local (default Galaaz bridge): Arrow IPC (Stage B) or table_from (Stage A) + R.* DSL.
  # Remote @eval (Docker dual-R): IPC file, else Feather, else RDS.
  class HistoricalEngine
    Result = Struct.new(
      :var_95, :var_99, :expected_shortfall, :elapsed_ms, :payload,
      keyword_init: true
    )

    WINDOW = 252

    def self.call(rows, mode: :local, eval: nil, r_version_label: nil)
      new(rows, mode: mode, eval: eval, r_version_label: r_version_label).call
    end

    def initialize(rows, mode: :local, eval: nil, r_version_label: nil)
      @rows = rows
      @mode = mode
      @eval = eval
      @r_version_label = r_version_label
    end

    def call
      raise ArgumentError, "ReturnPanel is empty" if @rows.empty?

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      times, port_returns = RJsonJob.portfolio_returns(@rows)

      raw =
        if @eval
          remote_arrow_eval(port_returns)
        else
          local_arrow_dsl(port_returns)
        end

      rolling = rolling_var_series(times, port_returns)
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      Result.new(
        var_95: raw.fetch("var_95").to_f,
        var_99: raw.fetch("var_99").to_f,
        expected_shortfall: raw.fetch("expected_shortfall").to_f,
        elapsed_ms: elapsed_ms,
        payload: {
          "engine" => "historical_arrow_dsl",
          "density" => raw.fetch("density"),
          "var_95" => raw.fetch("var_95").to_f,
          "var_99" => raw.fetch("var_99").to_f,
          "expected_shortfall" => raw.fetch("expected_shortfall").to_f,
          "rolling_var_series" => rolling[:series],
          "breach_points" => rolling[:breaches],
          "horizon_label" => "1-day historical",
          "r_version" => raw["r_version"],
          "r_version_label" => @r_version_label || raw["r_version"],
          "handoff" => raw["handoff"]
        }
      )
    end

    # --- Ruby DSL surface (showcase) -------------------------------------------------

    # Empirical VaR as a lower quantile of portfolio daily returns (R.quantile).
    def historical_var(returns_vec, probs:)
      RValues.scalar_f(
        R.as__numeric(R.quantile(returns_vec, probs: probs, names: false, type: 7))
      )
    end

    # Expected shortfall / CVaR: mean of returns at or below the VaR threshold.
    def expected_shortfall(returns_vec, var_level)
      thr = var_level.is_a?(Numeric) ? var_level : RValues.scalar_f(var_level)
      RValues.scalar_f(R.as__numeric(R.mean(returns_vec[returns_vec <= thr])))
    end

    # Kernel density coordinates for Plotly (R.density; Stage B2 IPC when available).
    def return_density(returns_vec, n: 128)
      ArrowHandoff.density_xy_for_plotly(returns_vec, n: n)
    end

    private

    def local_arrow_dsl(port_returns)
      returns_vec = ArrowHandoff.to_returns_numeric(port_returns)
      q05 = historical_var(returns_vec, probs: 0.05)
      q01 = historical_var(returns_vec, probs: 0.01)
      es = expected_shortfall(returns_vec, q05)
      {
        "var_95" => q05,
        "var_99" => q01,
        "expected_shortfall" => es,
        "density" => return_density(returns_vec),
        "r_version" => RValues.r_version_string,
        "handoff" => ArrowHandoff.local_handoff_tag
      }
    end

    def remote_arrow_eval(port_returns)
      ArrowHandoff.with_returns_remote(port_returns, mode: @mode) do |paths|
        r_code = <<~R
          #{ArrowHandoff.remote_load_returns_r(paths)}
          q05 <- as.numeric(quantile(x, probs = 0.05, names = FALSE, type = 7))
          q01 <- as.numeric(quantile(x, probs = 0.01, names = FALSE, type = 7))
          es <- mean(x[x <= q05])
          dens <- density(x, n = 128)
          rver <- paste(R.version$major, R.version$minor, sep = ".")
          json <- paste0(
            '{"var_95":', q05,
            ',"var_99":', q01,
            ',"expected_shortfall":', es,
            ',"handoff":"', handoff, '"',
            ',"r_version":"', rver, '"',
            ',"density":[',
            paste0('{"x":', dens$x, ',"y":', dens$y, "}", collapse = ","),
            "]}"
          )
          writeLines(json, #{paths[:r_out].inspect})
          TRUE
        R
        RJsonJob.eval_r!(r_code, eval: @eval)
        raise "R engine wrote no result JSON at #{paths[:host_out]}" unless File.file?(paths[:host_out])

        JSON.parse(File.read(paths[:host_out]))
      end
    end

    def rolling_var_series(times, returns)
      series = []
      breaches = []
      returns.each_with_index do |ret, i|
        next if i + 1 < WINDOW

        window = returns[(i + 1 - WINDOW)..i]
        sorted = window.sort
        idx = [((WINDOW - 1) * 0.05).floor, 0].max
        var_level = sorted[idx]
        point = {
          "t" => times[i],
          "return" => ret,
          "var_95" => var_level
        }
        series << point
        breaches << { "t" => times[i], "return" => ret, "var_95" => var_level } if ret < var_level
      end

      if series.size > 1000
        series = series.last(1000)
        t0 = series.first["t"]
        breaches = breaches.select { |b| b["t"] >= t0 }
      end

      { series: series, breaches: breaches }
    end
  end
end
