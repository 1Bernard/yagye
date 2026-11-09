import { Controller } from "@hotwired/stimulus"

// Manages the visual "Where / And" condition builder.
// Handles adding/removing rows and re-indexing params on change.
export default class extends Controller {
  static targets = ["rows", "row"]

  addRow() {
    const index = this.rowTargets.length
    const firstRow = this.rowTargets[0]
    if (!firstRow) return

    // Clone the first row and clear its values
    const newRow = firstRow.cloneNode(true)
    newRow.querySelectorAll("select, input").forEach(el => {
      el.value = el.tagName === "SELECT" ? el.options[0]?.value || "" : ""
    })

    this.rowsTarget.appendChild(newRow)
    this.reindex()
  }

  removeRow(event) {
    const row = event.target.closest("[data-query-builder-target='row']")
    if (!row) return

    // Keep at least one row
    if (this.rowTargets.length <= 1) {
      row.querySelectorAll("select, input").forEach(el => { el.value = "" })
      return
    }

    row.remove()
    this.reindex()
  }

  reindex() {
    this.rowTargets.forEach((row, index) => {
      row.querySelectorAll("[name]").forEach(el => {
        // Replace filters[N][...] with the new index
        el.name = el.name.replace(/filters\[\d+\]/, `filters[${index}]`)
      })
    })
  }
}
