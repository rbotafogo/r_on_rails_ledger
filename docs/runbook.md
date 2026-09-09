# Runbook

Operational commands for day-to-day work and live demos.

## Daily development

```bash
cd /home/rbotafogo/desenv_linux/r_on_rails_ledger
bundle install
bin/rails db:prepare
SEED_PROFILE=fast bin/rails db:seed   # laptop default; SEED_PROFILE=wow ≈ 1M rows
bin/dev                                 # or: bin/rails s -p 3001
```

Open http://localhost:3000 (or `:3001`) → portfolio → **Run stress test**.

Development uses Active Job **`:async`** so the stress-test job runs in the web process and
Turbo/Cable updates work without a separate worker. Solid Queue remains in the Gemfile for
production / later `SOLID_QUEUE_IN_PUMA=1` demos.

### Seed profiles

| Profile | Use |
|---------|-----|
| `SEED_PROFILE=fast` | ~20k bars — default for laptop pitches |
| `SEED_PROFILE=wow` | ~1M bars — “serious panel” line |
| `STRESS_LIMIT_PER_ASSET=N` | Cap load in the job without re-seeding |

### Rebuild Galaaz gatekeeper after gem updates

```bash
make -C ../galaaz/ext/new_bridge all
```

### Console with Galaaz

```bash
bin/rails console
# >> require "galaaz"
# >> R::Support.eval("1+1")
```

## Demo checklist (before you walk on stage)

1. [ ] App root is `r_on_rails_ledger` (not the Galaaz gem tree)
2. [ ] `SEED_PROFILE=fast bin/rails db:seed` (or `wow` if you will say “~1M rows”)
3. [ ] `bin/rails s` or `bin/dev` running; open the portfolio page
4. [ ] GNU R works (`R --version`); gatekeeper built (`make -C ../galaaz/ext/new_bridge all`)
5. [ ] Optional Docker dual-R: from **app root** run `bin/setup_docker_r_engines`
6. [ ] Tab ready: portfolio page + `/docs/ruby-dsl` (live code excerpts)
7. [ ] Know Local vs Docker radios; amber notice is OK if Docker images are missing

## Pitch script (2–3 minutes)

Timed for a live click-through. Keep the browser on the portfolio page unless noted.

| Time | Beat | What you say / do |
|------|------|-------------------|
| 0:00 | **Open** | “This is **R-on-Rails** — same one-person idea as Rails, for people whose science already lives in R. Rails → Omarchy → R-on-Rails.” |
| 0:20 | **Stack** | “Rails 8, **CRuby or JRuby**, SQLite (native or JDBC), Solid Queue / Cable, Hotwire. No Redis, no Python workers, no React SPA.” |
| 0:40 | **Data** | Point at price-bar count. “Synthetic GBM seed — `SEED_PROFILE=fast` on a laptop, `wow` for about a million bars.” |
| 1:00 | **Click Local** | Select **Local R** → **Run stress test**. “Job enqueues; Puma stays free. Returns go to R as an **Arrow IPC file** (path on the bridge); historical VaR is Ruby calling `R.quantile` / `R.density`.” |
| 1:30 | **Charts** | When Turbo replaces the panel: “KPI delta table — historical vs Monte Carlo — and three Plotly charts: density, paths, rolling VaR breaches.” |
| 1:50 | **Docker** (if ready) | Select **Docker dual-R** → run again. “Same job, two containers: Engine A on **R 3.6.3**, Engine B on **R 4.3.3**. Cold start is the slow part.” If amber notice: “Without Docker images we still run both engines on local R — honesty over theater.” |
| 2:15 | **Docs** | Open **Docs → Ruby DSL**. “Same guides as `docs/` on disk, plus live excerpts from this app’s engine code.” |
| 2:40 | **Close** | “One developer owns the ledger and the science. Keep CRAN where it is; ship the product on Rails.” |

Skip Docker if images are not built — Local alone still lands the Arrow + DSL story.

## Troubleshooting

| Symptom | Check |
|---------|--------|
| `cannot load such file -- galaaz` | `bundle install`; path `../galaaz` exists (or RubyGems `gem "galaaz"` — see README) |
| Bridge / gatekeeper errors | `make -C ../galaaz/ext/new_bridge all`; `R` on PATH |
| Job never runs | Active Job `:async` in development; restart server after Gemfile changes |
| Cable UI never updates | Solid Cable DB migrated; `turbo_stream_from` matches broadcast name |
| `bin/setup_docker_r_engines` not found | Run from **`r_on_rails_ledger`**, not the Galaaz checkout |
| Docker R “never finishes” | Restart server after handoff fixes; images need Docker daemon; Local always works |
| R package missing | Install in the R the gatekeeper uses (user library / Docker image) |

## Environment variables

| Variable | Purpose |
|----------|---------|
| `SEED_PROFILE` | `fast` or `wow` for `db:seed` |
| `STRESS_LIMIT_PER_ASSET` | Cap rows loaded per asset (debug) |
| `GALAAZ_BRIDGE_TIMEOUT_SEC` | Longer R jobs (Monte Carlo) |
| `SOLID_QUEUE_IN_PUMA` | Run Solid Queue inside Puma (simple demos) |
| `JOB_CONCURRENCY` | Solid Queue worker processes (see `config/queue.yml`) |
| `MC_PATHS` | Monte Carlo paths (default `5000`; try `50000` for pitch) |
| `MC_HORIZON_DAYS` | Forward horizon (default `30`) |
| `MC_SAMPLE_PATHS` | Spaghetti paths sent to Plotly (default `100`) |
| `LEDGER_R_HIST_IMAGE` | Default `galaaz/r-bridge:3.6.3` |
| `LEDGER_R_MC_IMAGE` | Default `galaaz/r-bridge:4.3.3` |

## Dual engines (Local vs Docker)

**Local R** — Arrow **IPC** handoff (`Galaaz::ArrowIpc` + `open_ipc`) on the default Galaaz bridge
when red-arrow is installed, else Stage A `table_from`. Historical engine uses Ruby DSL
(`R.quantile`, …); density coordinates use Stage B2 `write_ipc` when possible. Monte Carlo runs
GBM in R after the same ingest. Sequential on one R so DSL stays correct.

**Docker dual-R** — concurrent containers (3.6.3 historical + 4.3.3 Monte Carlo). Tabular handoff
via **IPC file** when Ruby can write one, else Feather, else `readRDS`. UI shows an amber notice
if Docker/images are missing and falls back to Local.

### One-time Docker image setup

```bash
cd /home/rbotafogo/desenv_linux/r_on_rails_ledger
bin/setup_docker_r_engines
```

Builds `galaaz/r-bridge:3.6.3` and `galaaz/r-bridge:4.3.3` (rocker + Rcpp; newer builds may also
install `arrow`). Re-run after deleting old tags if you need packages that were added later.
