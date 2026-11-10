import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display", "form", "trigger"]

  connect() {
    if (new URLSearchParams(window.location.search).get("edit") === "1") {
      this.edit()
    }
  }

  edit() {
    this.displayTarget.hidden = true
    this.formTarget.hidden = false
    if (this.hasTriggerTarget) this.triggerTarget.hidden = true
    this.formTarget.querySelector("textarea, input:not([type=hidden])")?.focus()
  }

  cancel() {
    this.formTarget.hidden = true
    this.displayTarget.hidden = false
    if (this.hasTriggerTarget) this.triggerTarget.hidden = false
  }
}
