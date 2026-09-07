# For Ruby / Rails developers

## Mental model

This is a normal Rails 8 app. Galaaz is a gem that talks to an **out-of-process** GNU R.
Treat R like an external analytics engine with a Ruby API — not like embedding NumPy.

## Rules of thumb

1. **Don’t block Puma** on long R calls — enqueue Solid Queue jobs.
2. **Don’t reimplement risk math in Ruby** — call R packages.
3. **Batch data into R** — prefer one handoff (`Galaaz::ArrowIpc.write` + `R::Arrow.open_ipc`,
   or Stage A `from_ruby_batches` / `table_from`) over thousands of tiny assign round-trips;
   then stay on **proxies** (`R.*`) and unbox only KPIs
   ([architecture.md](architecture.md) — Remote Control).
4. **Serialize shared Ruby structures** if multiple threads touch them; the bridge serializes
   calls into a given R session, but your Ruby arrays/hashes are your problem.
5. **Surface R failures** onto `stress_tests.status` / `error_message` for the UI.
6. **Do not pitch zero-copy shared RAM** for CRuby + NewBridge today — Stage B is an IPC file;
   Stage C shared-memory Arrow is future work.

## Where to put code

| Concern | Place |
|---------|--------|
| HTTP + Turbo | controllers / views |
| Job orchestration | `app/jobs/stress_test_job.rb` |
| R package workflow | job private methods or `app/services/risk/*` |
| Multi-R Docker | thin wrapper around `NewBridge::RInstanceManager` |
| Domain tables | Active Record models |

## CRuby vs JRuby

This app targets **CRuby**. Galaaz supports JRuby with the same bridge. Switching the app
runtime is a deployment choice, not a rewrite of the risk logic.

## Testing strategy (planned)

- Model tests for validations and status transitions
- Job test with a stubbed/short R call (or tagged integration test with real R)
- System test: click button → eventually see completed metrics (may be slow; mark as such)

## Galaaz call style

Prefer direct `R.*` method calls (no `R.eval(-> { })` wrapper). Short `R.eval_r("...")`
snippets are fine when clearer. Invented helpers (`pluck_to_arrow`, `R.assign_arrow`) are
**out** — see [engines_and_dashboard.md](engines_and_dashboard.md) and
[galaaz_api_cheatsheet.md](galaaz_api_cheatsheet.md).
