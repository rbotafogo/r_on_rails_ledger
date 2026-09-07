# Product scenario — portfolio stress-testing ledger

## One sentence

A single developer runs a **family-office style** portfolio ledger on **vanilla Rails 8**:
SQLite holds the book, Solid Queue orchestrates risk jobs, Hotwire streams results, and
**Galaaz** runs the hard statistics in **GNU R** (optionally two R engines at once).

## Who it is for

- **Primary:** an R-fluent investment / risk person who wants a web product without hiring
  a full stack + data-platform team.
- **Secondary:** a Rails developer who needs CRAN-quality math without rewriting it in Ruby.

## User story (demo click path)

1. Open a portfolio page (assets + weights).
2. Click **Run stress test**.
3. Rails creates a `StressTest` row and enqueues a Solid Queue job.
4. The job loads historical returns from SQLite, hands them to R (Arrow IPC file when the Ruby
   backend is present, otherwise a copy into an R-side Arrow table),
   and runs risk models.
5. **Engine A** — historical VaR / Expected Shortfall style metrics (e.g. PerformanceAnalytics).
6. **Engine B** (phase 2+) — Monte Carlo / denser simulation on a second R process or container.
7. Turbo Stream + Solid Cable replace the results panel with metrics and a ggplot2 SVG
   (no full page reload, no React).

## Data on disk (SQLite)

Normalized ledger (to be migrated in phase 1):

| Table | Role |
|-------|------|
| `portfolios` | Named book / account |
| `assets` | Tickers + weights per portfolio |
| `historical_prices` | Daily (or hourly) prices / returns — seed toward large N for the pitch |
| `stress_tests` | Job status + risk outputs (`var_95`, `var_99`, `expected_shortfall`, plot, errors) |

Optional later: `stress_test_runs` for per-engine results when A and B run in parallel.

## What “success” looks like on stage

> With Galaaz, a single developer builds a family-office stress tester on vanilla Rails 8 and
> SQLite: Solid Queue orchestrates concurrent GNU R containers, Hotwire streams the risk
> dashboard live, and the math stays in R — no Python microservice fleet.

## Explicitly out of scope for v1

- Live Pluggy / broker API ingestion (seed or CSV first; Pluggy as a later enrichment)
- Claiming true shared-memory “zero-copy” Arrow across the Ruby↔R boundary
- Multi-tenant SaaS hardening, auth productization, payment billing
