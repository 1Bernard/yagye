import { Controller } from "@hotwired/stimulus"

// Toggles which chart period is visible and highlights the active button.
// Expects:
//   data-controller="period-toggle" on the button group wrapper
//   data-period-btn="7d|30d|90d"   on each button
//   data-period-chart="7d|30d|90d" on each chart wrapper (sibling/ancestor of this element)
export default class extends Controller {
  connect() {
    this._active = this._initialPeriod()
    this._render()
  }

  switch(event) {
    const period = event.currentTarget.dataset.periodBtn
    if (!period || period === this._active) return
    this._active = period
    this._render()
    this._resizeActive()
  }

  _render() {
    const card = this._card()

    // Show/hide chart wrappers
    card.querySelectorAll("[data-period-chart]").forEach(el => {
      el.style.display = el.dataset.periodChart === this._active ? "" : "none"
    })

    // Update button styles
    this.element.querySelectorAll("[data-period-btn]").forEach(btn => {
      const on = btn.dataset.periodBtn === this._active
      btn.className = btn.className
        .replace(/\bbg-\[#3D47F5\]\b|\btext-white\b|\bbg-transparent\b|\btext-gray-500\b|\bhover:text-gray-700\b/g, "")
        .trim()
      if (on) {
        btn.classList.add("bg-[#3D47F5]", "text-white")
      } else {
        btn.classList.add("bg-transparent", "text-gray-500", "hover:text-gray-700")
      }
    })
  }

  // ECharts initialises with 0×0 when its container is display:none.
  // After revealing it, call chart.resize() once the browser has laid out the element.
  _resizeActive() {
    const wrapper = this._card().querySelector(`[data-period-chart="${this._active}"]`)
    if (!wrapper) return

    const chartEl = wrapper.querySelector("[data-controller~='ui--chart']")
    if (!chartEl) return

    // Wait one animation frame so the browser paints the now-visible wrapper
    // before we ask ECharts to measure its container.
    requestAnimationFrame(() => {
      const ctrl = this.application.getControllerForElementAndIdentifier(chartEl, "ui--chart")
      if (ctrl?.chart) {
        ctrl.chart.resize()
      } else {
        // Fallback: the controller listens to window resize events directly.
        window.dispatchEvent(new Event("resize"))
      }
    })
  }

  _card() {
    return this.element.closest(".bg-white") || document.body
  }

  _initialPeriod() {
    const active = this.element.querySelector("[data-period-btn].text-white")
    return active ? active.dataset.periodBtn : "30d"
  }
}
