# frozen_string_literal: true

class PortfoliosController < ApplicationController
  def index
    @portfolios = Portfolio.includes(:assets).order(:name)
    @price_count = HistoricalPrice.count
    @risk_runtime = session[:risk_runtime].presence || "local"
    @docker_status = Risk::DockerEngines.probe
  end

  def show
    @portfolio = Portfolio.find(params[:id])
    @assets = @portfolio.assets.order(:ticker)
    @stress_test = @portfolio.stress_tests.includes(:stress_test_runs).order(created_at: :desc).first
    @price_count = HistoricalPrice.joins(:asset).where(assets: { portfolio_id: @portfolio.id }).count
    @risk_runtime = session[:risk_runtime].presence || "local"
    @docker_status = Risk::DockerEngines.probe
  end
end
