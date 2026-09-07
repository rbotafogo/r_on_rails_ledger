# For R scientists

You already know R. This app asks you to learn **just enough Rails** to ship a product.

## Mental model

| You keep in R | Rails owns |
|---------------|------------|
| VaR, ES, Monte Carlo, GARCH, ggplot2 | HTTP, pages, buttons, auth (later) |
| CRAN / Bioconductor packages | SQLite ledger (portfolios, prices, job status) |
| Statistical correctness | Background jobs (Solid Queue), live UI (Hotwire) |

Galaaz is the bridge: Ruby calls into **your** GNU R process. You are not translating models
into Ruby or Python.

## What you need to recognize in this repo

- **`app/models`** — tables (portfolio, prices, stress test results)
- **`app/jobs`** — where we will call Galaaz / R
- **`app/views`** — HTML the manager sees; Turbo Streams update a div when R finishes
- **`db/seeds.rb`** — how demo data is created

You do **not** need to master the whole Rails Guides to complete the demo.

## How R code shows up

Prefer small, reviewable R expressions or scripts invoked from the job, for example:

- `R.library("PerformanceAnalytics")`
- `Galaaz::ArrowIpc.write` + `R::Arrow.open_ipc` (Stage B IPC) or `R::Arrow.from_ruby_batches` (Stage A copy), then dplyr / PerformanceAnalytics in R
- `bin/rails runner script/arrow_ipc_panel_demo.rb` — ticker-level B1/B2 example
- `R.eval_r("...")` for short snippets
- Save plots as SVG from R and stream them into the page

Avoid pasting huge opaque R strings without comments — future you (and DHH) will read the job.

## Dual engines (phase 2)

Think of Engine A and Engine B as **two R sessions** (possibly two container images / R
versions), not two threads inside one R. Rails starts/waits on both; each runs its model.

## Learning path (short)

1. Click through the UI once it exists.
2. Read `StressTestJob` (when added) top to bottom.
3. Skim [galaaz_api_cheatsheet.md](galaaz_api_cheatsheet.md).
4. Only then open the full Galaaz manual if you need deeper DSL detail
   ([external_references.md](external_references.md)).
