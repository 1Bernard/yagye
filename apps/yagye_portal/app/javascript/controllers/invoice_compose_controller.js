import { Controller } from "@hotwired/stimulus"

const CURRENCY_SYMBOLS = { GHS: "GH₵", USD: "$", EUR: "€", GBP: "£", NGN: "₦", KES: "KSh", XOF: "CFA" }
const MONTHS = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]

function sym(code) { return CURRENCY_SYMBOLS[code] || code }
function fmt(cents, code) { return `${sym(code)}${(cents / 100).toFixed(2)}` }

function fmtSize(bytes) {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

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
  return `
<tr class="border-b border-gray-50 last:border-0">
  <td class="pl-5 pr-3 py-3.5 text-[12.5px] text-gray-800">${desc || "<span class='text-gray-300'>—</span>"}</td>
  <td class="px-3 py-3.5 text-right tabular-nums text-[12px] text-gray-400">${qtyStr}</td>
  <td class="px-3 py-3.5 text-right tabular-nums text-[12px] text-gray-400">${sym(currency)}&thinsp;${(unit / 100).toFixed(2)}</td>
  <td class="px-3 py-3.5 text-right tabular-nums text-[12px] text-gray-400">${bps > 0 ? parseFloat((bps / 100).toFixed(4)).toString() + "%" : "—"}</td>
  <td class="pl-3 pr-5 py-3.5 text-right tabular-nums text-[12.5px] font-semibold text-gray-900">${fmt(amount, currency)}</td>
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
    "pvTaxRow",          // totals row for tax (hidden when 0)
    "pvDiscount",
    "pvDiscountRow",     // totals row for discount (hidden when 0)
    "pvTotal",
    "pvAmountDue",
    "pvNotes",
    "pvNotesSection",
    "pvTerms",
    "pvTermsSection",
    "pvNotesTermsSection",
    "pdfS3Key",    // hidden input for uploaded PDF s3 key
    "pdfStatus",   // status / error line below the file card
    "pdfDropZone", // the dashed drop zone container
    "pdfInput",    // the hidden file input
    "pdfFileCard", // file item row (shown after pick)
    "pdfFileName", // filename text in the file card
    "pdfFileMeta"  // size / status text in the file card
  ]

  connect() { this.syncPreview() }

  handlePdfUpload(e) {
    const file = e.target.files[0]
    if (!file) return
    this.#processFile(file)
  }

  browsePdf() {
    if (this.hasPdfInputTarget) this.pdfInputTarget.click()
  }

  onDragOver(e) {
    e.preventDefault()
    if (!this.hasPdfDropZoneTarget) return
    this.pdfDropZoneTarget.classList.add("!border-[#3D47F5]/50", "!bg-[#3D47F5]/[0.03]")
    this.pdfDropZoneTarget.classList.remove("border-gray-200")
  }

  onDragLeave() {
    if (!this.hasPdfDropZoneTarget) return
    this.pdfDropZoneTarget.classList.remove("!border-[#3D47F5]/50", "!bg-[#3D47F5]/[0.03]")
    this.pdfDropZoneTarget.classList.add("border-gray-200")
  }

  onDrop(e) {
    e.preventDefault()
    this.onDragLeave()
    const file = e.dataTransfer?.files[0]
    if (!file) return
    this.#processFile(file)
  }

  clearPdf() {
    if (this.hasPdfInputTarget)    this.pdfInputTarget.value = ""
    if (this.hasPdfFileCardTarget) this.pdfFileCardTarget.classList.add("hidden")
    if (this.hasPdfS3KeyTarget)    this.pdfS3KeyTarget.value = ""
    if (this.hasPdfStatusTarget) {
      this.pdfStatusTarget.textContent = ""
      this.pdfStatusTarget.classList.add("hidden")
    }
  }

  async #processFile(file) {
    if (!file.type.includes("pdf") && !file.name.toLowerCase().endsWith(".pdf")) {
      this.#showStatus("Only PDF files are supported.", "#ef4444")
      return
    }

    this.#showFileCard(file, "Extracting…")
    if (this.hasPdfStatusTarget) this.pdfStatusTarget.classList.add("hidden")

    const form = new FormData()
    form.append("pdf", file)
    const csrfEl = this.element.querySelector('[name="authenticity_token"]')
    if (csrfEl) form.append("authenticity_token", csrfEl.value)

    try {
      const res  = await fetch("/invoices/extract-pdf", { method: "POST", body: form })
      const data = await res.json()

      this.#setFileMeta(fmtSize(file.size))

      if (!res.ok || data.error) {
        this.#showStatus(data.error || "Extraction failed — please enter details manually.", "#ef4444")
        return
      }

      if (this.hasPdfS3KeyTarget) this.pdfS3KeyTarget.value = data.pdf_s3_key || ""

      const f = data.fields || {}
      this.#setField("customer_reference", f.customer_reference)
      this.#setField("number",             f.number)
      this.#setField("issue_date",         f.issue_date)
      this.#setField("due_date",           f.due_date)
      this.#setField("currency",           f.currency)
      this.#setField("notes",              f.notes)
      if (f.discount_amount != null) this.#setField("discount_amount", String(f.discount_amount))

      if (Array.isArray(f.line_items) && f.line_items.length > 0) this.#prefillLineItems(f.line_items)

      this.syncPreview()

      const msg = data.extraction_error
        ? `Partial import — ${data.extraction_error}`
        : "Invoice imported. Review and adjust as needed."
      this.#showStatus(msg, data.extraction_error ? "#f59e0b" : "#10b981")
    } catch {
      this.#setFileMeta(fmtSize(file.size))
      this.#showStatus("Network error — please try again.", "#ef4444")
    }
  }

  #showFileCard(file, meta = "") {
    if (!this.hasPdfFileCardTarget) return
    if (this.hasPdfFileNameTarget) this.pdfFileNameTarget.textContent = file.name
    this.#setFileMeta(meta)
    this.pdfFileCardTarget.classList.remove("hidden")
  }

  #setFileMeta(text) {
    if (this.hasPdfFileMetaTarget) this.pdfFileMetaTarget.textContent = text
  }

  #showStatus(msg, color = "#6b7280") {
    if (!this.hasPdfStatusTarget) return
    this.pdfStatusTarget.textContent = msg
    this.pdfStatusTarget.style.color = color
    this.pdfStatusTarget.classList.remove("hidden")
  }

  saveDraft(e) {
    e.preventDefault()
    const form = this.element.querySelector("form#invoice-form")
    if (!form) return
    let hidden = form.querySelector('[name="save_as_draft"]')
    if (!hidden) {
      hidden = document.createElement("input")
      hidden.type = "hidden"
      hidden.name = "save_as_draft"
      form.appendChild(hidden)
    }
    hidden.value = "1"
    form.requestSubmit()
  }

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

    const discountRaw = parseFloat(this.element.querySelector('[name="discount_amount"]')?.value) || 0
    const discount    = Math.round(discountRaw * 100)
    const total       = Math.max(subtotal + tax - discount, 0)

    if (this.hasPvSubtotalTarget)    this.pvSubtotalTarget.textContent    = fmt(subtotal, currency)
    if (this.hasPvTaxTarget)         this.pvTaxTarget.textContent         = fmt(tax, currency)
    if (this.hasPvTaxRowTarget)      this.pvTaxRowTarget.hidden           = tax === 0
    if (this.hasPvDiscountTarget)    this.pvDiscountTarget.textContent    = `− ${fmt(discount, currency)}`
    if (this.hasPvDiscountRowTarget) this.pvDiscountRowTarget.hidden      = discount === 0
    if (this.hasPvTotalTarget)       this.pvTotalTarget.textContent       = fmt(total, currency)
    if (this.hasPvAmountDueTarget)   this.pvAmountDueTarget.textContent   = fmt(total, currency)

    // Notes / Terms
    const notes = this.#val("notes")
    const terms = this.#val("terms")
    if (this.hasPvNotesTarget)             this.pvNotesTarget.textContent          = notes
    if (this.hasPvNotesSectionTarget)      this.pvNotesSectionTarget.hidden        = !notes
    if (this.hasPvTermsTarget)             this.pvTermsTarget.textContent          = terms
    if (this.hasPvTermsSectionTarget)      this.pvTermsSectionTarget.hidden        = !terms
    if (this.hasPvNotesTermsSectionTarget) this.pvNotesTermsSectionTarget.hidden   = !notes && !terms
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

  #setField(name, value) {
    if (value == null || value === "") return
    const el = this.element.querySelector(`[name="${name}"]`)
    if (el) el.value = value
  }

  #prefillLineItems(items) {
    // Remove all separators and rows except the first
    this.rowListTarget.querySelectorAll(".composer-sep").forEach(s => s.remove())
    const existing = this.rowListTarget.querySelectorAll(".composer-row")
    existing.forEach((r, i) => { if (i > 0) r.remove() })

    items.forEach((item, i) => {
      if (i > 0) this.addRow()
      const rows = this.rowListTarget.querySelectorAll(".composer-row")
      const row  = rows[i]
      if (!row) return
      row.querySelector('[name*="[description]"]').value = item.description || ""
      row.querySelector('[name*="[quantity]"]').value    = item.quantity ?? 1
      row.querySelector('[name*="[unit_amount]"]').value = item.unit_amount ?? 0
      const bpsEl = row.querySelector('[name*="[tax_rate_bps]"]')
      if (bpsEl) bpsEl.value = item.tax_rate_bps ?? 0
    })
  }
}
