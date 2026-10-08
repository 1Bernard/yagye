import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "title", "kind", "label_field"]

  open(event) {
    const btn = event.currentTarget
    const kind  = btn.dataset.docKind  || ""
    const label = btn.dataset.docLabel || "Upload document"

    if (this.hasKindTarget)       this.kindTarget.value       = kind
    if (this.hasLabel_fieldTarget) this.label_fieldTarget.value = label
    if (this.hasTitleTarget)      this.titleTarget.textContent = label

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
}
