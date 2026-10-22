import { Controller } from "@hotwired/stimulus"

// Captures the current live state of the payments filter form and injects
// it as saved_filter[filters][*] hidden inputs before the save form submits.
// Needed because the save form lives outside the filter form (to avoid nested
// form HTML), so we can't rely on the browser to include those values.
export default class extends Controller {
  static targets = ["inputs"]

  beforeSubmit() {
    const filterForm = document.getElementById("payments-filter-form")
    if (!filterForm || !this.hasInputsTarget) return

    // Clear any previously captured inputs
    this.inputsTarget.innerHTML = ""

    const skip = new Set(["authenticity_token"])
    for (const el of filterForm.elements) {
      if (!el.name || skip.has(el.name) || !el.value) continue
      if ((el.type === "radio" || el.type === "checkbox") && !el.checked) continue
      // Skip the "All" (empty value) radio options
      if (el.type === "radio" && el.value === "") continue

      const input = document.createElement("input")
      input.type = "hidden"
      input.name = `saved_filter[filters][${el.name}]`
      input.value = el.value
      this.inputsTarget.appendChild(input)
    }
  }
}
