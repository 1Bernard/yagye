import { Controller } from "@hotwired/stimulus"

const SYM = { GHS: "GH₵", USD: "$", NGN: "₦", KES: "KSh", XOF: "CFA" }
const s = c => SYM[c] || c

export default class extends Controller {
  static targets = [
    "amountRow",          // editor: amount input row (hidden for open-amount kind)
    "maxUsesRow",         // editor: max-uses row (hidden when single-use)
    "escrowToggle",       // editor: escrow enabled checkbox
    "escrowDetails",      // editor: escrow config fields (auto-release days, dispute window)
    "pvDescription",      // preview: product description
    "pvAmountLabel",      // preview: totals row amount value
    "pvAmount",           // preview: amount hero value or "You choose"
    "pvPayButton",        // preview: CTA button text
    "pvCustomerSection",  // preview: wraps all collect fields; hidden when none checked
    "pvEscrowBadge",      // preview: trust hold badge shown when escrow enabled
    "brandHex"            // editor: hex text input paired with the colour picker
  ]

  connect() {
    // Only run full sync when this controller wraps the form editor (not the show-page preview)
    if (this.element.querySelector('[name="currency"]')) this.syncPreview()
  }

  syncPreview() {
    const currency  = this.#val("currency") || "GHS"
    const kind      = this.element.querySelector('[name="kind"]:checked')?.value || "fixed_amount"
    const amount    = parseFloat(this.#val("amount")) || 0
    const discount  = Math.max(parseFloat(this.#val("discount_amount")) || 0, 0)
    const netAmount = Math.max(amount - discount, 0)
    const fixed     = kind === "fixed_amount"

    // Editor: show/hide amount input row
    if (this.hasAmountRowTarget) this.amountRowTarget.hidden = !fixed

    // Preview: description
    if (this.hasPvDescriptionTarget) {
      const desc = this.#val("description")
      this.pvDescriptionTarget.textContent  = desc || "Your product"
      this.pvDescriptionTarget.style.opacity = desc ? "1" : "0.35"
    }

    // Preview: amount display (shows net after discount)
    const display = fixed && netAmount > 0 ? `${s(currency)} ${netAmount.toFixed(2)}` : "You choose"
    if (this.hasPvAmountLabelTarget)
      this.pvAmountLabelTarget.textContent = display
    if (this.hasPvAmountTarget)
      this.pvAmountTarget.textContent = display

    // Preview: CTA button — custom label (from dropdown) wins over computed text
    if (this.hasPvPayButtonTarget) {
      const custom = this.pvPayButtonTarget.dataset.customLabel
      if (!custom) {
        this.pvPayButtonTarget.textContent = fixed && netAmount > 0
          ? `Pay ${s(currency)} ${netAmount.toFixed(2)}`
          : "Pay now"
      }
    }

    // Preview: payment method pills — only when method checkboxes exist in this scope
    const methodBoxes = [...this.element.querySelectorAll('[name="allowed_methods[]"]')]
    if (methodBoxes.length > 0) {
      this.element.querySelectorAll("[data-pl-method]").forEach(el => {
        const checked = this.element
          .querySelector(`[name="allowed_methods[]"][value="${el.dataset.plMethod}"]`)?.checked
        el.hidden = !checked
      })
      // Fix separator on first visible method item after show/hide
      const visibleMethods = [...this.element.querySelectorAll("[data-pl-method]:not([hidden])")]
      visibleMethods.forEach((el, idx) => {
        const sep = el.querySelector(".pv-method-sep")
        if (sep) sep.hidden = idx === 0
      })
    }

    // Preview: collect customer fields — driven by data-pl-collect attribute
    const collectBoxes = [...this.element.querySelectorAll('[name^="collect_"]')]
    if (collectBoxes.length > 0) {
      let anyCollect = false
      this.element.querySelectorAll("[data-pl-collect]").forEach(el => {
        const checked = this.element.querySelector(`[name="${el.dataset.plCollect}"]`)?.checked
        el.hidden = !checked
        if (checked) anyCollect = true
      })
      if (this.hasPvCustomerSectionTarget) this.pvCustomerSectionTarget.hidden = !anyCollect
    }

    // Editor: max-uses row (shown only when reusable is checked)
    if (this.hasMaxUsesRowTarget)
      this.maxUsesRowTarget.hidden = !this.element.querySelector('[name="reusable"]')?.checked
  }

  // Colour picker → update hex text field + preview brand colour live
  syncBrand() {
    const color  = this.element.querySelector('[name="checkout_config[brand_colour]"]')?.value
    const name   = this.element.querySelector('[name="checkout_config[display_name]"]')?.value?.trim()
    if (this.hasBrandHexTarget) this.brandHexTarget.value = color || ""

    if (color) {
      this.element.querySelectorAll("[data-brand-color]").forEach(el => {
        el.style.setProperty("--preview-brand", color)
      })
      // Update all inline brand-coloured elements in the preview
      this.element.querySelectorAll("[data-pv-brand-bg]").forEach(el => {
        el.style.background = color
      })
      this.element.querySelectorAll("[data-pv-brand-border]").forEach(el => {
        el.style.borderColor = color
      })
      this.element.querySelectorAll("[data-pv-brand-dot]").forEach(el => {
        el.style.background = color
      })
      this.element.querySelectorAll("[data-pv-brand-text]").forEach(el => {
        el.style.color = color
      })
    }

    if (name !== undefined) {
      this.element.querySelectorAll("[data-pv-merchant-name]").forEach(el => {
        el.textContent = name || "Your business"
      })
      this.element.querySelectorAll("[data-pv-merchant-initials]").forEach(el => {
        const parts = (name || "Your business").trim().split(/\s+/).slice(0, 2)
        el.textContent = parts.map(w => w[0]?.toUpperCase() || "").join("")
      })
    }

    // Re-apply selected-method brand color in preview
    const selected = this.element.querySelector("[data-pl-method]:not([hidden]) .pv-method-hd")
      ?.closest("[data-pl-method]")
    if (selected && color) {
      const dot = selected.querySelector(".pv-radio-dot")
      if (dot) dot.style.borderColor = color
      const inner = selected.querySelector(".pv-radio-inner")
      if (inner) inner.style.background = color
      const icon = selected.querySelector(".pv-method-icon")
      if (icon) icon.style.color = color
      const hd = selected.querySelector(".pv-method-hd")
      if (hd) hd.style.background = `${color}0d`
    }

    this.syncPreview()
  }

  // Discount input → recompute total shown in preview
  syncDiscountPreview() {
    this.syncPreview()
  }

  // Hex text input → keep colour picker in sync
  syncBrandHex() {
    const hex = this.brandHexTarget.value.trim()
    if (/^#[0-9a-fA-F]{6}$/.test(hex)) {
      const picker = this.element.querySelector('[name="checkout_config[brand_colour]"]')
      if (picker) picker.value = hex
      this.syncBrand()
    }
  }

  selectPreviewMethod(event) {
    const clicked = event.currentTarget.closest("[data-pl-method]")
    if (!clicked) return
    const color = this.element.querySelector('[name="checkout_config[brand_colour]"]')?.value || "#3D47F5"

    this.element.querySelectorAll("[data-pl-method]").forEach(el => {
      const on = el === clicked
      // Outer item has no border of its own (parent has the outer border)
      // Update header background
      const hd = el.querySelector(".pv-method-hd")
      if (hd) hd.style.background = on ? `${color}0d` : "#FFFFFF"
      // Update radio dot border
      const dot = el.querySelector(".pv-radio-dot")
      if (dot) dot.style.borderColor = on ? color : "#E5E7EB"
      // Update radio inner visibility + color
      const inner = el.querySelector(".pv-radio-inner")
      if (inner) { inner.hidden = !on; inner.style.background = color }
      // Update method icon color
      const icon = el.querySelector(".pv-method-icon")
      if (icon) icon.style.color = on ? color : "#9CA3AF"
      // Update label weight/color
      const lbl = hd?.querySelector("p")
      if (lbl) {
        lbl.style.fontWeight = on ? "600" : "500"
        lbl.style.color = on ? "#111827" : "#6B7280"
      }
      // Toggle body
      const body = el.querySelector("[data-pl-method-body]")
      if (body) body.hidden = !on
    })
  }

  toggleEscrow() {
    const enabled = this.hasEscrowToggleTarget && this.escrowToggleTarget.checked
    if (this.hasEscrowDetailsTarget) this.escrowDetailsTarget.hidden = !enabled
    if (this.hasPvEscrowBadgeTarget) this.pvEscrowBadgeTarget.hidden = !enabled
  }

  toggleFormTerms(event) {
    const checked = event.currentTarget.checked
    const fields = document.getElementById("form-terms-fields")
    if (fields) fields.style.display = checked ? "" : "none"
    const previewRow = this.element.querySelector("[data-pv-terms-row]")
    if (previewRow) previewRow.hidden = !checked
  }

  syncHeadlinePreview(event) {
    const text    = event.currentTarget.value.trim()
    const wrapper = this.element.querySelector("[data-pv-headline-wrapper]")
    const el      = this.element.querySelector("[data-pv-headline]")
    if (wrapper) wrapper.hidden = !text
    if (el)      el.textContent = text
  }

  syncCtaPreview(event) {
    const label = event.currentTarget.value
    if (this.hasPvPayButtonTarget) {
      this.pvPayButtonTarget.dataset.customLabel = label
      if (label) {
        this.pvPayButtonTarget.textContent = label
      } else {
        // Revert to computed label
        delete this.pvPayButtonTarget.dataset.customLabel
        this.syncPreview()
      }
    }
  }

  syncTermsLabelPreview(event) {
    const el = this.element.querySelector("[data-pv-terms-label]")
    if (el) el.textContent = event.currentTarget.value.trim() || "I agree to the Terms & Conditions"
  }

  #val(name) {
    return this.element.querySelector(`[name="${name}"]`)?.value?.trim() || ""
  }
}
