import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel"]

  open() {
    document.body.classList.add("overflow-hidden")
    this.element.classList.remove("opacity-0", "pointer-events-none")
    this.panelTarget.classList.remove("translate-y-3", "scale-[0.98]")
  }

  close() {
    document.body.classList.remove("overflow-hidden")
    this.element.classList.add("opacity-0", "pointer-events-none")
    this.panelTarget.classList.add("translate-y-3", "scale-[0.98]")
  }

  closeOnBackdrop(event) {
    if (event.target === this.element) this.close()
  }

  closeOnEscape(event) {
    if (event.key === "Escape") this.close()
  }
}
