# R-on-Rails Ledger

Standalone **Rails 8** demo of **R-on-Rails**: a family-office style portfolio stress tester.

- **App runtime:** **CRuby or JRuby** (Bundler picks SQLite via `sqlite3` on MRI, JDBC on JRuby)
- **Data / jobs / cable:** SQLite + Solid Queue + Solid Cable + Hotwire
- **Statistics:** GNU R via the [Galaaz](https://github.com/rbotafogo/galaaz) bridge

This repository is **isolated** from the Galaaz gem source tree. Open **this** project in your
editor. Galaaz is a dependency (RubyGems by default; optional `GALAAZ_GEM_PATH` for a local checkout — see below).

## Story / blog (Galaaz repo)

A narrative walkthrough of this demo—Rails models, R calculators, Arrow
handoff, and the Plotly results page—lives in the Galaaz blog:

- Source: [`blogs/r_on_rails_ledger/`](https://github.com/rbotafogo/galaaz/tree/master/blogs/r_on_rails_ledger) in [galaaz](https://github.com/rbotafogo/galaaz)
- Published renders: [rbotafogo.github.io/galaaz](https://rbotafogo.github.io/galaaz/)

## Documentation (start here)

→ **[docs/README.md](docs/README.md)** · in-app at `/docs` (including **Ruby DSL** with live code)

Especially:

- [Getting started](docs/getting_started.md)
- [Runbook / 2–3 min pitch](docs/runbook.md)
- [Implementation plan](docs/implementation_plan.md)
- [Architecture (honest claims)](docs/architecture.md)

## Quick boot

```bash
cd /path/to/r_on_rails_ledger
# Use either engine — Bundler installs the matching SQLite stack:
#   mise x ruby@3.3.12 -- bundle install    # CRuby
#   mise x ruby@jruby-10.0.3.0 -- bundle install   # JRuby
bundle install
bin/rails db:prepare
SEED_PROFILE=fast bin/rails db:seed    # or SEED_PROFILE=wow for ~1M rows
bin/dev
# open http://localhost:3000
# logs show: [r_on_rails_ledger] Ruby engine=ruby|jruby
```

On **JRuby**, set Galaaz JVM opens for Arrow (if you use Stage B Java):

```bash
export JAVA_OPTS="--add-opens=java.base/java.nio=ALL-UNNAMED ${JAVA_OPTS:-}"
```

`bin/dev` also installs a host Tailwind CLI under `tmp/tailwindcss-cli/` (JRuby has no gem platform binary) and sets `TAILWINDCSS_INSTALL_DIR`.

### Galaaz: path gem vs RubyGems

| Setup | Gemfile | When |
|-------|---------|------|
| **This monorepo** | `gem "galaaz", path: "../galaaz"` | Day-to-day development next to the gem checkout |
| **Standalone / pitch clone** | `gem "galaaz"` (no `path:`) | Published gem from RubyGems; no sibling tree required |

Either way you still need a working **GNU R** on `PATH`. With a path checkout, rebuild the
NewBridge gatekeeper after C++ changes (`make -C ../galaaz/ext/new_bridge all`). A RubyGems
install ships according to that gem’s packaging — follow Galaaz’s own install notes if the
bridge binary is missing.

Optional dual-version Docker demo (from **this** app root):

```bash
bin/setup_docker_r_engines
```

## OnRails family

Ruby on Rails → Omarchy (LinuxOnRails) → **R-on-Rails** (Galaaz). This app is the concrete
ledger demo for that pitch.
