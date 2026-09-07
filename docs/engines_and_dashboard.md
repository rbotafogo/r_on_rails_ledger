# Engines and dashboard design

Target UX for the stress-test demo once Phase 1–2 land. **Design only** — jobs and views
are not implemented yet.

## Pitch shape

One click runs **two specialized R engines** on the **same** portfolio return panel. Rails
collects both payloads, stores them on SQLite, and Turbo-streams a **side-by-side risk
dashboard** (KPI cards + charts).

Honest data path (see [architecture.md](architecture.md)):

1. Job loads returns from SQLite (batched pluck / find_each — **not** `pluck_to_arrow`).
2. One bulk handoff into R via **`Galaaz::ArrowIpc` + `R::Arrow.open_ipc`** (Stage B) or
   `R::Arrow.from_ruby_batches` / `table_from` (Stage A), or Feather/RDS in Docker.
3. Engine A / Engine B each compute and return **structured results** (hashes / arrays /
   JSON-serializable payloads Ruby can store and feed to the browser).
4. Solid Cable + Turbo Stream replace the dashboard partial.

Do **not** claim zero-copy Arrow pointers or `R.assign_arrow` unless we add those helpers
in this app later.

---

## Container A — Historical model engine

**Role:** Empirical risk from history (e.g. PerformanceAnalytics-style VaR / ES).  
**Suggested runtime:** older or “legacy” R image (e.g. rocker 4.0.x) for the dual-version story.

### Inputs

Same tabular panel for all engines: dates, tickers (or asset ids), `daily_return`
(and weights from `assets` when building portfolio returns).

### Outputs returned to Ruby

| Field | Meaning |
|-------|---------|
| `var_95`, `var_99` | Empirical historical VaR (document sign convention: usually negative loss) |
| `expected_shortfall` | ES / CVaR at agreed level (e.g. 95%) |
| `empirical_density` | Array of `{x, y}` bin or KDE coordinates for historical portfolio returns |
| `rolling_var_series` | Time series: date → trailing 252-day historical VaR level |
| `breach_points` | Dates (or indices) where realized return crossed below the rolling VaR |
| `elapsed_ms` | Wall time inside this engine |

Optional later: gaussian VaR as a second series for “fat-tail divergence” vs historical.

---

## Container B — Forward simulation engine

**Role:** Forward-looking stress (Monte Carlo; GARCH / time-varying vol when we are ready).  
**Suggested runtime:** newer R image (e.g. rocker 4.5.x).

### Core calculation (v1 target)

- ~**50,000** paths  
- **30-day** forward horizon  
- Time-varying volatility if feasible; otherwise GBM / bootstrap with clear labeling  

### Outputs returned to Ruby

| Field | Meaning |
|-------|---------|
| `sim_var_30d` | Simulated 30-day VaR (define horizon vs 1-day clearly on the card) |
| `sim_expected_max_drawdown` | Expected maximum drawdown over the horizon |
| `tail_risk_probability` | P(breach) or similar scalar (define formula in code comments) |
| `sample_paths` | ~**100** representative trajectories: `{t, value}[]` each |
| `quantile_envelopes` | Per day 0..30: p05, p25, p50, p75, p95 |
| `terminal_distribution` | `{x, y}` density/hist of portfolio value at day 30 |
| `elapsed_ms` | Wall time inside this engine |

---

## Ruby dashboard (collector)

When **both** engines finish (two jobs, or one job with fan-out + wait), update
`stress_tests` / `stress_test_runs` and broadcast.

### A. Side-by-side KPI cards

| Metric | Engine A | Engine B | Delta |
|--------|----------|----------|-------|
| 95% VaR | historical 1-day | sim (label horizon) | B − A |
| 99% VaR | historical | sim | B − A |
| Expected Shortfall | historical | sim (or N/A) | if both exist |
| Compute time | `elapsed_ms` A | `elapsed_ms` B | show parallel wall clock if measured |

Use clear labels so 1-day historical VaR is not silently compared to 30-day simulated VaR
without a footnote.

### B. Charts (Plotly.js via importmap)

v1 dashboard prefers **Plotly in the browser** fed by JSON coordinate arrays from R
(stored on the stress-test record or as Active Storage JSON). ggplot2 SVG remains a fine
fallback for a single density plot in Phase 1.

```text
+---------------------------+----------------------------+
| CHART 1: Density / tails  | CHART 2: 30-day MC cone    |
| Empirical vs simulated    | Paths + quantile ribbon    |
+---------------------------+----------------------------+
| CHART 3: Rolling VaR + breaches (historical backtest)  |
+--------------------------------------------------------+
```

**Chart 1 — Distribution & tail risk**

- Trace A: empirical density from Container A  
- Trace B: terminal or 1-day projected density from Container B (label which)  
- Vertical lines: VaR 95/99 cutoffs from each model  

**Chart 2 — Monte Carlo fan**

- ~100 grey spaghetti paths (low opacity)  
- Ribbon: 5th–95th percentile  
- Solid median (50th)  
- Dashed baseline at initial portfolio value  

**Chart 3 — Rolling historical VaR & breaches**

- Bars/line: recent portfolio returns (e.g. last 1,000 bars)  
- Red line: rolling 95% VaR from A  
- Markers: breach points  

---

## Galaaz call style (honest)

### You do **not** need `R.eval(-> { ... })`

Galaaz already exposes many R functions as `R.<name>(...)`. Prefer direct calls:

```ruby
R.library("PerformanceAnalytics")
var_95 = R.VaR(returns_matrix, p: 0.95, method: "historical")
```

`R.eval_r("...")` remains useful for short R snippets or packages that are awkward to
express as method calls — it is optional, not required for “elegance.”

### What Gemini’s job snippet invents (do not copy blindly)

| Invented / misleading | Reality |
|----------------------|---------|
| `pluck_to_arrow` | Not in Rails/Galaaz; use `Risk::ReturnPanel.column_hash` + `Galaaz::ArrowIpc.write` |
| `R.assign_arrow` | Not a public Galaaz API today |
| `portfolio_data.daily_return` as a free Ruby local | Only works if you bind a Ruby handle to an R object (`R.portfolio_data` / assign patterns) |
| “0-copy” | See architecture — bulk handoff, analytics in R |
| Fake `R.eval(-> { })` block DSL | Not required; also not how Galaaz eval works |

### Phase 1 vs Phase 2 code shape

**Phase 1 (single engine):** one Solid Queue job, historical VaR + one chart (Plotly or SVG).  
**Phase 2:** fan-out to A and B (`RInstanceManager` / Docker), merge payloads, full dashboard.

Sketch (illustrative — real APIs in [galaaz_api_cheatsheet.md](galaaz_api_cheatsheet.md)):

```ruby
class StressTestJob < ApplicationJob
  def perform(stress_test_id)
    test = StressTest.find(stress_test_id)
    test.update!(status: "calculating")

    rows = Risk::ReturnPanel.from_portfolio(test.portfolio)
    # Arrow IPC / table_from happens inside HistoricalEngine → ArrowHandoff
    result = Risk::HistoricalEngine.call(rows)

    test.update!(status: "completed", **result.metrics)
    Turbo::StreamsChannel.broadcast_replace_to(
      "portfolio_#{test.portfolio_id}",
      target: "stress_test_results",
      partial: "stress_tests/results",
      locals: { test: test, charts: result.chart_payloads }
    )
  end
end
```

---

## Storage sketch

Prefer JSON columns (or associated `stress_test_runs`) for large coordinate arrays rather
than dozens of float columns:

- `stress_tests`: status, scalars, `elapsed` totals, optional error  
- `stress_test_runs`: `engine` (`historical` / `monte_carlo`), scalars, `payload` (JSON)  

Exact migration lands in Phase 1/2 implementation — not in this doc’s scope to create files.

## Implementation status

- [x] Engines + dashboard design captured here  
- [x] Phase 1 single-engine job + minimal UI  
- [x] Phase 2 dual engines + three Plotly charts + KPI table  
- [x] Docker multi-version R via `RInstanceManager` (3.6.3 + 4.3.3) with local fallback
