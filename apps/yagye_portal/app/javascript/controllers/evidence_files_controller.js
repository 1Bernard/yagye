import { Controller } from "@hotwired/stimulus"

// Renders selected files as removable chips; tracks selection in a DataTransfer
// so individual files can be cancelled without clearing the whole input.
export default class extends Controller {
  static targets = ["input", "list", "empty"]

  connect() {
    this.dt = new DataTransfer()
  }

  pick(event) {
    event.preventDefault()
    this.inputTarget.click()
  }

  picked() {
    Array.from(this.inputTarget.files).forEach(file => {
      if (!this.#alreadyAdded(file)) {
        this.dt.items.add(file)
        this.#appendChip(file)
      }
    })
    this.inputTarget.files = this.dt.files
    this.#syncEmpty()
  }

  remove(event) {
    const chip = event.currentTarget.closest("[data-filename]")
    const name = chip?.dataset.filename
    if (!name) return

    const fresh = new DataTransfer()
    Array.from(this.dt.files)
      .filter(f => f.name !== name)
      .forEach(f => fresh.items.add(f))
    this.dt = fresh
    this.inputTarget.files = this.dt.files

    chip.remove()
    this.#syncEmpty()
  }

  // ── Private ───────────────────────────────────────────────────────────────

  #alreadyAdded(file) {
    return Array.from(this.dt.files).some(f => f.name === file.name && f.size === file.size)
  }

  #appendChip(file) {
    const chip = document.createElement("div")
    chip.dataset.filename = file.name
    chip.className = "flex items-center gap-2 px-3 py-2 bg-gray-50 rounded-xl border border-gray-100"
    chip.innerHTML = `
      <svg class="w-[13px] h-[13px] text-gray-400 flex-shrink-0" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
      </svg>
      <span class="text-[12.5px] text-gray-700 truncate flex-1 min-w-0">${this.#esc(file.name)}</span>
      <span class="text-[11px] text-gray-400 flex-shrink-0 tabular-nums">${this.#fmt(file.size)}</span>
      <button type="button" data-action="click->evidence-files#remove"
              class="flex-shrink-0 w-[18px] h-[18px] rounded-full bg-gray-200 hover:bg-red-100 hover:text-red-500 flex items-center justify-center transition-colors"
              aria-label="Remove file">
        <svg class="w-[9px] h-[9px]" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12"/>
        </svg>
      </button>
    `
    this.listTarget.appendChild(chip)
  }

  #syncEmpty() {
    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = this.dt.files.length > 0
    }
  }

  #fmt(bytes) {
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  }

  #esc(str) {
    return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }
}
