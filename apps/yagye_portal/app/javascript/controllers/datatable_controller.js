import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row", "selectAll", "selectedCount"]

  selectAll(event) {
    const checked = event.target.checked
    this.rowTargets.forEach(row => {
      const cb = row.querySelector("input[type=checkbox]")
      if (cb) cb.checked = checked
    })
    this._updateCount()
  }

  rowToggled() {
    this._updateCount()
    if (this.hasSelectAllTarget) {
      const allChecked = this.rowTargets.every(r => r.querySelector("input[type=checkbox]")?.checked)
      this.selectAllTarget.checked = allChecked
    }
  }

  sort(event) {
    const col = event.currentTarget.dataset.datatableColumn
    const url = new URL(window.location.href)
    const cur = url.searchParams.get("sort")
    url.searchParams.set("sort", cur === col ? `-${col}` : col)
    url.searchParams.delete("page")
    window.location.href = url.toString()
  }

  _updateCount() {
    if (!this.hasSelectedCountTarget) return
    const n = this.rowTargets.filter(r => r.querySelector("input[type=checkbox]")?.checked).length
    this.selectedCountTarget.textContent = n > 0 ? `${n} selected` : ""
  }
}
