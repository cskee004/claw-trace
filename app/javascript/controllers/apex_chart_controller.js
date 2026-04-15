import { Controller } from "@hotwired/stimulus"
import ApexCharts from "apexcharts"

export default class extends Controller {
  static values = { options: Object }

  connect() {
    this.chart = new ApexCharts(this.element, this.resolveColors(this.optionsValue))
    this.chart.render()
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  }

  resolveColors(opts) {
    if (!opts.colors || !opts.colors.length) return opts
    const style = getComputedStyle(document.documentElement)
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
