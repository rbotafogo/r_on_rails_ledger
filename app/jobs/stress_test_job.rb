# frozen_string_literal: true

class StressTestJob < ApplicationJob
  queue_as :default

  # runtime: "local" (default, fast) or "docker" (R 3.6.3 + 4.3.3)
  # mc_paths: optional Monte Carlo path count from the UI (nil → memory-based default)
  def perform(stress_test_id, runtime = "local", mc_paths = nil)
    test = StressTest.find(stress_test_id)
    test.update!(status: "calculating", error_message: nil)
    test.stress_test_runs.destroy_all

    hist_run = test.stress_test_runs.create!(engine: "historical", status: "calculating")
    mc_run = test.stress_test_runs.create!(engine: "monte_carlo", status: "calculating")
    broadcast!(test)

    limit = ENV["STRESS_LIMIT_PER_ASSET"].presence&.to_i
    rows = Risk::ReturnPanel.from_portfolio(test.portfolio, limit_per_asset: limit)
    portfolio_value = test.portfolio.total_value || 1_000_000

    outcome = Risk::DualOrchestrator.call(
      rows,
      portfolio_value: portfolio_value,
      preferred: runtime,
      mc_paths: mc_paths
    )

    if outcome.historical
      h = outcome.historical
      hist_run.update!(
        status: "completed",
        var_95: h.var_95,
        var_99: h.var_99,
        expected_shortfall: h.expected_shortfall,
        elapsed_ms: h.elapsed_ms,
        payload: h.payload
      )
    else
      hist_run.update!(status: "failed", error_message: outcome.errors["historical"])
    end

    if outcome.monte_carlo
      m = outcome.monte_carlo
      mc_run.update!(
        status: "completed",
        var_95: m.payload["var_95"],
        var_99: m.payload["var_99"],
        sim_var_30d: m.sim_var_30d,
        sim_expected_max_drawdown: m.sim_expected_max_drawdown,
        tail_risk_probability: m.tail_risk_probability,
        elapsed_ms: m.elapsed_ms,
        payload: m.payload
      )
    else
      mc_run.update!(status: "failed", error_message: outcome.errors["monte_carlo"])
    end

    both_failed = hist_run.failed? && mc_run.failed?
    test.update!(
      status: both_failed ? "failed" : "completed",
      error_message: both_failed ? outcome.errors.values.join(" | ") : nil,
      var_95: hist_run.var_95,
      var_99: hist_run.var_99,
      expected_shortfall: hist_run.expected_shortfall,
      sim_var_30d: mc_run.sim_var_30d,
      sim_expected_max_drawdown: mc_run.sim_expected_max_drawdown,
      tail_risk_probability: mc_run.tail_risk_probability,
      historical_elapsed_ms: hist_run.elapsed_ms,
      monte_carlo_elapsed_ms: mc_run.elapsed_ms,
      wall_elapsed_ms: outcome.wall_elapsed_ms,
      elapsed_ms: outcome.wall_elapsed_ms,
      chart_payload: {
        "historical" => hist_run.payload,
        "monte_carlo" => mc_run.payload,
        "errors" => outcome.errors,
        "runtime" => outcome.runtime
      }
    )

    broadcast!(test)
  rescue StandardError => e
    test&.update!(status: "failed", error_message: e.message)
    broadcast!(test) if test
    raise
  end

  private

  def broadcast!(test)
    return unless test

    test = StressTest.includes(:stress_test_runs).find(test.id)
    Turbo::StreamsChannel.broadcast_replace_to(
      "portfolio_#{test.portfolio_id}",
      target: "stress_test_results",
      partial: "stress_tests/results",
      locals: { stress_test: test }
    )
  end
end
