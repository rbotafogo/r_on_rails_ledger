# R-on-Rails Ledger

Standalone **Rails 8** demo of **R-on-Rails**: a family-office style portfolio stress tester.

- **App runtime:** CRuby (uses the host / mise Ruby — no pinned `.ruby-version`)
- **Data / jobs / cable:** SQLite + Solid Queue + Solid Cable + Hotwire
- **Statistics:** GNU R via the [Galaaz](https://github.com/rbotafogo/galaaz) bridge

This repository is **isolated** from the Galaaz gem source tree. Open **this** project in your
editor. Galaaz is a dependency (RubyGems by default; optional `GALAAZ_GEM_PATH` for a local checkout — see below).

## Documentation (start here)

→ **[docs/README.md](docs/README.md)** · in-app at `/docs` (including **Ruby DSL** with live code)

Especially:

- [Getting started](docs/getting_started.md)
- [Runbook / 2–3 min pitch](docs/runbook.md)
- [Implementation plan](docs/implementation_plan.md)
- [Architecture (honest claims)](docs/architecture.md)

## Quick boot

```bash
cd /home/rbotafogo/desenv_linux/r_on_rails_ledger
bundle install
make -C ../galaaz/ext/new_bridge all   # once / after bridge changes (path-gem setup)
bin/rails db:prepare
SEED_PROFILE=fast bin/rails db:seed    # or SEED_PROFILE=wow for ~1M rows
bin/dev
# open http://localhost:3000
```

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
