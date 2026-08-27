# frozen_string_literal: true

# Build column hashes for Galaaz / R from SQLite historical prices.
module Risk
  class ReturnPanel
    Row = Struct.new(:traded_at, :ticker, :daily_return, :weight, keyword_init: true)

    def self.from_portfolio(portfolio, limit_per_asset: nil)
      new(portfolio, limit_per_asset: limit_per_asset).rows
    end

    def initialize(portfolio, limit_per_asset: nil)
      @portfolio = portfolio
      @limit_per_asset = limit_per_asset
    end

    def rows
      @portfolio.assets.includes(:historical_prices).flat_map do |asset|
        scope = asset.historical_prices.order(:traded_at)
        scope = scope.limit(@limit_per_asset) if @limit_per_asset
        scope.pluck(:traded_at, :daily_return).filter_map do |traded_at, daily_return|
          next if daily_return.nil?

          {
            "traded_at" => traded_at.iso8601,
            "ticker" => asset.ticker,
            "daily_return" => daily_return,
            "weight" => asset.weight.to_f
          }
        end
      end
    end
  end
end
