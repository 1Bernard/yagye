import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form"]

  submit() {
    this.formTarget.requestSubmit()
  }

  clear() {
    this.formTarget.querySelectorAll("select").forEach(s => s.value = "")
    this.formTarget.querySelectorAll("input[type=date]").forEach(i => i.value = "")
    this.formTarget.querySelectorAll("input[type=search]").forEach(i => i.value = "")
    this.formTarget.requestSubmit()
  }
}
