# frozen_string_literal: true

require "fileutils"
require "open3"
require "securerandom"
require "tempfile"
require "galaaz"

module Risk
  # Ruby ↔ R tabular handoff via Apache Arrow, not CSV.
  #
  # Local / default Galaaz bridge:
  #   Stage B1 when Galaaz::ArrowIpc is available (red-arrow / Arrow Java): write an IPC
  #   file, R::Arrow.open_ipc, only the path crosses NewBridge. Else Stage A:
  #   data.frame + R::Arrow.table_from (copy into R).
  #   Stage B2: optional Galaaz::ArrowIpc.read after R::Arrow.write_ipc (density → Plotly).
  #
  # Docker / remote eval: Ruby may write returns.arrow (IPC) without using the long-lived
  # bridge; Rscript still writes RDS + Feather so older container Arrow can fall back.
  # Do not re-enter the Galaaz bridge from ActiveJob solely to write those files.
  module ArrowHandoff
    module_function

    def ipc_available?
      Galaaz::ArrowIpc.available?
    rescue StandardError
      false
    end

    def local_handoff_tag
      ipc_available? ? "arrow_ipc" : "arrow_table"
    end

    def ensure_arrow!
      ok = R::Support.eval("isTRUE(requireNamespace('arrow', quietly = TRUE))")
      flag = ok.respond_to?(:>>) ? (ok >> 0) : ok
      return if flag == true

      raise "R package 'arrow' is required. Install in GNU R: install.packages('arrow')"
    end

    # Columnar portfolio returns → Arrow Table handle in the current R process.
    def to_returns_table(port_returns)
      ensure_arrow!
      floats = port_returns.map(&:to_f)
      if ipc_available?
        path = Galaaz::ArrowIpc.write("daily_return" => floats)
        begin
          R::Arrow.open_ipc(path)
        ensure
          Galaaz::ArrowIpc.release(path)
        end
      else
        df = R::Support.exec_function("data.frame", { daily_return: floats })
        R::Arrow.table_from(df)
      end
    end

    # Arrow Table → numeric vector of daily_return (still an R handle).
    def to_returns_numeric(port_returns)
      tbl = to_returns_table(port_returns)
      R.as__numeric(R.dplyr___collect(tbl)[["daily_return"]])
    end

    # Kernel density x/y for Plotly. Prefer Stage B2 (R writes IPC, Ruby reads) when the
    # Ruby Arrow backend is loaded; otherwise unbox dens$x / dens$y over the bridge.
    def density_xy_for_plotly(returns_vec, n: 128)
      dens = R.density(returns_vec, n: n)
      if ipc_available?
        begin
          xy = R.data__frame(x: dens.x, y: dens.y)
          path = R::Arrow.write_ipc(xy)
          cols = Galaaz::ArrowIpc.read(path)
          Galaaz::ArrowIpc.release(path)
          xs = Array(cols["x"] || cols["X"]).map { |v| v&.to_f }
          ys = Array(cols["y"] || cols["Y"]).map { |v| v&.to_f }
          return xs.zip(ys).map { |x, y| { "x" => x, "y" => y } } if xs.size == ys.size && xs.any?
        rescue StandardError
          # fall through to proxy unbox
        end
      end

      xs = RValues.float_array(dens.x)
      ys = RValues.float_array(dens.y)
      xs.zip(ys).map { |x, y| { "x" => x, "y" => y } }
    end

    # Remote-safe scratch: RDS always; Feather when host Rscript has arrow; IPC when
    # Galaaz::ArrowIpc can write from Ruby. Yields a Hash:
    #   :ipc, :feather, :rds (paths inside the R process), :r_out, :host_out
    def with_returns_remote(port_returns, mode: :docker)
      id = SecureRandom.hex(8)
      host_dir = File.join(RJsonJob.galaaz_root, "tmp", "r_on_rails_ledger", id)
      FileUtils.mkdir_p(host_dir)
      host_rds = File.join(host_dir, "returns.rds")
      host_feather = File.join(host_dir, "returns.feather")
      host_ipc = File.join(host_dir, "returns.arrow")
      host_out = File.join(host_dir, "result.json")

      write_returns_files!(
        port_returns,
        host_rds: host_rds,
        host_feather: host_feather,
        host_ipc: host_ipc
      )

      prefix =
        if mode.to_sym == :docker
          "/workspace/tmp/r_on_rails_ledger/#{id}"
        else
          host_dir
        end
      r_rds = "#{prefix}/returns.rds"
      r_feather = File.file?(host_feather) ? "#{prefix}/returns.feather" : nil
      r_ipc = File.file?(host_ipc) ? "#{prefix}/returns.arrow" : nil
      r_out = "#{prefix}/result.json"

      begin
        yield({ ipc: r_ipc, feather: r_feather, rds: r_rds, r_out: r_out, host_out: host_out })
      ensure
        FileUtils.rm_rf(host_dir)
      end
    end

    # R snippet: set `x` (numeric) and `handoff` (arrow_ipc | arrow_feather | rds_fallback).
    def remote_load_returns_r(paths)
      ipc = paths[:ipc]
      feather = paths[:feather]
      rds = paths[:rds]
      ipc_try =
        if ipc
          <<~R
            if (is.null(x) && file.exists(#{ipc.inspect}) && isTRUE(requireNamespace("arrow", quietly = TRUE))) {
              tbl <- try(arrow::read_ipc_file(#{ipc.inspect}, as_data_frame = TRUE), silent = TRUE)
              if (!inherits(tbl, "try-error")) {
                x <- as.numeric(tbl[["daily_return"]])
                handoff <- "arrow_ipc"
              }
            }
          R
        else
          ""
        end
      feather_try =
        if feather
          <<~R
            if (is.null(x) && file.exists(#{feather.inspect}) && isTRUE(requireNamespace("arrow", quietly = TRUE))) {
              tbl <- arrow::read_feather(#{feather.inspect})
              x <- as.numeric(tbl[["daily_return"]])
              handoff <- "arrow_feather"
            }
          R
        else
          ""
        end

      <<~R
        x <- NULL
        handoff <- "rds_fallback"
        #{ipc_try}
        #{feather_try}
        if (is.null(x)) {
          x <- as.numeric(readRDS(#{rds.inspect}))
          handoff <- "rds_fallback"
        }
      R
    end

    def write_returns_files!(port_returns, host_rds:, host_feather:, host_ipc: nil)
      if host_ipc && ipc_available?
        tmp_ipc = Galaaz::ArrowIpc.write("daily_return" => port_returns.map(&:to_f))
        FileUtils.mv(tmp_ipc, host_ipc)
      end

      scan_tmp = Tempfile.new(["ledger_returns", ".txt"])
      port_returns.each { |v| scan_tmp.puts(v) }
      scan_tmp.flush

      # One-shot R — do not use the long-lived Galaaz bridge from job threads.
      r = <<~R
        x <- scan(#{scan_tmp.path.inspect}, quiet = TRUE)
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
      scan_tmp&.close!
    end
  end
end
