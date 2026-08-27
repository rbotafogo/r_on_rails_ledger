# Data and seeding design

Synthetic market data for the R-on-Rails Ledger stress-test demo. **Not** live broker data
(Pluggy / exchange feeds are a later optional enrichment).

## Goal

Seed about **1,000,000** price/return rows that behave like markets enough for Value at Risk
and Monte Carlo work in GNU R: realistic drift, asset-specific volatility, and fat-ish tails
from GBM shocks — without spending minutes on ActiveRecord-per-row inserts.

## Row shape (`historical_prices`)

| Column | Type | Example | Purpose |
|--------|------|---------|---------|
| `asset_id` | integer FK | `3` | Links to `assets` |
| `trade_date` / `traded_at` | date or datetime | `2024-06-12 14:31:00` | Time index of the bar |
| `adjusted_close` | float | `182.45` | Synthetic price (GBM path) |
| `daily_return` | float | `-0.0142` | Log return \(\ln(P_t / P_{t-1})\) (precomputed) |
| `volume` | integer (optional) | `4_230_000` | Liquidity weighting; include in schema if we keep it |

Index: `[asset_id, trade_date]` (or `traded_at`).

Related tables (see implementation plan): `portfolios`, `assets` (ticker + weight),
`stress_tests` (job outputs).

## How we reach ~1M rows

Two acceptable layouts:

| Layout | Math | Use when |
|--------|------|----------|
| **A — high-frequency bars** | 10 assets × 100,000 steps | Pitch “lots of ticks”; timestamp = base + `step` × bar size (e.g. minutes), **not** `step.days` |
| **B — daily panel** | ~50 assets × ~20,000 trading days | Pitch “multi-year daily history”; step business days |

**Default for v1 seed:** Layout **A** (matches the Gemini sketch: 10 liquid names, 100k steps).

Do **not** use `base_date + step.days` for 100k steps (~274 calendar years). That breaks the
“market history” story even though the math still runs.

## Price model: Geometric Brownian Motion (GBM)

Per asset, choose annual drift \(\mu\) and volatility \(\sigma\). With step size \(\Delta t\)
(e.g. \(1/252\) for a daily fraction, or a smaller fraction for intraday bars):

\[
S_t = S_{t-1} \times \exp\left( \left(\mu - \frac{\sigma^2}{2}\right)\Delta t + \sigma \sqrt{\Delta t}\, Z_t \right),
\quad Z_t \sim \mathcal{N}(0,1)
\]

Store both `adjusted_close` (\(S_t\)) and `daily_return` (the exponent increment / log return
for that step) so R can build return matrices without recomputing logs.

Generate \(Z_t\) with a standard normal (Box–Muller is fine in pure Ruby; or any solid RNG).

## Suggested asset book (weights sum to 1.0)

| Ticker | Base price | µ | σ | Weight |
|--------|------------|---|---|--------|
| SPY | 500 | 0.08 | 0.15 | 0.25 |
| QQQ | 440 | 0.12 | 0.22 | 0.20 |
| TLT | 95 | 0.03 | 0.12 | 0.15 |
| GLD | 215 | 0.05 | 0.14 | 0.15 |
| NVDA | 120 | 0.25 | 0.45 | 0.10 |
| BND | 72 | 0.02 | 0.06 | 0.05 |
| EEM | 42 | 0.06 | 0.20 | 0.05 |
| XOM | 110 | 0.07 | 0.24 | 0.02 |
| JNJ | 155 | 0.04 | 0.11 | 0.02 |
| BTC | 65_000 | 0.35 | 0.65 | 0.01 |

Portfolio label (demo): e.g. “Global Sovereign & Macro Allocation”, `total_value` ~ 250e6.

## Fast seed technique (SQLite)

Instantiating 1M ActiveRecord objects one-by-one is too slow. Target: **seconds**, not minutes.

1. One `ActiveRecord::Base.transaction`
2. SQLite pragmas for bulk load: `PRAGMA journal_mode = WAL;`, `PRAGMA synchronous = NORMAL;`
3. Create portfolio + assets with normal AR (`create!`)
4. Build hashes in memory; flush with `HistoricalPrice.insert_all(batch)` every ~25_000 rows
5. Assert `HistoricalPrice.count` and that weights sum to 1.0 (± epsilon)

Pseudo-structure for `db/seeds.rb` (implement in Phase 1 — not wired yet):

```ruby
# Outline only — real file lands with migrations in Phase 1
ActiveRecord::Base.transaction do
  connection.execute("PRAGMA journal_mode = WAL;")
  connection.execute("PRAGMA synchronous = NORMAL;")

  portfolio = Portfolio.create!(...)
  assets = asset_configs.map { |cfg| portfolio.assets.create!(...) }

  batch = []
  assets.each_with_index do |asset, idx|
    # GBM loop for num_steps; append hashes; insert_all when batch full
  end
  HistoricalPrice.insert_all(batch) if batch.any?
end
```

### Seed profiles (`SEED_PROFILE`)

| Profile | Steps / asset | Approx rows (10 assets) | When to use |
|---------|---------------|-------------------------|-------------|
| `fast` (default) | 2_000 | ~20k | Laptop pitches, CI, day-to-day |
| `wow` | 100_000 | ~1M | Stage / “serious panel” line |

```bash
SEED_PROFILE=fast bin/rails db:seed
SEED_PROFILE=wow  bin/rails db:seed
```

Debug without re-seeding: cap rows loaded into the job with `STRESS_LIMIT_PER_ASSET`
(e.g. `STRESS_LIMIT_PER_ASSET=500`).

## What we say on stage

> “One million synthetic bars from geometric Brownian motion with asset-specific volatilities —
> seeded into SQLite in seconds — so R can run real VaR / stress math on a serious panel.”

## What we do **not** claim

- That these are historical exchange prints
- Cross-asset correlation structure beyond independent GBM shocks (correlated residuals can be
  a later enhancement if R-side risk needs a full covariance story)
- Zero-copy load from SQLite into R (see [architecture.md](architecture.md))

## Implementation status

- [x] Design captured here
- [x] Migration + models
- [x] `db/seeds.rb` implementing this outline (`SEED_PROFILE=fast|wow`)
- [ ] Optional: record wall-clock for `SEED_PROFILE=wow` on your demo laptop (fill into runbook)
