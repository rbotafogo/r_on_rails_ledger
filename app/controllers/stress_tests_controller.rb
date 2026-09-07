# frozen_string_literal: true

class StressTestsController < ApplicationController
  def create
    portfolio = Portfolio.find(params[:portfolio_id])
    runtime = normalize_runtime(params[:runtime])
    session[:risk_runtime] = runtime

    mc_paths = normalize_mc_paths(params[:mc_paths])
    session[:mc_paths] = mc_paths

    stress_test = portfolio.stress_tests.create!(status: "pending")
    StressTestJob.perform_later(stress_test.id, runtime, mc_paths)

    respond_to do |format|
      format.turbo_stream do
        if inline_on_portfolio_show?(portfolio)
          render turbo_stream: turbo_stream.replace(
            "stress_test_results",
            partial: "stress_tests/results",
            locals: { stress_test: stress_test }
          )
        else
          redirect_to portfolio_path(portfolio), status: :see_other
        end
      end
      format.html { redirect_to portfolio_path(portfolio), status: :see_other }
    end
  end

  private

  def normalize_runtime(value)
    value.to_s == "docker" ? "docker" : "local"
  end

  def normalize_mc_paths(value)
    n = value.to_i
    return Risk::McPaths.suggested_default if n <= 0

    n
  end

  def inline_on_portfolio_show?(portfolio)
    return true if params[:inline].present?

    referer = request.referer.to_s
    referer.match?(%r{/portfolios/#{portfolio.id}(?:\?|#|$)})
  end
end
