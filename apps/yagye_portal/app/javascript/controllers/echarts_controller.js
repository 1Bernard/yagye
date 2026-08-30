import { Controller } from "@hotwired/stimulus"
import * as echarts from "echarts"

export default class extends Controller {
  static values = { option: Object }

  connect() {
    this._chart = echarts.init(this.element, null, { renderer: "svg" })
    this._chart.setOption(this.optionValue)
    // Apply theme-aware overrides on top so charts respond to light/dark mode.
    this._chart.setOption(this._themeDefaults())
    this._ro = new ResizeObserver(() => this._chart.resize())
    this._ro.observe(this.element)
  }

  disconnect() {
    this._ro?.disconnect()
    this._chart?.dispose()
  }

  _themeDefaults() {
    const cs       = getComputedStyle(document.body)
    const get      = v  => cs.getPropertyValue(v).trim()
    const muted    = get("--muted-text")
    const border   = get("--border-med")
    const surface  = get("--surface")
    const bodyText = get("--body-text")
    const cardBg   = get("--card-bg")

    return {
      backgroundColor: "transparent",
      textStyle: { color: muted },
      xAxis: {
        axisLabel:  { color: muted },
        axisLine:   { lineStyle: { color: border } },
        splitLine:  { lineStyle: { color: surface } },
      },
      yAxis: {
        axisLabel:  { color: muted },
        axisLine:   { lineStyle: { color: border } },
        splitLine:  { lineStyle: { color: surface } },
      },
      tooltip: {
        backgroundColor: cardBg,
        borderColor:     border,
        textStyle:       { color: bodyText },
      },
    }
  }
}
