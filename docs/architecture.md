# Architecture (honest)

This document is the contract between marketing language and what we implement.

## Stack

```text
Browser (Hotwire / Turbo / Stimulus / Tailwind)
        │
        ▼
Puma (CRuby) ── Active Record ── SQLite (primary ledger)
        │
        ├── Solid Cable ── live Turbo Streams
        │
        └── Solid Queue worker
                │
                ├── load returns from SQLite
                ├── build R-side table / Arrow via Galaaz
                └── GNU R process(es)  [NewBridge MsgPack bridge]
                        ├── Engine A (historical VaR)
                        └── Engine B (Monte Carlo)  [optional / phase 2]
```

Everything that Rails 8 can keep local stays local: **no Redis required** for jobs or
websockets when using Solid Queue + Solid Cable.

## Process boundaries

| Process | Owns |
|---------|------|
| Puma | HTTP, HTML, enqueuing jobs, Cable connections |
| Solid Queue worker | Long work; must not block request threads |
| GNU R (gatekeeper) | Statistics, ggplot2, PerformanceAnalytics, etc. |
| Docker R containers | Optional second/third R versions or isolated engines |

**R is single-threaded per process.** Scale R by **more R processes/containers**, not by
hoping one R uses all cores for every package.

## Galaaz’s role

Galaaz is the **bridge**: Ruby sends requests to a **separate GNU R process** and gets typed
results back (NewBridge protocol over Unix/TCP + MsgPack).

- Default public API: `R.*`, `R.eval_r`, `R.eval_r_async`, `R::Async.*`, `R::Arrow.*`
- Multi-instance helper: `NewBridge::RInstanceManager` (local or Docker) — used when we
  deliberately fan out Engine A / Engine B

Galaaz does **not** replace Solid Queue. Rails owns job lifecycle; Galaaz owns R I/O.

## Remote Control (proxy) pattern — what is real

Galaaz’s steady-state design is **orchestrate in Ruby, keep data resident in R**.

After a value exists in the GNU R process, Ruby holds an **`R::Object` proxy** (a bridge
handle such as `@r_interop`), not a copy of the full vector/table in the Ruby heap.

```text
Ruby (orchestrator)                    GNU R (separate process)
─────────────────                      ─────────────────────────
returns_vec = R.as__numeric(...) ──►   allocate / name vector
var = R.quantile(returns_vec, …) ──►   run quantile in R memory
  (still a proxy)                      result stays in R unless unboxed
kpi = (var >> 0)  ─────────────────►   explicit unbox → Ruby scalar for UI
```

**Do say (real today)**

- **Move the command, not the panel:** `R.quantile`, `R.density`, `R.mean`, dplyr helpers, etc.
  send compact instructions over NewBridge; vectorized work runs in R’s native memory.
- **Opt-in unboxing:** data stays in the R world until you explicitly pull it
  (`>>`, `to_ruby`, or small scalars for KPI cards / Plotly coordinates).
- **Debugging:** you can break between R calls and inspect live proxies without dumping the
  whole matrix into Ruby (same idea as `binding.pry` between `R.*` lines).
- **Heavy / nested R types** (including awkward-to-serialize S4): prefer manipulate **by
  reference** via proxies; query only the slots you need.

**Do not confuse with**

- Raw C pointers from CRuby into R’s heap. Proxies are **bridge handles** to a **separate**
  R process (NewBridge Unix/TCP + MsgPack), not same-address-space shared objects.
- “Never touch Ruby for ingest.” SQLite (or any Rails source) still needs **one handoff into R**;
  purity is *after* that: stay on proxies for analytics.

**This demo:** `Risk::ArrowHandoff` ingests once; `HistoricalEngine#historical_var` /
`#expected_shortfall` / `#return_density` call `R.*` on proxies and unbox only what the
dashboard needs. Pulling a tiny subset into Ruby for a chart is a **display-edge** compromise,
not the analytics steady state.

## Apache Arrow — what we say vs what we do

**Do say**

- We hand a tabular dataset to R in **one (or few) bridge round-trips**.
- **Stage A:** `R::Arrow.from_ruby_batches` / `table_from` **copy** columns into an Arrow `Table`
  **inside GNU R** (Ruby does not hold a shared Arrow C++ table).
- **Stage B (this demo’s local path when `Galaaz::ArrowIpc` loads):** Ruby writes an Arrow **IPC
  file** (`Galaaz::ArrowIpc.write`); `R::Arrow.open_ipc(path)` opens it in R; only the **path**
  crosses NewBridge. Export: `R::Arrow.write_ipc` then `Galaaz::ArrowIpc.read` / `read_batches`
  (density → Plotly). This is **mmap/IPC file handoff**, not a shared heap.
- Heavy dplyr / risk math then runs **in R** on that resident table / vectors.
- We avoid JSON-per-row microservice tax and avoid reimplementing VaR in Ruby.

**Do not say (not true on CRuby + NewBridge today)**

- “Zero-copy: Ruby and R map the same physical RAM; transfer is 0 ms.”
- “Zero-copy memory pointer from CRuby into R bypasses the GVL.”
- “`pluck_to_arrow` / `R.assign_arrow`” — use `Risk::ReturnPanel.column_hash` + `Galaaz::ArrowIpc.write`.

**Current pattern (real):** SQLite → Ruby columns → **`Galaaz::ArrowIpc.write` + `R::Arrow.open_ipc`**
when the Ruby Arrow backend is installed, else **`table_from`**. Docker: host **IPC file** plus
Feather/RDS fallback on the bind mount. Then analytics on **proxies** → unbox KPIs (or B2 for
coordinate tables).

### Future work — shared-memory / zero-copy Arrow

A true shared-memory Arrow bus (both sides attached to one columnar segment) is a
**possible future** escape hatch when ingest or export must move gigabytes often. It needs an
explicit design (process boundary, lifetime, IPC or in-process embed) — it is **not** what
Stage A or Stage B do today. Until then, pitch **ingest once + Remote Control proxies**,
not zero-copy shared RAM. See `../galaaz/Documentation/ROADMAP_ARROW_RUBY_R.md`.

## Concurrency model for this demo

1. **Request path:** create `StressTest`, enqueue job, return HTML immediately.
2. **Job path:** Solid Queue runs the stress test.
3. **Inside the job:** optionally start/use two R instances and run A ∥ B.
4. **Completion:** update SQLite; `broadcast_replace_to` the results partial.

CRuby’s GVL matters for CPU-heavy Ruby. We keep Ruby as **orchestrator**; R does the math.
Solid Queue concurrency is process/thread based at the Rails layer — that is the demo’s
parallelism story for “Puma stays free.”

## CRuby default, JRuby optional

| Runtime | Role in this demo |
|---------|-------------------|
| **CRuby** | Default app runtime (Rails 8 pitch) |
| **JRuby** | Same Galaaz bridge; useful if you later want true JVM threads in-process |

Do not require JRuby to run the ledger demo.

## Security / ops notes (later phases)

- Treat R `eval` of unsanitized user strings as dangerous (same as any eval).
- Bound job timeouts; surface errors on `stress_tests`.
- Docker engines need image pull + package install strategy documented in the runbook.
