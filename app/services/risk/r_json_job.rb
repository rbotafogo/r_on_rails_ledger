# frozen_string_literal: true

require "json"
require "securerandom"
require "galaaz"

module Risk
  # Shared portfolio aggregation + remote R eval adapter.
  # Tabular handoff lives in Risk::ArrowHandoff (Arrow IPC / table_from / Feather), not CSV.
  module RJsonJob
    module_function

    def galaaz_root
      spec = Gem.loaded_specs["galaaz"]
      return spec.full_gem_path if spec

      File.expand_path("../galaaz", Rails.root)
    end

    def gatekeeper_source
      ENV.fetch("GALAAZ_NEW_BRIDGE_SOURCE") do
        File.join(galaaz_root, "ext/new_bridge/galaaz_gatekeeper_phase1.cpp")
      end
    end

    def portfolio_returns(rows)
      by_time = Hash.new { |h, k| h[k] = 0.0 }
      rows.each do |row|
        by_time[row["traded_at"]] += row["daily_return"].to_f * row["weight"].to_f
      end
      times = by_time.keys.sort
      [ times, times.map { |t| by_time[t] } ]
    end

    def eval_r!(code, eval: nil)
      if eval
        eval.call(code)
      else
        R::Support.eval(code)
      end
    end

    def client_eval_proc(manager, instance_id, timeout: 300)
      lambda do |code|
        body = code.to_s.strip
        wrapped = body.start_with?("{") ? body : "{\n#{body}\n}"
        manager.eval_r(wrapped, session_id: "ledger", instance_id: instance_id, timeout: timeout)
        true
      end
    end
  end
end
