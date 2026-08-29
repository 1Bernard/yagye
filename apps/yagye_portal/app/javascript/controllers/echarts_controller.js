import { Controller } from "@hotwired/stimulus"
import * as echarts from "echarts"

export default class extends Controller {
  static values = { option: Object }

  connect() {
    this._chart = echarts.init(this.element, null, { renderer: "svg" })
    this._chart.setOption(this.optionValue)
    this._ro = new ResizeObserver(() => this._chart.resize())
    this._ro.observe(this.element)
  }

  disconnect() {
    this._ro?.disconnect()
    this._chart?.dispose()
  }
}
