# frozen_string_literal: true

module Risk
  # Runs Engine A + Engine B.
  # preferred: "local" (Arrow + Ruby DSL on default Galaaz R) |
  #            "docker" (Feather handoff, concurrent R 3.6.3 + 4.3.3).
  class DualOrchestrator
    Outcome = Struct.new(
      :historical, :monte_carlo, :wall_elapsed_ms, :errors, :runtime,
      keyword_init: true
    )

    def self.call(rows, portfolio_value:, preferred: "local")
      new(rows, portfolio_value: portfolio_value, preferred: preferred).call
    end

    def initialize(rows, portfolio_value:, preferred: "local")
      @rows = rows
      @portfolio_value = portfolio_value
      @preferred = preferred.to_s
    end

    def call
      if @preferred == "docker"
        status = DockerEngines.probe
        if status.images_ready
          run_docker
        else
          run_local(
            notice: status.notice || "Docker dual-R not ready — using local Arrow + Ruby DSL."
          )
        end
      else
        run_local(notice: nil)
      end
    end

    private

    def run_engines_concurrently(mode:, hist_eval:, mc_eval:, hist_label:, mc_label:)
      errors = {}
      historical = nil
      monte_carlo = nil

      hist_t = Thread.new do
        historical = HistoricalEngine.call(
          @rows,
          mode: mode,
          eval: hist_eval,
          r_version_label: hist_label
        )
      rescue StandardError => e
        errors["historical"] = e.message
      end
      mc_t = Thread.new do
        monte_carlo = MonteCarloEngine.call(
          @rows,
          portfolio_value: @portfolio_value,
          mode: mode,
          eval: mc_eval,
          r_version_label: mc_label
        )
      rescue StandardError => e
        errors["monte_carlo"] = e.message
      end
      hist_t.join
      mc_t.join
      [historical, monte_carlo, errors]
    end

    def run_docker
      errors = {}
      historical = nil
      monte_carlo = nil
      wall_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      begin
        DockerEngines.with_dual_containers do |_hm, _mm, hist_eval, mc_eval|
          historical, monte_carlo, errors = run_engines_concurrently(
            mode: :docker,
            hist_eval: hist_eval,
            mc_eval: mc_eval,
            hist_label: DockerEngines::HIST_VERSION,
            mc_label: DockerEngines::MC_VERSION
          )
        end
      rescue StandardError => e
        return run_local(
          notice: "Docker dual-R start failed (#{e.message}). Falling back to local Arrow + Ruby DSL. " \
                  "Try: bin/setup_docker_r_engines"
        )
      end

      finish(historical, monte_carlo, errors, wall_started, mode: "docker", notice: nil, concurrent: true)
    end

    def run_local(notice:)
      # Default Galaaz bridge: Arrow tables + Ruby methods calling R.* (sequential, one R).
      wall_started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      errors = {}
      historical = nil
      monte_carlo = nil

      begin
        historical = HistoricalEngine.call(@rows, mode: :local, r_version_label: "local")
      rescue StandardError => e
        errors["historical"] = e.message
      end
      begin
        monte_carlo = MonteCarloEngine.call(
          @rows, portfolio_value: @portfolio_value, mode: :local, r_version_label: "local"
        )
      rescue StandardError => e
        errors["monte_carlo"] = e.message
      end

      finish(
        historical, monte_carlo, errors, wall_started,
        mode: notice ? "local_fallback" : "local",
        notice: notice,
        concurrent: false
      )
    end

    def finish(historical, monte_carlo, errors, wall_started, mode:, notice:, concurrent:)
      wall_elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - wall_started) * 1000).round
      Outcome.new(
        historical: historical,
        monte_carlo: monte_carlo,
        wall_elapsed_ms: wall_elapsed_ms,
        errors: errors,
        runtime: {
          "mode" => mode,
          "preferred" => @preferred,
          "concurrent" => concurrent,
          "handoff" => concurrent ? "arrow_feather" : "arrow_table",
          "historical_target" => DockerEngines::HIST_VERSION,
          "monte_carlo_target" => DockerEngines::MC_VERSION,
          "historical_r" => historical&.payload&.dig("r_version"),
          "monte_carlo_r" => monte_carlo&.payload&.dig("r_version"),
          "notice" => notice
        }
      )
    end
  end
end
