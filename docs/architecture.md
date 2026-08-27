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

## Apache Arrow — what we say vs what we do

**Do say**

- We hand a tabular dataset to R in one (or few) bridge round-trips.
- Heavy dplyr / risk math runs **inside R**, often using R’s `arrow` package after conversion.
- We avoid JSON-per-row microservice tax and avoid reimplementing VaR in Ruby.

**Do not say**

- “Zero-copy memory pointer from CRuby into R bypasses the GVL.”
- “`pluck_to_arrow` / `R.assign_arrow`” unless we implement those helpers in this app.

**Current Galaaz pattern (real):** build column-oriented Ruby data →
`R::Arrow.from_ruby_batches` (or Feather file) → analytics in R.

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
