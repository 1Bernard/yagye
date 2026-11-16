import { Controller } from "@hotwired/stimulus"

// Filters visible payment-method checkboxes based on the selected PSP.
// Used on the "new provider connection" form where the PSP selector changes
// which methods are supported.
//
// Usage:
//   data-controller="psp-methods" on the methods fieldset
//   data-action="change->psp-methods#filter" on the PSP <select>
//   data-psp-methods-target="row" data-method="card" on each checkbox label

export default class extends Controller {
  static targets = ["row"]

  filter(event) {
    const select = event.target
    const selected = select.options[select.selectedIndex]
    const supported = (selected.dataset.methods || "").split(",").filter(Boolean)

    // If the placeholder option is selected, nothing is known yet — show all.
    if (supported.length === 0) {
      this.rowTargets.forEach(row => row.classList.remove("hidden"))
      return
    }

    this.rowTargets.forEach(row => {
      const method = row.dataset.method
      const visible = supported.includes(method)
      row.classList.toggle("hidden", !visible)

      // Uncheck hidden methods so they are not submitted.
      if (!visible) {
        const checkbox = row.querySelector("input[type=checkbox]")
        if (checkbox) checkbox.checked = false
      }
    })
  }
}
