import { Controller } from "@hotwired/stimulus"

// Phase 2: three Plotly charts from dual-engine chart_payload.
export default class extends Controller {
  static targets = ["density", "cone", "rolling"]
  static values = { payload: Object }

  connect() {
    this.render()
  }

  payloadValueChanged() {
    this.render()
  }

  render() {
    if (typeof Plotly === "undefined") return
    const payload = this.payloadValue || {}
    const hist = payload.historical || {}
    const mc = payload.monte_carlo || {}

    this.renderDensity(hist, mc)
    this.renderCone(mc)
    this.renderRolling(hist)
  }

  renderDensity(hist, mc) {
    if (!this.hasDensityTarget) return
    const traces = []
    const shapes = []

    if (hist.density) {
      traces.push({
        x: hist.density.map((p) => p.x),
        y: hist.density.map((p) => p.y),
        type: "scatter",
        mode: "lines",
        fill: "tozeroy",
        name: "Historical density",
        line: { color: "#1d4ed8" }
      })
    }
    if (mc.terminal_density) {
      traces.push({
        x: mc.terminal_density.map((p) => p.x),
        y: mc.terminal_density.map((p) => p.y),
        type: "scatter",
        mode: "lines",
        name: "MC terminal return dens.",
        line: { color: "#ea580c", width: 2 }
      })
    }

    ;[
      [hist.var_95, "A 95%", "#1d4ed8"],
      [hist.var_99, "A 99%", "#1e3a8a"],
      [mc.sim_var_30d, "B 95% (30d)", "#ea580c"]
    ].forEach(([x, label, color]) => {
      if (typeof x !== "number") return
      shapes.push({
        type: "line",
        x0: x,
        x1: x,
        y0: 0,
        y1: 1,
        yref: "paper",
        line: { color, dash: "dash" }
      })
    })

    if (traces.length === 0) {
      this.densityTarget.innerHTML = "<p class='text-sm text-slate-500'>No density data</p>"
      return
    }

    Plotly.newPlot(
      this.densityTarget,
      traces,
      {
        margin: { t: 16, r: 12, b: 40, l: 48 },
        xaxis: { title: "Return" },
        yaxis: { title: "Density" },
        shapes,
        legend: { orientation: "h", y: 1.12 },
        showlegend: true
      },
      { responsive: true, displayModeBar: false }
    )
  }

  renderCone(mc) {
    if (!this.hasConeTarget) return
    const envelopes = mc.quantile_envelopes || []
    const paths = mc.sample_paths || []
    if (envelopes.length === 0) {
      this.coneTarget.innerHTML = "<p class='text-sm text-slate-500'>No Monte Carlo paths</p>"
      return
    }

    const traces = []
    paths.slice(0, 100).forEach((path) => {
      traces.push({
        x: path.map((p) => p.t),
        y: path.map((p) => p.value),
        type: "scatter",
        mode: "lines",
        line: { color: "rgba(100,116,139,0.15)", width: 1 },
        hoverinfo: "skip",
        showlegend: false
      })
    })

    const t = envelopes.map((e) => e.t)
    traces.push({
      x: t.concat([...t].reverse()),
      y: envelopes.map((e) => e.p95).concat(envelopes.map((e) => e.p05).reverse()),
      fill: "toself",
      fillcolor: "rgba(15,107,76,0.15)",
      line: { color: "transparent" },
      name: "5–95% band",
      type: "scatter",
      hoverinfo: "skip"
    })
    traces.push({
      x: t,
      y: envelopes.map((e) => e.p50),
      type: "scatter",
      mode: "lines",
      name: "Median",
      line: { color: "#0f6b4c", width: 2.5 }
    })

    const s0 = mc.s0
    if (typeof s0 === "number") {
      traces.push({
        x: [0, mc.horizon_days || 30],
        y: [s0, s0],
        type: "scatter",
        mode: "lines",
        name: "Baseline",
        line: { color: "#dc2626", dash: "dash", width: 1.5 }
      })
    }

    Plotly.newPlot(
      this.coneTarget,
      traces,
      {
        margin: { t: 16, r: 12, b: 40, l: 56 },
        xaxis: { title: "Day" },
        yaxis: { title: "Portfolio value" },
        legend: { orientation: "h", y: 1.12 },
        showlegend: true
      },
      { responsive: true, displayModeBar: false }
    )
  }

  renderRolling(hist) {
    if (!this.hasRollingTarget) return
    const series = hist.rolling_var_series || []
    const breaches = hist.breach_points || []
    if (series.length === 0) {
      this.rollingTarget.innerHTML =
        "<p class='text-sm text-slate-500'>Need ≥252 bars for rolling VaR (seed more history or use wow profile)</p>"
      return
    }

    // Use index for x if ISO timestamps are dense
    const xs = series.map((_, i) => i)
    const traces = [
      {
        x: xs,
        y: series.map((p) => p.return),
        type: "bar",
        name: "Portfolio return",
        marker: { color: "rgba(59,130,246,0.45)" }
      },
      {
        x: xs,
        y: series.map((p) => p.var_95),
        type: "scatter",
        mode: "lines",
        name: "Rolling 95% VaR",
        line: { color: "#dc2626", width: 2 }
      }
    ]

    if (breaches.length) {
      const bIndex = []
      const bY = []
      const tset = new Map(series.map((p, i) => [p.t, i]))
      breaches.forEach((b) => {
        const i = tset.get(b.t)
        if (i != null) {
          bIndex.push(i)
          bY.push(b.return)
        }
      })
      traces.push({
        x: bIndex,
        y: bY,
        type: "scatter",
        mode: "markers",
        name: "Breach",
        marker: { color: "#b91c1c", size: 7, symbol: "x" }
      })
    }

    Plotly.newPlot(
      this.rollingTarget,
      traces,
      {
        margin: { t: 16, r: 12, b: 40, l: 56 },
        xaxis: { title: "Trailing window index" },
        yaxis: { title: "Return" },
        legend: { orientation: "h", y: 1.12 },
        barmode: "overlay",
        showlegend: true
      },
      { responsive: true, displayModeBar: false }
    )
  }
}
