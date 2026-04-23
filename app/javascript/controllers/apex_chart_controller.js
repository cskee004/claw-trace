import { Controller } from "@hotwired/stimulus"
import ApexCharts from "apexcharts"

export default class extends Controller {
  static values = { options: Object }

  connect() {
    const style = getComputedStyle(document.documentElement)
    const opts  = this.withTheme(this.resolveColors(this.optionsValue, style), style)
    this.chart  = new ApexCharts(this.element, opts)
    this.chart.render()
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  }

  // Merges dark-theme defaults so all charts are readable against the dark background.
  // Defaults come first — explicit keys in opts take precedence via spread.
  withTheme(opts, style) {
    const yaxis = Array.isArray(opts.yaxis) ? opts.yaxis : (opts.yaxis ? [opts.yaxis] : [])
    const themedYaxis = yaxis.map(y => ({
      labels: { formatter: v => Math.round(v).toLocaleString() },
      ...y
    }))
    return {
      ...opts,
      chart:   { foreColor: this.resolveVar("var(--color-fg-muted)", style),   ...opts.chart },
      grid:    { borderColor: this.resolveVar("var(--color-surface-2)", style), ...opts.grid },
      tooltip: { theme: "dark", ...opts.tooltip },
      ...(themedYaxis.length ? { yaxis: themedYaxis.length === 1 ? themedYaxis[0] : themedYaxis } : {})
    }
  }

  resolveColors(opts, style) {
    if (!opts.colors || !opts.colors.length) return opts
    return {
      ...opts,
      // Only processes top-level colors array; nested ApexCharts color keys (fill, markers, etc.)
      // are not used by MetricChartBuilder and are intentionally out of scope.
      colors: opts.colors.map(c => c.startsWith("var(") ? this.resolveVar(c, style) : c)
    }
  }

  // Follows CSS variable alias chains until a non-var() value is reached.
  // Falls back to the original string if resolution fails (variable not defined).
  resolveVar(varExpr, style) {
    let value = varExpr
    while (value.startsWith("var(")) {
      const name = value.slice(4, -1).trim()
      const resolved = style.getPropertyValue(name).trim()
      if (!resolved) return varExpr  // variable not found — return original for debuggability
      value = resolved
    }
    return value
  }
}
