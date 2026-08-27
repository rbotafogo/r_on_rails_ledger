# Galaaz API cheat sheet (for this demo)

Self-contained reminders. Full semantics live in the Galaaz manual; this page lists what
**this app** expects to use.

## Boot

```ruby
require "galaaz"
# optional refinement for ~:symbol style in some scripts:
# using Galaaz::SymbolDSL
```

## Eval and calls

```ruby
R::Support.eval("1 + 1")          # string eval (preferred)
# R.bridge.eval_r("1 + 1")        # same bridge path
R.library("ggplot2")
# R.install_and_loads("PerformanceAnalytics") # use sparingly; prefer images with pkgs preinstalled

# Async (completion in a block) — useful inside jobs / orchestration
R.eval_r_async("Sys.sleep(1); 42", timeout: nil) do |result|
  if result.ok?
    result.value
  else
    result.error
  end
end
```

Phase 1 of this app uses **`R::Arrow.table_from` / Feather** for portfolio returns (see
`Risk::ArrowHandoff` + `Risk::HistoricalEngine`) so large vectors stay out of Ruby splat/`R.c`
limits. Local analytics prefer Ruby methods that call `R.quantile`, `R.density`, etc.

## Tabular handoff (Arrow-oriented, not zero-copy)

```ruby
# Conceptual shape — exact column builder follows Galaaz examples:
table = R::Arrow.from_ruby_batches([
  { "trade_date" => dates, "ticker" => tickers, "daily_return" => returns }
])
# Then dplyr / PerformanceAnalytics in R on that table
```

Prefer one bulk handoff per stress test over per-row assigns.

## Multi-R (phase 2)

```ruby
# Conceptual — see Galaaz NewBridge RInstanceManager docs/specs:
# manager = NewBridge::RInstanceManager.new(...)
# manager.eval_with_version(...) / Docker rocker images
```

Document the exact wrapper we adopt in `app/services` when Phase 2 lands; keep call sites
out of controllers.

## Plots

**Phase 1:** ggplot2 SVG **or** a single Plotly figure from JSON coordinates.  
**Phase 2 dashboard:** prefer **Plotly.js** (importmap) fed by engine JSON payloads —
densities, MC fan, rolling VaR breaches (see [engines_and_dashboard.md](engines_and_dashboard.md)).

Generate coordinate arrays in R; let the browser draw. Avoid a Node/React build for v1.

## Timeouts

Long Monte Carlo: set `ENV["GALAAZ_BRIDGE_TIMEOUT_SEC"]` (or per-call timeout args where
supported) so the bridge does not kill legitimate long jobs.
