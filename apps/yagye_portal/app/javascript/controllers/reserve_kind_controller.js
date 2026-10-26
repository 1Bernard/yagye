import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["rateWrap", "fixedWrap"]

  connect() { this.sync() }

  sync() {
    const kind = this.element.querySelector("[data-action*='reserve-kind#sync']").value
    const isFixed = kind === "fixed"
    this.rateWrapTarget.hidden  = kind !== "rolling"
    this.fixedWrapTarget.hidden = !isFixed
    this.fixedWrapTarget.querySelector("input").disabled = !isFixed
  }
}
