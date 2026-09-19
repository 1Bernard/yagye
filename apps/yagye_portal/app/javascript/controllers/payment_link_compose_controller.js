import { Controller } from "@hotwired/stimulus"

const SYM = { GHS: "GH₵", USD: "$", NGN: "₦", KES: "KSh", XOF: "CFA" }
const s = c => SYM[c] || c

export default class extends Controller {
  static targets = [
    "amountRow",          // editor: amount input row (hidden for open-amount kind)
    "maxUsesRow",         // editor: max-uses row (hidden when single-use)
    "pvDescription",      // preview: product description
    "pvAmountLabel",      // preview: "Total" label (empty for open amount)
    "pvAmount",           // preview: amount value or "You choose"
    "pvPayButton",        // preview: CTA button text
    "pvCustomerSection"   // preview: wraps all collect fields; hidden when none checked
  ]

  connect() { this.syncPreview() }

  syncPreview() {
    const currency = this.#val("currency") || "GHS"
    const kind     = this.element.querySelector('[name="kind"]:checked')?.value || "fixed_amount"
    const amount   = parseFloat(this.#val("amount")) || 0
    const fixed    = kind === "fixed_amount"

    // Editor: show/hide amount input row
    if (this.hasAmountRowTarget) this.amountRowTarget.hidden = !fixed

    // Preview: description
    if (this.hasPvDescriptionTarget) {
      const desc = this.#val("description")
      this.pvDescriptionTarget.textContent  = desc || "Your product"
      this.pvDescriptionTarget.style.opacity = desc ? "1" : "0.35"
    }

    // Preview: amount display
    const display = fixed && amount > 0 ? `${s(currency)} ${amount.toFixed(2)}` : "You choose"
    if (this.hasPvAmountLabelTarget)
      this.pvAmountLabelTarget.textContent = fixed && amount > 0 ? "Total" : ""
    if (this.hasPvAmountTarget)
      this.pvAmountTarget.textContent = display

    // Preview: CTA button
    if (this.hasPvPayButtonTarget)
      this.pvPayButtonTarget.textContent = fixed && amount > 0
        ? `Pay ${s(currency)} ${amount.toFixed(2)}`
        : "Pay now"

    // Preview: payment method pills — driven by data-pl-method attribute
    this.element.querySelectorAll("[data-pl-method]").forEach(el => {
      const checked = this.element
        .querySelector(`[name="allowed_methods[]"][value="${el.dataset.plMethod}"]`)?.checked
      el.hidden = !checked
    })

    // Preview: collect customer fields — driven by data-pl-collect attribute
    let anyCollect = false
    this.element.querySelectorAll("[data-pl-collect]").forEach(el => {
      const checked = this.element.querySelector(`[name="${el.dataset.plCollect}"]`)?.checked
      el.hidden = !checked
      if (checked) anyCollect = true
    })
    if (this.hasPvCustomerSectionTarget) this.pvCustomerSectionTarget.hidden = !anyCollect

    // Editor: max-uses row (shown only when reusable is checked)
    if (this.hasMaxUsesRowTarget)
      this.maxUsesRowTarget.hidden = !this.element.querySelector('[name="reusable"]')?.checked
  }

  #val(name) {
    return this.element.querySelector(`[name="${name}"]`)?.value?.trim() || ""
  }
}
