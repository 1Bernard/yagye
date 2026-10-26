import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["rate", "days", "immediateAmount", "heldAmount", "holdPeriod", "previewNotice"]

  connect() {
    this.calculate()
  }

  calculate() {
    const rateVal = parseFloat(this.rateTarget?.value) || 0
    const clampedRate = Math.min(Math.max(rateVal, 0), 25)
    const daysVal = parseInt(this.daysTarget?.value, 10) || 90

    const referenceBatch = 10000.00
    const held = (referenceBatch * (clampedRate / 100))
    const immediate = referenceBatch - held

    const fmt = (n) => "GHS " + n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })

    if (this.hasImmediateAmountTarget) {
      this.immediateAmountTarget.textContent = fmt(immediate)
    }
    if (this.hasHeldAmountTarget) {
      this.heldAmountTarget.textContent = fmt(held)
    }
    if (this.hasHoldPeriodTarget) {
      this.holdPeriodTarget.textContent = `${daysVal} days`
    }
    if (this.hasPreviewNoticeTarget) {
      if (clampedRate === 0) {
        this.previewNoticeTarget.textContent = "100% of cleared funds are disbursed immediately (0.00% reserve held)."
      } else {
        this.previewNoticeTarget.textContent = `${clampedRate.toFixed(2)}% of each batch is withheld in escrow and automatically released after ${daysVal} days.`
      }
    }
  }
}
