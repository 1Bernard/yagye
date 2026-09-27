import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["track", "knob"]
  static values  = { on: String, off: String }

  connect() {
    this.checkbox = this.element.querySelector("input[type=checkbox]")
    this.checkbox.addEventListener("change", () => this.sync())
  }

  sync() {
    const active = this.checkbox.checked
    this.trackTarget.style.background = active ? this.onValue  : this.offValue
    this.knobTarget.style.left        = active ? "18px" : "2px"
  }
}
