# Implementation plan

Phased checklist. Do not skip honesty gates in [architecture.md](architecture.md).

## Phase 0 — Scaffold (done when this repo boots)

- [x] Rails 8.1 app at `/home/rbotafogo/desenv_linux/r_on_rails_ledger`
- [x] CRuby or JRuby (host / mise Ruby; no `.ruby-version` pin — Omarchy-friendly; Bundler picks SQLite stack)
- [x] SQLite + Hotwire + Tailwind + Solid Queue/Cache/Cable gems
- [x] Path gem `galaaz` → `../galaaz`
- [x] Self-contained `docs/`
- [x] `bin/rails db:prepare` verified on a clean shell
- [x] Gatekeeper built (`make -C ../galaaz/ext/new_bridge all`)
- [x] `bin/rails runner` Galaaz smoke (`R::Support.eval('R.version.string')`)

## Phase 1 — Ledger schema + seed + single-engine stress test

- [x] Migration: `portfolios`, `assets`, `historical_prices`, `stress_tests`
      (JSON payload columns as needed — see [engines_and_dashboard.md](engines_and_dashboard.md))
- [x] Models + validations (weights sum ≈ 1.0 optional warning)
- [x] Seed script: one demo portfolio, several tickers, **large** `historical_prices`
      following [data_and_seeding.md](data_and_seeding.md) (GBM, `insert_all`, ~1M rows;
      start with `SEED_PROFILE=fast` if needed)
- [x] `PortfoliosController#show` + “Run stress test” button
- [x] `StressTestsController#create` → enqueue `StressTestJob`
- [x] Active Job `:async` in development (same-process; Cable broadcasts work). Solid Queue
      gem present for production / optional `SOLID_QUEUE_IN_PUMA` later
- [x] Job: load returns → Galaaz → historical VaR / ES → chart payload
      (Plotly JSON via Arrow IPC / table_from + Ruby DSL `R.quantile` / `R.density`; IPC/Feather for Docker)
- [x] Turbo Stream replace of `#stress_test_results`
- [x] Persist status: `pending` → `calculating` → `completed` / `failed`

**Exit criteria:** one click produces metrics + chart without refreshing the page.

## Phase 2 — Dual R engines

- [x] `stress_test_runs` for Engine A vs B payloads
- [x] Dual orchestrator (sequential on shared Galaaz bridge by default;
      `RISK_PARALLEL_ENGINES=1` for threaded fan-out — R still serializes on one process)
- [x] Engine A: historical VaR/ES, density, rolling VaR + breaches
- [x] Engine B: Monte Carlo GBM forward paths, quantiles, terminal density
- [x] Job fan-out + KPI delta table + three Plotly charts
- [x] Runbook notes for `MC_PATHS` / dual engines
- [x] Optional: `RInstanceManager` + Docker rocker images for true multi-version R
      (R 3.6.3 historical + R 4.3.3 Monte Carlo; graceful local fallback + UI notice)

**Exit criteria:** one click shows both engines’ outputs; failure of one engine is visible.

## Phase 3 — Pitch polish

- [x] Demo seed profile (“fast” vs “wow” row counts) — `db/seeds.rb` + [data_and_seeding.md](data_and_seeding.md)
- [x] Pitch script (2–3 minutes) in [runbook.md](runbook.md)
- [x] Gemfile / README note for RubyGems `galaaz` (no path) install

## Phase 4 — Optional enrichments (explicitly later)

- [ ] Pluggy (or other) live ingest into `historical_prices`
- [ ] Auth / multi-portfolio tenancy
- [ ] Plotly from R only if Hotwire+SVG is not enough
- [x] App-local helpers mimicking nicer Arrow loaders (`Risk::ReturnPanel.column_hash` + `Galaaz::ArrowIpc`) — **app code**, not fake gem APIs

## Non-goals (do not schedule as “missing demo features”)

- Reimplementing Galaaz inside this app
- True shared-memory zero-copy Ruby↔R
- Replacing Solid Queue with Sidekiq/Redis “because scale”
