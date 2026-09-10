# frozen_string_literal: true

module Risk
  # Choose Monte Carlo path counts from free RAM and UI input.
  # Prefer refusing an unsafe N with a clear message over letting R OOM / close the bridge.
  module McPaths
    PRESETS = [ 100, 200, 500, 1_000, 2_000, 5_000 ].freeze

    # Conservative bytes/path for GBM matrix + R overhead (horizon ≈ 30).
    BYTES_PER_PATH = 8 * 30 * 8

    class InsufficientMemory < StandardError; end

    module_function

    def mem_available_kib
      File.read("/proc/meminfo")[/MemAvailable:\s+(\d+)/, 1].to_i
    rescue StandardError
      0
    end

    def mem_available_mib
      mem_available_kib / 1024
    end

    # Default when the user does not pick a value (and MC_PATHS is unset).
    def suggested_default
      env = ENV["MC_PATHS"].presence&.to_i
      return env if env&.positive?

      mib = mem_available_mib
      return 500 if mib <= 0

      if mib < 1_500
        200
      elsif mib < 3_000
        500
      elsif mib < 6_000
        2_000
      else
        5_000
      end
    end

    # Soft ceiling from MemAvailable (use ~1/4 of free RAM for the path matrix).
    def max_safe
      kib = mem_available_kib
      return 5_000 if kib <= 0

      usable = (kib * 1024) / 4
      [ [ usable / BYTES_PER_PATH, 100 ].max, 50_000 ].min
    end

    # Resolve UI/ENV request; raise InsufficientMemory if clearly too large.
    def resolve(requested)
      n = requested.to_i
      n = suggested_default if n <= 0
      soft = max_safe
      if n > soft
        raise InsufficientMemory,
              "Not enough memory for #{n} Monte Carlo paths " \
              "(about #{soft} is safe with ~#{mem_available_mib} MiB free RAM). " \
              "Reduce the path count and try again."
      end
      n
    end

    def sample_paths_for(n_paths)
      env = ENV["MC_SAMPLE_PATHS"].presence&.to_i
      return env if env&.positive?

      [ [ n_paths / 10, 100 ].min, 20 ].max
    end

    # Map bridge/R death into a user-facing memory hint.
    def wrap_runtime_failure(error, n_paths:)
      msg = error.message.to_s
      return error unless msg.match?(/connection closed|no RET|timeout|RProcessError|failed to accept/i)

      hint = [ suggested_default, (n_paths / 4) ].min
      hint = 100 if hint < 100
      InsufficientMemory.new(
        "Monte Carlo failed with #{n_paths} paths (R closed or timed out — often low memory). " \
        "Try #{hint} or fewer paths."
      )
    end
  end
end
