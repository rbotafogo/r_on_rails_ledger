# frozen_string_literal: true

require "open3"
require "galaaz"
require "new_bridge"

module Risk
  # Dual container R: historical on 3.6.3, Monte Carlo on 4.3.3 (rocker-based images).
  # Never raises for missing Docker — returns a status object for UI messaging.
  class DockerEngines
    HIST_IMAGE = ENV.fetch("LEDGER_R_HIST_IMAGE", "galaaz/r-bridge:3.6.3")
    MC_IMAGE = ENV.fetch("LEDGER_R_MC_IMAGE", "galaaz/r-bridge:4.3.3")
    HIST_BASE = ENV.fetch("LEDGER_R_HIST_BASE", "rocker/r-ver:3.6.3")
    MC_BASE = ENV.fetch("LEDGER_R_MC_BASE", "rocker/r-ver:4.3.3")
    HIST_VERSION = "3.6.3"
    MC_VERSION = "4.3.3"

    Status = Struct.new(
      :available, :images_ready, :notice, :mode,
      keyword_init: true
    )

    def self.docker_ok?
      system("docker info >/dev/null 2>&1")
    end

    def self.image_exists?(tag)
      system("docker image inspect #{tag} >/dev/null 2>&1")
    end

    # Probe Docker capability (independent of user preference).
    def self.probe
      unless docker_ok?
        return Status.new(
          available: false,
          images_ready: false,
          mode: "unavailable",
          notice: "Docker is not available. Dual-version R (#{HIST_VERSION} + #{MC_VERSION}) needs Docker. " \
                  "Use Local R, or start Docker and run: bin/setup_docker_r_engines"
        )
      end

      missing = []
      missing << HIST_IMAGE unless image_exists?(HIST_IMAGE)
      missing << MC_IMAGE unless image_exists?(MC_IMAGE)
      if missing.any?
        return Status.new(
          available: true,
          images_ready: false,
          mode: "images_missing",
          notice: "Docker is up, but bridge images are missing (#{missing.join(', ')}). " \
                  "Run: bin/setup_docker_r_engines"
        )
      end

      Status.new(available: true, images_ready: true, mode: "ready", notice: nil)
    end

    def self.ensure_images!(out: $stdout)
      raise "Docker is not available" unless docker_ok?

      {
        HIST_IMAGE => HIST_BASE,
        MC_IMAGE => MC_BASE
      }.each do |tag, base|
        if image_exists?(tag)
          out.puts("[docker-r] image ready: #{tag}")
          next
        end
        out.puts("[docker-r] building #{tag} FROM #{base} (Rcpp) — this can take several minutes…")
        dockerfile = <<~DOCKERFILE
          FROM #{base}
          RUN R -q -e "install.packages(c('Rcpp','arrow'), repos='https://cloud.r-project.org/')"
        DOCKERFILE
        _stdout, stderr, st = Open3.capture3(
          "docker", "build", "-t", tag, "-f", "-", ".",
          stdin_data: dockerfile,
          chdir: RJsonJob.galaaz_root
        )
        raise "Failed to build #{tag}: #{stderr}" unless st.success?

        out.puts("[docker-r] built #{tag}")
      end
    end

    # Two managers → parallel container cold-start + concurrent evals.
    def self.with_dual_containers(accept_timeout: 90)
      source = RJsonJob.gatekeeper_source
      hist_mgr = NewBridge::RInstanceManager.new(source_path: source, out: $stdout)
      mc_mgr = NewBridge::RInstanceManager.new(source_path: source, out: $stdout)
      hist_err = nil
      mc_err = nil

      hist_t = Thread.new do
        hist_mgr.spawn(
          runtime: "container",
          instance_id: "ledger-hist",
          version: HIST_VERSION,
          image: HIST_IMAGE,
          accept_timeout: accept_timeout
        )
      rescue StandardError => e
        hist_err = e
      end
      mc_t = Thread.new do
        mc_mgr.spawn(
          runtime: "container",
          instance_id: "ledger-mc",
          version: MC_VERSION,
          image: MC_IMAGE,
          accept_timeout: accept_timeout
        )
      rescue StandardError => e
        mc_err = e
      end
      hist_t.join
      mc_t.join
      raise hist_err if hist_err
      raise mc_err if mc_err

      hist_eval = RJsonJob.client_eval_proc(hist_mgr, "ledger-hist")
      mc_eval = RJsonJob.client_eval_proc(mc_mgr, "ledger-mc")
      yield hist_mgr, mc_mgr, hist_eval, mc_eval
    ensure
      hist_mgr&.stop_all(force_container: true)
      mc_mgr&.stop_all(force_container: true)
    end

    # Two local R processes for true concurrent eval (avoids single-bridge serialization).
    def self.with_dual_local
      source = RJsonJob.gatekeeper_source
      hist_mgr = NewBridge::RInstanceManager.new(source_path: source, out: $stdout)
      mc_mgr = NewBridge::RInstanceManager.new(source_path: source, out: $stdout)

      hist_mgr.spawn(runtime: "local", instance_id: "local-hist", version: "local")
      mc_mgr.spawn(runtime: "local", instance_id: "local-mc", version: "local")

      hist_eval = RJsonJob.client_eval_proc(hist_mgr, "local-hist")
      mc_eval = RJsonJob.client_eval_proc(mc_mgr, "local-mc")
      yield hist_mgr, mc_mgr, hist_eval, mc_eval
    ensure
      hist_mgr&.stop_all(force_container: true)
      mc_mgr&.stop_all(force_container: true)
    end
  end
end
