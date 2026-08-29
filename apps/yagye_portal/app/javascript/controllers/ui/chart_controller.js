import { Controller } from "@hotwired/stimulus"
import * as echarts from "echarts"

// ui--chart — universal ECharts controller.
// Colors are read live from the portal design tokens (@theme in application.css)
// so one CSS variable change reflows all charts automatically.
export default class extends Controller {
  static targets = ["container"]
  static values  = {
    type:           String,
    labels:         Array,
    data:           Array,
    formattedData:  Array,
    series:         Array,
    datasetLabel:   String,
    currencyUnit:   String,
    stacked:        Boolean,
    area:           Boolean,
    centerLabel:    String,
    centerSublabel: String,
    colors:         Array,
    ring:           Boolean,
    selectedIndex:  Number
  }

  connect() {
    this.colors = this.readColors()
    this.chart  = echarts.init(this.containerTarget)
    this.chart.setOption(this.buildOption())
    this.resizeHandler = () => this.chart.resize()
    window.addEventListener("resize", this.resizeHandler)
  }

  disconnect() {
    window.removeEventListener("resize", this.resizeHandler)
    this.chart?.dispose()
  }

  downloadImage() {
    const link = document.createElement("a")
    link.href     = this.chart.getDataURL({ type: "png", backgroundColor: "#fff", pixelRatio: 2 })
    link.download = `${this.datasetLabelValue || this.typeValue}-chart.png`
    link.click()
  }

  readColors() {
    const token = (name, fallback) => {
      const value = getComputedStyle(document.documentElement).getPropertyValue(name).trim()
      return value || fallback
    }
    return {
      primary100:  token("--color-primary-100", "#dce1fd"),
      primary200:  token("--color-primary-200", "#bac2fb"),
      primary400:  token("--color-primary-400", "#6875f5"),
      primary600:  token("--color-primary-600", "#3D47F5"),
      chip:        token("--color-chip",         "#F3F4F6"),
      ink900:      token("--color-ink-900",      "#111827"),
      secondary:   token("--color-chart-secondary", "#818cf8"),
      neutral:     token("--color-chart-neutral",    "#d1d5db"),
      amber:       token("--color-chart-amber",      "#d97706"),
      okText:      token("--color-ok-text",          "#16a34a"),
      dangerText:  token("--color-danger-text",      "#dc2626")
    }
  }

  buildOption() {
    return this.isPie() ? this.pieOption() : this.axisOption()
  }

  tooltipStyle() {
    return {
      backgroundColor: this.colors.ink900,
      borderWidth:     0,
      textStyle:       { color: "#F9FAFB", fontFamily: "Inter", fontSize: 12 },
      extraCssText:    "border-radius:10px;padding:8px 12px"
    }
  }

  isPie() {
    return ["pie", "doughnut"].includes(this.typeValue)
  }

  hasSeries() {
    return this.seriesValue && this.seriesValue.length > 0
  }

  formattedValueAt(index) {
    return this.formattedDataValue[index] ?? this.dataValue[index]
  }

  abbreviate(value) {
    const abs = Math.abs(value)
    if (abs >= 1e9) return `${(value / 1e9).toFixed(1)}B`
    if (abs >= 1e6) return `${(value / 1e6).toFixed(1)}M`
    if (abs >= 1e3) return `${(value / 1e3).toFixed(1)}K`
    return `${value}`
  }

  pieOption() {
    const { primary600, primary200, chip, ink900 } = this.colors
    const isDoughnut   = this.typeValue === "doughnut"
    const hasCenter    = this.centerLabelValue.length > 0
    const palette      = this.colorsValue.length ? this.colorsValue : [primary600, primary200, chip]
    const hasSelection = this.selectedIndexValue >= 0

    const data = this.labelsValue.map((name, index) => ({
      name,
      value:      this.dataValue[index],
      itemStyle:  { color: palette[index % palette.length] },
      selected:   hasSelection && index === this.selectedIndexValue
    }))

    const centerLabel = {
      show:      true,
      position:  "center",
      formatter: () => `{a|${this.centerLabelValue}}\n{b|${this.centerSublabelValue}}`,
      rich: {
        a: { fontSize: 28, fontFamily: "Inter", fontWeight: 700, color: ink900, lineHeight: 34 },
        b: { fontSize: 11, color: "#9CA3AF", fontFamily: "Inter", padding: [4, 0, 0, 0] }
      }
    }

    const dataSeries = {
      type:           "pie",
      radius:         isDoughnut ? ["60%", "85%"] : "75%",
      padAngle:       isDoughnut ? 3 : 0,
      itemStyle:      { borderRadius: isDoughnut ? 6 : 0 },
      selectedMode:   hasSelection ? "single" : false,
      selectedOffset: 10,
      label:          hasCenter ? centerLabel : { show: false },
      data
    }

    const series = this.ringValue
      ? [{ type: "pie", radius: dataSeries.radius, silent: true, animation: false, z: 1,
           label: { show: false }, itemStyle: { color: chip }, data: [{ value: 1 }] },
         { ...dataSeries, z: 2 }]
      : [dataSeries]

    return {
      tooltip: {
        trigger:   "item",
        ...this.tooltipStyle(),
        formatter: (params) => `${params.name}: ${this.formattedValueAt(params.dataIndex)} (${params.percent}%)`
      },
      series
    }
  }

  axisOption() {
    const { primary400, primary600, primary200, chip } = this.colors
    const isSingle = !this.hasSeries()
    const tooltip = {
      trigger:     "axis",
      axisPointer: { type: this.typeValue === "bar" ? "shadow" : "line" },
      ...this.tooltipStyle(),
      formatter:   isSingle
        ? (params) => `${params[0].axisValueLabel}<br/>${this.formattedValueAt(params[0].dataIndex)}`
        : (params) => {
            const lines = params.map((p) => `${p.marker} ${p.seriesName}: ${this.seriesFormattedAt(p.seriesIndex, p.dataIndex)}`)
            return `${params[0].axisValueLabel}<br/>${lines.join("<br/>")}`
          }
    }

    return {
      color:   [primary600, primary400, primary200, chip],
      tooltip,
      grid:  { left: 8, right: 8, top: 8, bottom: 8, containLabel: true },
      xAxis: {
        type:      "category",
        data:      this.labelsValue,
        axisLine:  { lineStyle: { color: chip } },
        axisLabel: { interval: 0, color: "#9CA3AF", fontFamily: "Inter", fontSize: 11 }
      },
      yAxis: {
        type:      "value",
        splitLine: { lineStyle: { color: chip } },
        axisLabel: {
          color: "#9CA3AF", fontFamily: "Inter", fontSize: 11,
          formatter: (value) => `${this.currencyUnitValue}${this.abbreviate(value)}`
        }
      },
      series: isSingle ? this.singleSeries() : this.multiSeries()
    }
  }

  seriesFormattedAt(seriesIndex, dataIndex) {
    return this.seriesValue[seriesIndex]?.formatted?.[dataIndex] ?? this.seriesValue[seriesIndex]?.data?.[dataIndex]
  }

  singleSeries() {
    const { primary600 } = this.colors
    const isLine = this.typeValue === "line"
    return [{
      type:       this.typeValue,
      name:       this.datasetLabelValue,
      data:       this.dataValue,
      smooth:     isLine ? 0.4 : undefined,
      symbol:     isLine ? "circle" : undefined,
      symbolSize: isLine ? 5 : undefined,
      showSymbol: false,
      areaStyle:  this.areaValue ? this.gradientFill(primary600) : undefined,
      lineStyle:  isLine ? { color: primary600, width: 2 } : undefined,
      itemStyle:  isLine
        ? { color: primary600, borderColor: "#fff", borderWidth: 1.5 }
        : { color: primary600, borderRadius: 6 }
    }]
  }

  multiSeries() {
    const { primary600, secondary, neutral, amber, dangerText } = this.colors
    const fallback = [primary600, secondary, neutral, amber, dangerText]
    const palette  = this.colorsValue.length ? this.colorsValue : fallback
    const isLine   = this.typeValue === "line"
    const last     = this.seriesValue.length - 1
    return this.seriesValue.map((s, index) => {
      const color   = palette[index % palette.length]
      const hasArea = s.area ?? this.areaValue
      let borderRadius
      if (this.typeValue === "bar" && this.stackedValue) {
        if (index === 0) borderRadius = [0, 0, 4, 4]
        else if (index === last) borderRadius = [4, 4, 0, 0]
        else borderRadius = 0
      }
      return {
        type:      this.typeValue,
        name:      s.name,
        data:      s.data,
        stack:     this.stackedValue ? "total" : undefined,
        smooth:    isLine ? 0.4 : undefined,
        symbol:    isLine ? "none" : undefined,
        lineStyle: isLine ? { color, width: 2 } : undefined,
        areaStyle: hasArea ? this.gradientFill(color) : undefined,
        barWidth:  this.stackedValue ? 20 : undefined,
        itemStyle: { color, borderRadius }
      }
    })
  }

  gradientFill(color) {
    return {
      color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
        { offset: 0, color: `${color}26` },
        { offset: 1, color: `${color}00` }
      ])
    }
  }
}
