# Documentation index — R-on-Rails Ledger

This app is a **standalone Rails 8 demo** of **R-on-Rails**: keep statistical work in
**GNU R**, put the product shell on **Rails** (CRuby by default; JRuby also works with
the same Galaaz bridge).

You do **not** need to open the Galaaz repository as a Cursor/IDE project to work here.
This `docs/` tree is the source of truth for the demo. When you need deep Galaaz API
detail, use the published docs or the sibling checkout only as a library.

## OnRails family (pitch framing)

| Layer | Story |
|-------|--------|
| **Ruby on Rails** | Web apps for one person |
| **Omarchy / LinuxOnRails** | DHH’s Linux desktop philosophy |
| **R-on-Rails (Galaaz)** | R science + Rails product, no Python microservice fleet |

This demo (`r_on_rails_ledger`) is the concrete R-on-Rails showcase: a family-office style
portfolio stress tester on **SQLite + Solid Queue + Solid Cable + Hotwire**, with Galaaz
driving concurrent GNU R engines for VaR / Monte Carlo style risk.

## Read in this order

1. [Getting started](getting_started.md) — machine setup, boot the app
2. [Product scenario](product_scenario.md) — what we are building and why
3. [Architecture](architecture.md) — Rails, Solid*, Galaaz proxies, Arrow handoff (honest; no fake zero-copy)
4. [Implementation plan](implementation_plan.md) — phased build checklist
5. [Data and seeding](data_and_seeding.md) — 1M-row GBM / SQLite design
6. [Engines and dashboard](engines_and_dashboard.md) — dual R engines, KPIs, Plotly
7. [Runbook](runbook.md) — ops, demo checklist, **2–3 min pitch script**
8. [For R scientists](for_r_scientists.md) — minimal Rails you need
9. [For Ruby developers](for_ruby_developers.md) — how to call R safely
10. [API cheat sheet](galaaz_api_cheatsheet.md) — Galaaz calls used by this demo
11. [Ruby DSL & code](ruby_dsl.md) — call style + this app’s engine code (also `/docs/ruby-dsl`)
12. [External references](external_references.md) — Galaaz docs, Rails 8 Solid guides

In the running app, open **Docs** in the nav (or `/docs`) to browse these pages with formatting
and live code excerpts on the Ruby DSL guide.

## Project layout (high level)

```text
r_on_rails_ledger/          # this Rails 8 app (isolated)
  docs/                     # you are here
  app/                      # Rails MVC + jobs + Hotwire
  db/                       # SQLite schema + seeds (ledger + Solid* DBs)
../galaaz/                  # optional sibling path gem (development)
```

Galaaz is declared in the `Gemfile` as a **path gem** to `../galaaz` during development.
For a stranger install, switch to the published `galaaz` gem (see Getting started).
