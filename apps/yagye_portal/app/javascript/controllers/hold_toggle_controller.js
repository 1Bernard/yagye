import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "reason", "container"]

  connect() {
    this.sync()
  }

  toggle() {
    this.sync()
  }

  sync() {
    const isHold = this.checkboxTarget.checked
    if (this.hasReasonTarget) {
      if (isHold) {
        this.reasonTarget.style.display = "block"
        this.reasonTarget.style.opacity = "1"
      } else {
        this.reasonTarget.style.display = "none"
        this.reasonTarget.style.opacity = "0"
      }
    }

    if (this.hasContainerTarget) {
      if (isHold) {
        this.containerTarget.classList.add("border-amber-300", "bg-amber-50/50")
        this.containerTarget.classList.remove("border-gray-100", "bg-white")
      } else {
        this.containerTarget.classList.remove("border-amber-300", "bg-amber-50/50")
        this.containerTarget.classList.add("border-gray-100", "bg-white")
      }
    }
  }
}
