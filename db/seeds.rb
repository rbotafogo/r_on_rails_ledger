# frozen_string_literal: true

# Seeds synthetic GBM paths. See docs/data_and_seeding.md.
#
#   SEED_PROFILE=fast bin/rails db:seed   # 10 assets × 2_000 steps  (default)
#   SEED_PROFILE=wow  bin/rails db:seed   # 10 assets × 100_000 steps (~1M rows)

require "benchmark"

profile = ENV.fetch("SEED_PROFILE", "fast")
num_steps = case profile
when "wow" then 100_000
when "fast" then 2_000
else
              Integer(ENV.fetch("SEED_STEPS", "2000"))
end

puts "== Seeding Financial Ledger (profile=#{profile}, steps/asset=#{num_steps}) =="

connection = ActiveRecord::Base.connection
connection.execute("PRAGMA journal_mode = WAL;")
connection.execute("PRAGMA synchronous = NORMAL;")

time = Benchmark.realtime do
  ActiveRecord::Base.transaction do
    StressTest.delete_all
    HistoricalPrice.delete_all
    Asset.delete_all
    Portfolio.delete_all

    portfolio = Portfolio.create!(
      name: "Global Sovereign & Macro Allocation",
      total_value: 250_000_000.00
    )

    asset_configs = [
      { ticker: "SPY",  base_price: 500.0, mu: 0.08, sigma: 0.15, weight: 0.25 },
      { ticker: "QQQ",  base_price: 440.0, mu: 0.12, sigma: 0.22, weight: 0.20 },
      { ticker: "TLT",  base_price: 95.0,  mu: 0.03, sigma: 0.12, weight: 0.15 },
      { ticker: "GLD",  base_price: 215.0, mu: 0.05, sigma: 0.14, weight: 0.15 },
      { ticker: "NVDA", base_price: 120.0, mu: 0.25, sigma: 0.45, weight: 0.10 },
      { ticker: "BND",  base_price: 72.0,  mu: 0.02, sigma: 0.06, weight: 0.05 },
      { ticker: "EEM",  base_price: 42.0,  mu: 0.06, sigma: 0.20, weight: 0.05 },
      { ticker: "XOM",  base_price: 110.0, mu: 0.07, sigma: 0.24, weight: 0.02 },
      { ticker: "JNJ",  base_price: 155.0, mu: 0.04, sigma: 0.11, weight: 0.02 },
      { ticker: "BTC",  base_price: 65_000.0, mu: 0.35, sigma: 0.65, weight: 0.01 }
    ]

    weight_sum = asset_configs.sum { |c| c[:weight] }
    raise "weights must sum to 1.0 (got #{weight_sum})" unless (weight_sum - 1.0).abs < 1e-9

    assets = asset_configs.map do |cfg|
      portfolio.assets.create!(ticker: cfg[:ticker], weight: cfg[:weight])
    end

    standard_normal = lambda do
      u1 = rand
      u2 = rand
      Math.sqrt(-2.0 * Math.log([ u1, 1e-15 ].max)) * Math.cos(2.0 * Math::PI * u2)
    end

    # Intraday-ish bars: 1-minute steps ending "now" (not step.days for 100k).
    bar = 1.minute
    base_time = Time.current - (num_steps * bar)
    dt = 1.0 / (252.0 * 390.0) # fraction of year per minute bar (approx)
    batch_size = 25_000
    batch = []

    assets.each_with_index do |asset, idx|
      cfg = asset_configs[idx]
      current_price = cfg[:base_price]
      mu = cfg[:mu]
      sigma = cfg[:sigma]

      num_steps.times do |step|
        z = standard_normal.call
        daily_return = (mu - 0.5 * (sigma**2)) * dt + sigma * Math.sqrt(dt) * z
        current_price *= Math.exp(daily_return)

        batch << {
          asset_id: asset.id,
          traded_at: base_time + (step * bar),
          adjusted_close: current_price.round(6),
          daily_return: daily_return.round(8),
          volume: (1_000_000 * (0.5 + rand)).to_i
        }

        if batch.size >= batch_size
          HistoricalPrice.insert_all(batch)
          batch.clear
        end
      end
    end

    HistoricalPrice.insert_all(batch) unless batch.empty?
  end
end

puts "== Seeded #{HistoricalPrice.count} rows across #{Asset.count} assets in #{time.round(2)}s =="
