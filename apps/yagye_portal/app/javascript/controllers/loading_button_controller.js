import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["label", "spinner"]
  static values  = { loadingText: String }

  connect() {
    if (this.hasLabelTarget) this._original = this.labelTarget.textContent
  }

  start() {
    setTimeout(() => {
      this.element.disabled = true
      this.element.classList.add("opacity-80", "cursor-wait")
      if (this.hasSpinnerTarget) this.spinnerTarget.classList.remove("hidden")
      if (this.hasLabelTarget && this.loadingTextValue)
        this.labelTarget.textContent = this.loadingTextValue
    }, 0)
    this._timer = setTimeout(() => this.stop(), 15000)
  }

  stop() {
    clearTimeout(this._timer)
    this.element.disabled = false
    this.element.classList.remove("opacity-80", "cursor-wait")
    if (this.hasSpinnerTarget) this.spinnerTarget.classList.add("hidden")
    if (this.hasLabelTarget && this._original)
      this.labelTarget.textContent = this._original
  }
}
