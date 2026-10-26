import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "panel"]
  static values = {
    reveal: String
  }

  connect() {
    this.toggle()
  }

  change() {
    this.toggle(true)
  }

  toggle(resetOnHide = false) {
    const checked = this.sourceTargets.find(el => el.checked)
    const shouldReveal = checked && checked.value === this.revealValue

    this.panelTargets.forEach(panel => {
      if (shouldReveal) {
        panel.classList.remove("hidden")
      } else {
        panel.classList.add("hidden")
        if (resetOnHide) {
          // Reset child radio/checkbox inputs to default (first "All" option or unchecked)
          const allOption = panel.querySelector("input[value='']")
          if (allOption) {
            allOption.checked = true
          } else {
            panel.querySelectorAll("input").forEach(i => i.checked = false)
          }
        }
      }
    })
  }
}
