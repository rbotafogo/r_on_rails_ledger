# Getting started

## Prerequisites

| Dependency | Notes |
|------------|--------|
| **CRuby 3.3+** (host / mise latest) | No `.ruby-version` pin — on Omarchy this is whatever Install → Ruby on Rails installed. JRuby also works with Galaaz; this demo defaults to CRuby for the Rails 8 / DHH stack story. |
| **Bundler** | Comes with RubyGems / Rails. |
| **GNU R** | `R` and `Rscript` on `PATH`. Needed when jobs call Galaaz. |
| **C++ toolchain** | To build Galaaz’s NewBridge gatekeeper (`make` + a C++ compiler). |
| **Apache Arrow (optional, CRuby Stage B)** | System Arrow GLib (`libarrow-glib-dev`) and `gem install red-arrow` matching `pkg-config --modversion arrow-glib`. Without it, the demo uses Stage A `table_from`. |
| **Docker** (optional) | For concurrent R containers (Engine A / Engine B images). Local R alone is enough for phase 1. |

## Clone / open this project

```bash
cd /home/rbotafogo/desenv_linux/r_on_rails_ledger
# Open *this* folder in Cursor/VS Code — not the galaaz gem tree.
```

## Install Ruby gems

Development uses a **path gem** to the sibling Galaaz checkout:

```ruby
# Gemfile
gem "galaaz", path: "../galaaz"
```

```bash
bundle install
# This checkout may use `bundle config set --local path vendor/bundle`
# (ignored by git). Either that or your user gem home is fine.
```

**Without a local Galaaz clone** (stranger / pitch machine):

1. Change the Gemfile line to `gem "galaaz"` (RubyGems).
2. `bundle install`
3. Build the gatekeeper from the installed gem path:

```bash
gem_dir="$(bundle show galaaz)"
make -C "$gem_dir/ext/new_bridge" all
```

**With the path gem** (this machine):

```bash
make -C ../galaaz/ext/new_bridge all
```

## Database

Rails 8 uses SQLite for the primary app DB. Solid Queue / Cache / Cable use additional
SQLite databases in production configuration; see `config/database.yml`.

```bash
bin/rails db:prepare
```

## Boot the web app

```bash
bin/dev
# or: bin/rails server
```

Visit http://localhost:3000

## Solid Queue in development (for the stress-test demo)

By default, development may use the `:async` Active Job adapter. For the demo pitch we want
jobs to behave like production (SQLite-backed Solid Queue). When we enable that (see
implementation plan), start a worker:

```bash
SOLID_QUEUE_IN_PUMA=1 bin/dev
# or: bin/jobs
```

Exact commands will be finalized in [runbook.md](runbook.md) once the job is implemented.

## Sanity check: Galaaz loads

```bash
bin/rails runner "require 'galaaz'; puts RUBY_ENGINE; puts R::Support.eval('R.version.string')"
```

Expect CRuby (`ruby`) and a GNU R version string.

Arrow IPC smoke (needs seed data + `Galaaz::ArrowIpc`):

```bash
bin/rails runner script/arrow_ipc_panel_demo.rb
```

Note: prefer `R::Support.eval` / `R.bridge.eval_r` for string eval. Bare `R.eval_r(...)`
is not a Ruby method on `R` today (it would go through `method_missing` as an R function).

## What you do *not* need

- Redis, Postgres, Sidekiq, Node/React, or a Python microservice
- To keep the Galaaz repo open in the IDE (path gem is enough at bundle time)
- To memorize the Galaaz manual — use [galaaz_api_cheatsheet.md](galaaz_api_cheatsheet.md) first
