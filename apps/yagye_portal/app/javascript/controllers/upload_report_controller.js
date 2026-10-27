import { Controller } from "@hotwired/stimulus"

// Filename → provider code heuristics for Ghana MNOs.
const PROVIDER_PATTERNS = [
  { pattern: /SIMULATOR/i, code: "simulator" },
  { pattern: /MTN/i,       code: "mtn_gh" },
  { pattern: /VODAFONE|TELECEL/i, code: "vodafone_gh" },
  { pattern: /AIRTEL|TIGO/i, code: "airteltigo_gh" },
]

export default class extends Controller {
  static targets = [
    "file", "preview", "error",
    "providerSelect", "dateDisplay", "lineCount", "netTotal",
    "submitBtn",
  ]

  openFilePicker(event) {
    event.stopPropagation()
    this.fileTarget.click()
  }

  fileChanged(event) {
    const file = event.target.files[0]
    if (!file) { this.reset(); return }

    const reader = new FileReader()
    reader.onload = (e) => this.#processCSV(e.target.result, file.name)
    reader.onerror = () => this.#showError("Could not read the file.")
    reader.readAsText(file, "UTF-8")
  }

  #processCSV(text, filename) {
    try {
      // Strip BOM
      text = text.replace(/^﻿/, "")
      const lines = text.split(/\r?\n/).map(l => l.trim()).filter(Boolean)

      if (lines.length < 2) throw new Error("File appears to be empty — no data rows found.")

      const header = lines[0].split(",").map(h => h.trim().toUpperCase())
      const required = ["SETTLEMENT_DATE", "LINE_NO", "CHARGE_REF", "LINE_TYPE",
                        "GROSS_PESEWAS", "FEE_PESEWAS", "NET_PESEWAS", "VALUE_DATE"]
      const missing = required.filter(col => !header.includes(col))
      if (missing.length) throw new Error(`Missing columns: ${missing.join(", ")}`)

      const netIdx  = header.indexOf("NET_PESEWAS")
      const dateIdx = header.indexOf("VALUE_DATE")

      const dataRows = lines.slice(1)
      const firstCols = dataRows[0].split(",").map(c => c.trim())
      const reportDate = firstCols[dateIdx] || "—"

      const netTotal = dataRows.reduce((sum, row) => {
        const cols = row.split(",")
        return sum + (parseInt(cols[netIdx], 10) || 0)
      }, 0)

      const ghs = (netTotal / 100).toLocaleString("en-GH", {
        minimumFractionDigits: 2, maximumFractionDigits: 2,
      })

      // Auto-detect provider from filename
      const detected = PROVIDER_PATTERNS.find(p => p.pattern.test(filename))
      if (detected) this.providerSelectTarget.value = detected.code

      this.dateDisplayTarget.textContent  = reportDate
      this.lineCountTarget.textContent    = `${dataRows.length} row${dataRows.length !== 1 ? "s" : ""}`
      this.netTotalTarget.textContent     = `GHS ${ghs}`

      this.errorTarget.hidden   = true
      this.previewTarget.hidden = false
      this.submitBtnTarget.disabled = false
    } catch (err) {
      this.#showError(err.message)
    }
  }

  #showError(msg) {
    this.errorTarget.textContent = msg
    this.errorTarget.hidden      = false
    this.previewTarget.hidden    = true
    this.submitBtnTarget.disabled = true
  }

  reset() {
    this.previewTarget.hidden     = true
    this.errorTarget.hidden       = true
    this.submitBtnTarget.disabled = true
  }
}
