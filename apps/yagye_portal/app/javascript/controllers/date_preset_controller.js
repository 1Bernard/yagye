import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["preset", "from", "to", "customPanel"]

  connect() {
    this.syncActivePreset()
  }

  select(event) {
    const preset = event.currentTarget.dataset.preset

    if (preset === "custom") {
      this.showCustomPanel()
      this.updateActiveStyles(event.currentTarget)
      if (this.hasFromTarget) this.fromTarget.focus()
      return
    }

    const { from, to } = this.calculateRange(preset)
    if (this.hasFromTarget) this.fromTarget.value = from
    if (this.hasToTarget) this.toTarget.value = to

    this.hideCustomPanel()
    this.updateActiveStyles(event.currentTarget)
  }

  dateChanged() {
    this.syncActivePreset()
  }

  showCustomPanel() {
    if (this.hasCustomPanelTarget) {
      this.customPanelTarget.classList.remove("hidden")
    }
  }

  hideCustomPanel() {
    if (this.hasCustomPanelTarget) {
      this.customPanelTarget.classList.add("hidden")
    }
  }

  calculateRange(preset) {
    const now = new Date()
    const formatDate = (d) => {
      const year = d.getFullYear()
      const month = String(d.getMonth() + 1).padStart(2, "0")
      const day = String(d.getDate()).padStart(2, "0")
      return `${year}-${month}-${day}`
    }

    const todayStr = formatDate(now)

    switch (preset) {
      case "all_time":
        return { from: "", to: "" }
      case "today":
        return { from: todayStr, to: todayStr }
      case "yesterday": {
        const yest = new Date(now)
        yest.setDate(yest.getDate() - 1)
        const yestStr = formatDate(yest)
        return { from: yestStr, to: yestStr }
      }
      case "7d": {
        const start = new Date(now)
        start.setDate(start.getDate() - 6)
        return { from: formatDate(start), to: todayStr }
      }
      case "30d": {
        const start = new Date(now)
        start.setDate(start.getDate() - 29)
        return { from: formatDate(start), to: todayStr }
      }
      case "this_month": {
        const start = new Date(now.getFullYear(), now.getMonth(), 1)
        return { from: formatDate(start), to: todayStr }
      }
      default:
        return { from: "", to: "" }
    }
  }

  syncActivePreset() {
    if (!this.hasFromTarget || !this.hasToTarget) return
    const fromVal = this.fromTarget.value
    const toVal = this.toTarget.value

    // If both dates are empty, match "all_time" or nothing
    if (!fromVal && !toVal) {
      const allTimeBtn = this.presetTargets.find(b => b.dataset.preset === "all_time")
      this.hideCustomPanel()
      this.updateActiveStyles(allTimeBtn || null)
      return
    }

    let matchedBtn = null
    this.presetTargets.forEach((btn) => {
      const preset = btn.dataset.preset
      if (preset === "custom") return
      const { from, to } = this.calculateRange(preset)
      if (from && to && from === fromVal && to === toVal) {
        matchedBtn = btn
      }
    })

    if (matchedBtn) {
      this.hideCustomPanel()
      this.updateActiveStyles(matchedBtn)
    } else {
      // Custom arbitrary date range entered or loaded from URL
      const customBtn = this.presetTargets.find(b => b.dataset.preset === "custom")
      this.showCustomPanel()
      this.updateActiveStyles(customBtn || null)
    }
  }

  updateActiveStyles(activeBtn) {
    this.presetTargets.forEach((btn) => {
      const isActive = btn === activeBtn
      btn.classList.toggle("bg-white", isActive)
      btn.classList.toggle("text-gray-900", isActive)
      btn.classList.toggle("shadow-sm", isActive)
      btn.classList.toggle("font-semibold", isActive)
      btn.classList.toggle("text-gray-500", !isActive)
      btn.classList.toggle("font-medium", !isActive)
    })
  }
}
