# Ruby DSL & application code

This page is also rendered **in-app** at `/docs/ruby-dsl`, with live excerpts from the repo.

## Mental model

Galaaz exposes GNU R to Ruby. Prefer **Ruby methods that call `R.*`** (the DSL) for analytics
you want to read in a code review. Hand tabular data through **Apache Arrow** (R-side Table),
not CSV.

```ruby
require "galaaz"

# One bulk handoff → Arrow Table inside GNU R
df  = R::Support.exec_function("data.frame", { daily_return: returns })
tbl = R::Arrow.table_from(df)
x   = R.as__numeric(R.dplyr___collect(tbl)[["daily_return"]])

# Ruby method → R.quantile (DSL)
var_95 = R.as__numeric(R.quantile(x, probs: 0.05, names: false, type: 7))
```

String eval (`R::Support.eval`) is fine for long R algorithms (e.g. GBM loops). Docker dual-R
uses **Feather** on the shared mount (`arrow::read_feather`) because the container is a
separate process.

## What this app runs on each stress test

1. `StressTestsController` enqueues `StressTestJob` with `runtime: "local"` or `"docker"`.
2. **Local:** `Risk::DualOrchestrator` runs engines on the default Galaaz bridge —
   `Risk::ArrowHandoff` + Ruby DSL methods on `HistoricalEngine` (`historical_var`,
   `expected_shortfall`, `return_density`).
3. **Docker:** Feather handoff + concurrent R 3.6.3 / 4.3.3 containers.
4. Results land in `stress_test_runs` + Turbo Stream dashboard (Plotly).

## Showcase: historical VaR as Ruby → `R.*`

```ruby
def historical_var(returns_vec, probs:)
  RValues.scalar_f(
    R.as__numeric(R.quantile(returns_vec, probs: probs, names: false, type: 7))
  )
end

def expected_shortfall(returns_vec, var_level)
  RValues.scalar_f(R.as__numeric(R.mean(returns_vec[returns_vec <= var_level])))
end

def return_density(returns_vec, n: 128)
  dens = R.density(returns_vec, n: n)
  # dens.x / dens.y → Ruby arrays for Plotly
end
```

Monte Carlo still runs the path simulation in R (clearer as a script) after the same Arrow
handoff; μ/σ are taken with `R.mean` / `R.sd`.

## Key files

| File | Role |
|------|------|
| `app/services/risk/arrow_handoff.rb` | Arrow table + Feather IO |
| `app/services/risk/historical_engine.rb` | DSL VaR / ES / density |
| `app/services/risk/monte_carlo_engine.rb` | Arrow + GBM in R |
| `app/services/risk/dual_orchestrator.rb` | Local DSL vs Docker Feather |
| `app/jobs/stress_test_job.rb` | Job + persistence + broadcast |

See also [galaaz_api_cheatsheet.md](galaaz_api_cheatsheet.md) and
[for_ruby_developers.md](for_ruby_developers.md).
