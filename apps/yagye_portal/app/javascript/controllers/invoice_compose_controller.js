import { Controller } from "@hotwired/stimulus"

const CURRENCY_SYMBOLS = { GHS: "GH₵", USD: "$", EUR: "€", GBP: "£", NGN: "₦", KES: "KSh", XOF: "CFA" }
const MONTHS = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]

function sym(code) { return CURRENCY_SYMBOLS[code] || code }
function fmt(cents, code) { return `${sym(code)}${(cents / 100).toFixed(2)}` }

function fmtDate(str) {
  if (!str) return "—"
  try {
    const [y, m, d] = str.split("-").map(Number)
    return `${d} ${MONTHS[m - 1]} ${y}`
  } catch { return str }
}

// ── Editor-panel row HTML ───────────────────────────────────────────────────

function editorRowHTML(i) {
  const base = [
    "w-full h-[34px] border border-gray-200 rounded-[9px] px-2.5",
    "text-[12px] text-gray-700 bg-white outline-none",
    "focus:border-[#3D47F5] transition-colors"
  ].join(" ")
  const num = base + " tabular-nums text-right"
  const sync = "data-action=\"input->invoice-compose#syncPreview\""

  return `
<div class="composer-row group" data-invoice-compose-target="composerRow">
  <div class="flex items-center gap-1.5 mb-[5px]">
    <input type="text" name="line_items[${i}][description]" placeholder="Description…"
           ${sync}
           class="${base} flex-1 placeholder-gray-300">
    <button type="button" data-action="click->invoice-compose#removeRow"
            class="w-[26px] h-[26px] flex-shrink-0 rounded-lg flex items-center justify-center
                   text-gray-200 hover:text-red-400 hover:bg-red-50 transition-colors
                   opacity-0 group-hover:opacity-100">
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"
           stroke-linecap="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
    </button>
  </div>
  <div class="grid grid-cols-3 gap-[6px]">
    <label class="block">
      <span class="text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400">Qty</span>
      <input type="number" name="line_items[${i}][quantity]" value="1" min="0.01" step="0.01"
             ${sync} class="${num} block w-full mt-[3px]">
    </label>
    <label class="block">
      <span class="text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400">Unit price</span>
      <input type="number" name="line_items[${i}][unit_amount]" placeholder="0.00" min="0" step="0.01"
             ${sync} class="${num} block w-full mt-[3px]">
    </label>
    <label class="block">
      <span class="text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400">Tax %</span>
      <input type="number" name="line_items[${i}][tax_rate_bps]" value="0" min="0" max="10000" step="0.01"
             ${sync} data-convert-bps="true" class="${num} block w-full mt-[3px]">
    </label>
  </div>
</div>`
}

// ── Preview-table row HTML ──────────────────────────────────────────────────

function previewRowHTML(desc, qty, unit, bps, currency) {
  const amount = Math.round(unit * qty + unit * qty * bps / 10_000)
  const qtyStr = qty % 1 === 0 ? qty.toFixed(0) : qty.toFixed(2)
  const td = "px-8 py-3.5"
  const tdR = td + " text-right tabular-nums"
  return `
<tr class="border-b border-gray-50 last:border-0">
  <td class="${td} text-[12.5px] text-gray-800">${desc || "<span class='text-gray-300'>—</span>"}</td>
  <td class="${tdR} text-[12px] text-gray-400">${qtyStr}</td>
  <td class="${tdR} text-[12px] text-gray-400">${sym(currency)}&thinsp;${(unit / 100).toFixed(2)}</td>
  <td class="${tdR} text-[12px] text-gray-400">${bps > 0 ? (bps / 100).toFixed(1) + "%" : "—"}</td>
  <td class="${tdR} text-[12.5px] font-semibold text-gray-900">${fmt(amount, currency)}</td>
</tr>`
}

// ── Controller ──────────────────────────────────────────────────────────────

export default class extends Controller {
  static targets = [
    "rowList",           // editor row container
    "composerRow",       // individual editor rows
    "pvBillTo",          // preview: bill-to name
    "pvNumber",          // preview: invoice number
    "pvIssued",          // preview: issue date
    "pvDue",             // preview: due date
    "pvCurrency",        // preview: currency label
    "pvRowsBody",        // preview: <tbody>
    "pvSubtotal",
    "pvTax",
    "pvTotal",
    "pvAmountDue",
    "pvTaxRow",          // totals row for tax (hidden when 0)
    "pvNotes",
    "pvNotesSection",
    "pvTerms",
    "pvTermsSection"
  ]

  connect() { this.syncPreview() }

  addRow() {
    const idx = this.rowListTarget.querySelectorAll(".composer-row").length
    const el  = document.createElement("div")
    el.innerHTML = editorRowHTML(idx).trim()
    const row = el.firstElementChild
    // separator line between rows
    if (idx > 0) {
      const sep = document.createElement("div")
      sep.className = "h-px bg-gray-50 my-3 composer-sep"
      this.rowListTarget.appendChild(sep)
    }
    this.rowListTarget.appendChild(row)
    row.querySelector("input[type=text]")?.focus()
    this.syncPreview()
  }

  removeRow(e) {
    const row  = e.target.closest(".composer-row")
    const rows = this.rowListTarget.querySelectorAll(".composer-row")
    if (!row || rows.length <= 1) return
    // remove preceding separator if any
    const prev = row.previousElementSibling
    if (prev?.classList.contains("composer-sep")) prev.remove()
    row.remove()
    this.#reindex()
    this.syncPreview()
  }

  syncPreview() {
    const currency = this.#val("currency") || "GHS"

    // Bill to
    if (this.hasPvBillToTarget) {
      const v = this.#val("customer_reference")
      this.pvBillToTarget.textContent = v || "Your customer"
      this.pvBillToTarget.style.fontStyle = v ? "normal" : "italic"
      this.pvBillToTarget.style.color     = v ? "" : "#9ca3af"
    }

    // Invoice number
    if (this.hasPvNumberTarget)
      this.pvNumberTarget.textContent = this.#val("number") || "—"

    // Dates
    if (this.hasPvIssuedTarget) this.pvIssuedTarget.textContent = fmtDate(this.#val("issue_date"))
    if (this.hasPvDueTarget)    this.pvDueTarget.textContent    = fmtDate(this.#val("due_date"))

    // Line items → preview table
    const rows = this.rowListTarget.querySelectorAll(".composer-row")
    let subtotal = 0, tax = 0
    const fragments = []

    rows.forEach(row => {
      const desc = row.querySelector('[name*="[description]"]')?.value  || ""
      const qty  = parseFloat(row.querySelector('[name*="[quantity]"]')?.value)  || 0
      const unit = Math.round((parseFloat(row.querySelector('[name*="[unit_amount]"]')?.value)  || 0) * 100)
      const bps  = parseFloat(row.querySelector('[name*="[tax_rate_bps]"]')?.value) || 0

      subtotal += Math.round(unit * qty)
      tax      += Math.round(unit * qty * bps / 10_000)
      fragments.push(previewRowHTML(desc, qty, unit, bps, currency))
    })

    if (this.hasPvRowsBodyTarget)
      this.pvRowsBodyTarget.innerHTML = fragments.join("")

    const total = subtotal + tax
    if (this.hasPvSubtotalTarget)  this.pvSubtotalTarget.textContent  = fmt(subtotal, currency)
    if (this.hasPvTaxTarget)       this.pvTaxTarget.textContent       = fmt(tax, currency)
    if (this.hasPvTotalTarget)     this.pvTotalTarget.textContent     = fmt(total, currency)
    if (this.hasPvAmountDueTarget) this.pvAmountDueTarget.textContent = fmt(total, currency)
    if (this.hasPvTaxRowTarget)    this.pvTaxRowTarget.hidden = tax === 0

    // Notes / Terms
    const notes = this.#val("notes")
    const terms = this.#val("terms")
    if (this.hasPvNotesSectionTarget) this.pvNotesSectionTarget.hidden = !notes
    if (this.hasPvNotesTarget)        this.pvNotesTarget.textContent   = notes
    if (this.hasPvTermsSectionTarget) this.pvTermsSectionTarget.hidden = !terms
    if (this.hasPvTermsTarget)        this.pvTermsTarget.textContent   = terms
  }

  // ── private ──────────────────────────────────────────────────────────────

  #val(name) {
    return this.element.querySelector(`[name="${name}"]`)?.value?.trim() || ""
  }

  #reindex() {
    this.rowListTarget.querySelectorAll(".composer-row").forEach((row, i) => {
      row.querySelectorAll("input[name]").forEach(inp => {
        inp.name = inp.name.replace(/line_items\[\d+\]/, `line_items[${i}]`)
      })
    })
  }
}
