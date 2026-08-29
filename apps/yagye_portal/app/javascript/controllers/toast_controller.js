import { Controller } from "@hotwired/stimulus"

// Premium toast — entry slides down from top, exit fades + slides up.
// Progress bar drains via scaleX CSS transition over the delay window.
export default class extends Controller {
  static targets = ["progress"]
  static values  = { delay: { type: Number, default: 4500 } }

  connect() {
    // Entry: two rAF ticks so the browser registers the start state
    // (-translate-y-2 opacity-0) before the transition fires.
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        this.element.classList.remove("-translate-y-2", "opacity-0")
      })
    })

    this._drainProgress()
    this._timeout = setTimeout(() => this.dismiss(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this._timeout)
  }

  dismiss() {
    clearTimeout(this._timeout)
    this.element.classList.add("opacity-0", "-translate-y-1")
    setTimeout(() => this.element.remove(), 320)
  }

  _drainProgress() {
    if (!this.hasProgressTarget) return
    const bar = this.progressTarget
    // One rAF to let the DOM paint scaleX(1) before we start the transition.
    requestAnimationFrame(() => {
      bar.style.transition = `transform ${this.delayValue}ms linear`
      bar.style.transform = "scaleX(0)"
    })
  }
}
