import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "file", "preview", "error",
    "dateField", "openingBalanceField", "closingBalanceField",
    "dateRange", "rowCount", "netMovement",
    "submitBtn",
  ]

  openFilePicker(event) {
    event.stopPropagation()
    this.fileTarget.click()
  }

  fileChanged(event) {
    const file = event.target.files[0]
    if (!file) { this.#reset(); return }

    const reader = new FileReader()
    reader.onload = (e) => this.#processCSV(e.target.result)
    reader.onerror = () => this.#showError("Could not read the file.")
    reader.readAsText(file, "UTF-8")
  }

  #processCSV(text) {
    try {
      text = text.replace(/^﻿/, "") // Strip BOM
      const allRows = text.split(/\r?\n/).map(l => l.trim()).filter(Boolean)

      // Extract simulator-generated balance comments: `# opening_balance: 500000.00`
      for (const row of allRows) {
        if (!row.startsWith("#")) continue
        const openMatch  = row.match(/^#\s*opening_balance:\s*([\d.]+)/)
        const closeMatch = row.match(/^#\s*closing_balance:\s*([\d.]+)/)
        if (openMatch  && this.hasOpeningBalanceFieldTarget) this.openingBalanceFieldTarget.value = openMatch[1]
        if (closeMatch && this.hasClosingBalanceFieldTarget) this.closingBalanceFieldTarget.value = closeMatch[1]
      }

      // Data rows only (skip comment lines)
      const rows = allRows.filter(r => !r.startsWith("#"))

      if (rows.length === 0) throw new Error("The file is empty — no data rows found.")

      const dates      = []
      let   netPesewas = 0
      let   validRows  = 0

      for (const row of rows) {
        const parts = row.split(",")
        if (parts.length < 3) continue

        const rawDate = parts[0].trim()
        const amount  = parseFloat(parts[2].trim())

        // Accept YYYY-MM-DD dates only
        if (!/^\d{4}-\d{2}-\d{2}$/.test(rawDate)) continue

        dates.push(rawDate)
        if (!isNaN(amount)) netPesewas += Math.round(amount * 100)
        validRows++
      }

      if (validRows === 0) throw new Error(
        "No valid rows found. Expected format: value_date,narrative,amount (e.g. 2026-10-01,Settlement credit,8450.00)"
      )

      dates.sort()
      const earliest = dates[0]
      const latest   = dates[dates.length - 1]

      // Auto-fill the statement date with the latest date in the file
      if (this.hasDateFieldTarget) this.dateFieldTarget.value = latest

      const ghsSign = netPesewas >= 0 ? "+" : ""
      const ghsAmt  = (netPesewas / 100).toLocaleString("en-GH", {
        minimumFractionDigits: 2, maximumFractionDigits: 2,
      })

      this.dateRangeTarget.textContent   = earliest === latest ? earliest : `${earliest} → ${latest}`
      this.rowCountTarget.textContent    = `${validRows} row${validRows !== 1 ? "s" : ""}`
      this.netMovementTarget.textContent = `GHS ${ghsSign}${ghsAmt}`

      this.errorTarget.hidden   = true
      this.previewTarget.hidden = false
      this.submitBtnTarget.disabled = false
    } catch (err) {
      this.#showError(err.message)
    }
  }

  #showError(msg) {
    this.errorTarget.textContent  = msg
    this.errorTarget.hidden       = false
    this.previewTarget.hidden     = true
    this.submitBtnTarget.disabled = true
  }

  #reset() {
    this.previewTarget.hidden     = true
    this.errorTarget.hidden       = true
    this.submitBtnTarget.disabled = true
    if (this.hasDateFieldTarget)           this.dateFieldTarget.value           = ""
    if (this.hasOpeningBalanceFieldTarget) this.openingBalanceFieldTarget.value = ""
    if (this.hasClosingBalanceFieldTarget) this.closingBalanceFieldTarget.value = ""
  }
}
