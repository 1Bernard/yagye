import { Controller } from "@hotwired/stimulus"

// Collapsible section with optional auto-open when inputs are prefilled.
//
// Targets:
//   panel   — the element to show/hide
//   chevron — optional icon that rotates 180° when open
//   trigger — optional button (gets aria-expanded)
//
// Values:
//   open (Boolean) — initial state; auto-promoted to true when panel has filled inputs
export default class extends Controller {
  static targets = ["panel", "chevron", "trigger"]
  static values  = { open: Boolean, rotation: { type: Number, default: 180 } }

  // Stimulus calls openValueChanged() automatically on connect (after targets are ready),
  // so we only need to handle the auto-open promotion here — no explicit update() needed.
  connect() {
    if (!this.openValue && this.hasPanelTarget) {
      const filled = Array.from(this.panelTarget.querySelectorAll("input, select, textarea"))
      if (filled.some(el => el.value && el.value.trim() !== "")) {
        this.openValue = true  // triggers openValueChanged → update()
        return
      }
    }
    this.update()  // handles the case where openValue was already set before connect
  }

  toggle() {
    this.openValue = !this.openValue
  }

  // For checkbox-driven panels: hides when the checkbox is checked.
  checkboxToggle(event) {
    this.openValue = !event.target.checked
  }

  openValueChanged() {
    this.update()
  }

  update() {
    if (!this.hasPanelTarget) return
    this.panelTarget.hidden = !this.openValue
    if (this.hasChevronTarget)
      this.chevronTarget.style.transform = this.openValue ? `rotate(${this.rotationValue}deg)` : ""`
    if (this.hasTriggerTarget)
      this.triggerTarget.setAttribute("aria-expanded", String(this.openValue))
  }
}
