# frozen_string_literal: true

require "fileutils"
require "open3"
require "securerandom"
require "tempfile"
require "galaaz"

module Risk
  # Ruby → R tabular handoff via Apache Arrow (R-side Table), not CSV.
  #
  # Local / default bridge: build an Arrow table in the attached R process (DSL path).
  # Remote eval (Docker): write via a one-shot `Rscript` subprocess (avoids re-entering
  # the long-lived Galaaz bridge from ActiveJob threads, which can deadlock), then
  # prefer Feather when the container has {arrow}, else base-R readRDS.
  module ArrowHandoff
    module_function

    def ensure_arrow!
      ok = R::Support.eval("isTRUE(requireNamespace('arrow', quietly = TRUE))")
      flag = ok.respond_to?(:>>) ? (ok >> 0) : ok
      return if flag == true

      raise "R package 'arrow' is required. Install in GNU R: install.packages('arrow')"
    end

    # Columnar portfolio returns → Arrow Table handle in the current R process.
    def to_returns_table(port_returns)
      ensure_arrow!
      df = R::Support.exec_function("data.frame", { daily_return: port_returns.map(&:to_f) })
      R::Arrow.table_from(df)
    end

    # Arrow Table → numeric vector of daily_return (still an R handle).
    def to_returns_numeric(port_returns)
      tbl = to_returns_table(port_returns)
      R.as__numeric(R.dplyr___collect(tbl)[["daily_return"]])
    end

    # Remote-safe scratch: RDS always; Feather when host Rscript has arrow.
    # Yields [r_feather_or_nil, r_rds, r_out, host_out, host_dir].
    def with_returns_remote(port_returns, mode: :docker)
      id = SecureRandom.hex(8)
      host_dir = File.join(RJsonJob.galaaz_root, "tmp", "r_on_rails_ledger", id)
      FileUtils.mkdir_p(host_dir)
      host_rds = File.join(host_dir, "returns.rds")
      host_feather = File.join(host_dir, "returns.feather")
      host_out = File.join(host_dir, "result.json")

      write_returns_files!(port_returns, host_rds: host_rds, host_feather: host_feather)

      prefix =
        if mode.to_sym == :docker
          "/workspace/tmp/r_on_rails_ledger/#{id}"
        else
          host_dir
        end
      r_rds = "#{prefix}/returns.rds"
      r_feather = File.file?(host_feather) ? "#{prefix}/returns.feather" : nil
      r_out = "#{prefix}/result.json"

      begin
        yield r_feather, r_rds, r_out, host_out
      ensure
        FileUtils.rm_rf(host_dir)
      end
    end

    def write_returns_files!(port_returns, host_rds:, host_feather:)
      tmp = Tempfile.new(["ledger_returns", ".txt"])
      port_returns.each { |v| tmp.puts(v) }
      tmp.flush

      # One-shot R — do not use the long-lived Galaaz bridge from job threads.
      r = <<~R
        x <- scan(#{tmp.path.inspect}, quiet = TRUE)
        saveRDS(x, #{host_rds.inspect})
        if (isTRUE(requireNamespace("arrow", quietly = TRUE))) {
          arrow::write_feather(data.frame(daily_return = x), #{host_feather.inspect})
        }
        invisible(TRUE)
      R
      out, err, st = Open3.capture3("Rscript", "--vanilla", "-e", r)
      unless st.success? && File.file?(host_rds)
        raise "Rscript handoff failed (status=#{st.exitstatus}): #{err.presence || out}"
      end
    ensure
      tmp&.close!
    end
  end
end
