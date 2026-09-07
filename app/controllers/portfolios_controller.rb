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
    @mc_paths_default = session[:mc_paths].presence&.to_i
    @mc_paths_default = Risk::McPaths.suggested_default if @mc_paths_default.nil? || @mc_paths_default <= 0
    @mc_mem_mib = Risk::McPaths.mem_available_mib
    @mc_max_safe = Risk::McPaths.max_safe
  end
end
