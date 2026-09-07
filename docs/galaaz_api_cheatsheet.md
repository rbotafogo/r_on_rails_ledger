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

Phase 1 of this app uses **`Galaaz::ArrowIpc` + `R::Arrow.open_ipc`** for portfolio returns when
the Ruby Arrow backend is installed (CRuby **red-arrow**, JRuby Arrow Java), else
**`R::Arrow.table_from`**. Docker prefers **`returns.arrow`** (IPC), then Feather, then RDS.
See `Risk::ArrowHandoff` + `Risk::HistoricalEngine`. Local analytics prefer Ruby methods that
call `R.quantile`, `R.density`, etc.

## Tabular handoff (Arrow-oriented, not zero-copy shared RAM)

Ingest once into an R-side Arrow table / vectors; then use **proxy** `R.*` calls (Remote Control).
Do not claim Ruby and R share the same physical Arrow buffer today — see
[architecture.md](architecture.md).

```ruby
# Stage B1 — IPC file; only the path crosses NewBridge
path = Galaaz::ArrowIpc.write(Risk::ReturnPanel.column_hash(rows))
tbl  = R::Arrow.open_ipc(path)
Galaaz::ArrowIpc.release(path)

# Stage A fallback (copy into R)
# tbl = R::Arrow.from_ruby_batches(rows)

# Stage B2 — bulky result table back to Ruby
out = R::Arrow.write_ipc(summarised)
rows = Galaaz::ArrowIpc.read_batches(out)
Galaaz::ArrowIpc.release(out)
```

Runnable: `bin/rails runner script/arrow_ipc_panel_demo.rb`.

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
