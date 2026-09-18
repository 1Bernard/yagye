import { Controller } from "@hotwired/stimulus"

const INPUT_CLS =
  "w-full h-8 border border-gray-200 rounded-[9px] px-3 text-[12.5px] " +
  "text-gray-700 bg-white outline-none focus:border-[#3D47F5]"

const NUM_CLS = INPUT_CLS + " tabular-nums text-right"

// Build the inner grid HTML for a single line-item row.
function rowHTML(index) {
  return `
    <div class="grid grid-cols-[1fr_80px_120px_80px_24px] gap-3 items-start">
      <input type="text"   name="line_items[${index}][description]"  placeholder="Description" class="${INPUT_CLS}">
      <input type="number" name="line_items[${index}][quantity]"      value="1"   min="0.01" step="0.01" placeholder="1"    class="${NUM_CLS}">
      <input type="number" name="line_items[${index}][unit_amount]"               min="0"    step="0.01" placeholder="0.00" class="${NUM_CLS}">
      <input type="number" name="line_items[${index}][tax_rate_bps]"  value="0"   min="0" max="10000" step="0.01" placeholder="0"
             title="Tax rate in % (e.g. 15 for 15%)" class="${NUM_CLS}" data-convert-bps="true">
      <button type="button"
              class="h-8 flex items-center justify-center text-gray-300 hover:text-red-400 transition-colors"
              data-action="click->invoice-line-items#removeItem">
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24"
             fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
        </svg>
      </button>
    </div>`
}

export default class extends Controller {
  static targets = ["rows", "header"]

  connect() {
    this.updateHeader()
  }

  addItem() {
    const index = this.rowsTarget.querySelectorAll(".line-item-row").length
    const wrapper = document.createElement("div")
    wrapper.className = "line-item-row px-6 py-3 border-b border-gray-50 last:border-0"
    wrapper.innerHTML = rowHTML(index)
    this.rowsTarget.appendChild(wrapper)
    this.updateHeader()
  }

  removeItem(event) {
    const row = event.target.closest(".line-item-row")
    if (!row) return
    // Keep at least one row.
    if (this.rowsTarget.querySelectorAll(".line-item-row").length <= 1) return
    row.remove()
    this.reindex()
    this.updateHeader()
  }

  // After a removal, renumber all remaining rows so names stay sequential.
  reindex() {
    this.rowsTarget.querySelectorAll(".line-item-row").forEach((row, i) => {
      row.querySelectorAll("input[name]").forEach(input => {
        input.name = input.name.replace(/line_items\[\d+\]/, `line_items[${i}]`)
      })
    })
  }

  updateHeader() {
    if (!this.hasHeaderTarget) return
    const count = this.rowsTarget.querySelectorAll(".line-item-row").length
    this.headerTarget.classList.toggle("hidden", count <= 1)
  }
}
