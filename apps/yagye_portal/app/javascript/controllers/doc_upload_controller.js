import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "input", "previewSlide", "replaceSlide", "deleteSlide",
    "filename", "filesize", "submitBtn", "btnLabel", "pickRow"
  ]

  pick() {
    this.inputTarget.click()
  }

  picked() {
    const file = this.inputTarget.files[0]
    if (file) this.#showPreview(file)
  }

  clear(event) {
    event.stopPropagation()
    this.inputTarget.value = ""
    delete this.previewSlideTarget.dataset.open
    if (this.hasPickRowTarget) this.pickRowTarget.hidden = false
  }

  // ── Uploaded card ─────────────────────────────────────────────────────────

  replace() {
    if (this.hasDeleteSlideTarget) delete this.deleteSlideTarget.dataset.open
    if (this.hasReplaceSlideTarget) this.replaceSlideTarget.dataset.open = ""
  }

  cancelReplace() {
    this.inputTarget.value = ""
    delete this.previewSlideTarget.dataset.open
    if (this.hasPickRowTarget) this.pickRowTarget.hidden = false
    if (this.hasReplaceSlideTarget) delete this.replaceSlideTarget.dataset.open
  }

  showDelete() {
    if (this.hasReplaceSlideTarget) delete this.replaceSlideTarget.dataset.open
    if (this.hasDeleteSlideTarget) this.deleteSlideTarget.dataset.open = ""
  }

  cancelDelete() {
    if (this.hasDeleteSlideTarget) delete this.deleteSlideTarget.dataset.open
  }

  // ── Drag & drop ───────────────────────────────────────────────────────────

  dragover(event) {
    event.preventDefault()
    event.stopPropagation()
    this.element.dataset.dragging = "true"
  }

  dragleave(event) {
    event.stopPropagation()
    if (!this.element.contains(event.relatedTarget)) {
      delete this.element.dataset.dragging
    }
  }

  drop(event) {
    event.preventDefault()
    event.stopPropagation()
    delete this.element.dataset.dragging

    const file = event.dataTransfer?.files[0]
    if (!file) return

    // Uploaded card: auto-enter replace mode
    if (this.hasReplaceSlideTarget && !this.replaceSlideTarget.dataset.open) {
      this.replace()
    }

    const dt = new DataTransfer()
    dt.items.add(file)
    this.inputTarget.files = dt.files
    this.#showPreview(file)
  }

  submitting() {
    if (this.hasSubmitBtnTarget) this.submitBtnTarget.disabled = true
    if (this.hasBtnLabelTarget) this.btnLabelTarget.textContent = "Uploading…"
  }

  // ── Private ───────────────────────────────────────────────────────────────

  #showPreview(file) {
    if (this.hasFilenameTarget) this.filenameTarget.textContent = file.name
    if (this.hasFilesizeTarget) this.filesizeTarget.textContent = this.#formatSize(file.size)
    if (this.hasPickRowTarget) this.pickRowTarget.hidden = true
    this.previewSlideTarget.dataset.open = ""
  }

  #formatSize(bytes) {
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  }
}
