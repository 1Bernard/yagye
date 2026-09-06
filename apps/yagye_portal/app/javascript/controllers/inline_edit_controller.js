import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display", "form", "trigger"]

  edit() {
    this.displayTarget.hidden = true
    this.formTarget.hidden = false
    this.triggerTarget.hidden = true
    this.formTarget.querySelector("input:not([type=hidden])")?.focus()
  }

  cancel() {
    this.formTarget.hidden = true
    this.displayTarget.hidden = false
    this.triggerTarget.hidden = false
  }
}
