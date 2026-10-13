import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["label"]

  connect() {
    this.update()
    this.element.addEventListener("change", () => this.update())
  }

  update() {
    const checked = this.element.querySelectorAll("input[type=checkbox]:checked").length
    if (!this.hasLabelTarget) return
    this.labelTarget.textContent =
      checked === 0 ? "No approvers selected"
                    : `${checked} ${checked === 1 ? "approver" : "approvers"} selected`
  }
}
