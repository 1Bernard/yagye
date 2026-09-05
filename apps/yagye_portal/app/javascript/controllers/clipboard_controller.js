import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { text: String }
  static targets = ["label"]

  copy() {
    navigator.clipboard.writeText(this.textValue).then(() => {
      if (this.hasLabelTarget) {
        const original = this.labelTarget.textContent
        this.labelTarget.textContent = "Copied!"
        setTimeout(() => { this.labelTarget.textContent = original }, 1500)
      }
    })
  }
}
