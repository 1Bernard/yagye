import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "overlay"]

  open() {
    document.body.classList.add("overflow-hidden")
    this.overlayTarget.classList.remove("opacity-0", "pointer-events-none")
    this.panelTarget.classList.remove("translate-x-full")
  }

  close() {
    document.body.classList.remove("overflow-hidden")
    this.overlayTarget.classList.add("opacity-0", "pointer-events-none")
    this.panelTarget.classList.add("translate-x-full")
  }

  closeOnEscape(event) {
    if (event.key === "Escape") this.close()
  }
}
