import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["saveBtn", "savedBadge", "checkoutUrl", "logoUrlInput", "previewLogoImg", "copyUrlBtn"]
  static values  = {
    saveUrl: String,
    csrf:    String,
    mode:    { type: String, default: "live" }
  }

  connect() {
    this._dirty = false
    this._setSavedState()
  }

  updateLogo(event) {
    const url = event.currentTarget.value.trim()
    if (!this.hasPreviewLogoImgTarget) return
    const el = this.previewLogoImgTarget
    if (url) {
      if (el.tagName === "IMG") {
        el.src = url
      } else {
        const img = document.createElement("img")
        img.src = url; img.alt = "Logo"
        img.className = "w-7 h-7 rounded-lg object-cover flex-shrink-0 border border-gray-100"
        img.dataset.checkoutLayoutTarget = "previewLogoImg"
        el.replaceWith(img)
      }
    } else {
      if (el.tagName === "IMG") {
        const div = document.createElement("div")
        div.className = "w-7 h-7 rounded-lg bg-[#3D47F5] flex items-center justify-center"
        div.dataset.checkoutLayoutTarget = "previewLogoImg"
        div.innerHTML = `<span class="flex w-[13px] h-[13px] text-white"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg></span>`
        el.replaceWith(div)
      }
    }
    this._markDirty()
  }

  copyUrl() {
    const url = this.hasCheckoutUrlTarget ? this.checkoutUrlTarget.href : ""
    if (!url) return
    const btn = this.hasCopyUrlBtnTarget ? this.copyUrlBtnTarget : null
    navigator.clipboard.writeText(url).then(() => {
      if (!btn) return
      const orig = btn.innerHTML
      btn.innerHTML = "<span style=\"color:#16a34a;font-size:11.5px;font-weight:500\">Copied!</span>"
      setTimeout(() => { btn.innerHTML = orig }, 2000)
    }).catch(() => {})
  }

  navigateLink(event) {
    window.location = `/payment-links/${event.target.value}/layout`
  }

  // ── Appearance ────────────────────────────────────────────────────────────

  updateBrandColor(event) {
    const hex = event.currentTarget.value.trim()
    if (!/^#[0-9a-fA-F]{6}$/.test(hex)) return
    const picker = this.element.querySelector("input[type='color']")
    if (picker) picker.value = hex
    this._applyBrandColor(hex)
    this._markDirty()
  }

  syncColorHex(event) {
    const hex = event.currentTarget.value
    const hexInput = this.element.querySelector("[data-preview-color-hex]")
    if (hexInput) hexInput.value = hex
    this._applyBrandColor(hex)
    this._markDirty()
  }

  _applyBrandColor(hex) {
    this.element.querySelectorAll("[data-pv-brand-bg]").forEach(el => { el.style.background = hex })
    this.element.querySelectorAll("[data-pv-brand-border]").forEach(el => { el.style.borderColor = hex })
    this.element.querySelectorAll("[data-pv-brand-dot]").forEach(el => { el.style.background = hex })
    this.element.querySelectorAll("[data-pv-brand-text]").forEach(el => { el.style.color = hex })
  }

  updateFont(event) {
    this._markDirty()
  }

  // ── Content ───────────────────────────────────────────────────────────────

  updateBusinessName(event) {
    const name = event.currentTarget.value.trim()
    this.element.querySelectorAll("[data-pv-merchant-name]").forEach(el => {
      el.textContent = name || el.dataset.defaultName || "Your business"
    })
    this.element.querySelectorAll("[data-pv-merchant-initials]").forEach(el => {
      const parts = (name || "Your business").split(/\s+/).slice(0, 2)
      el.textContent = parts.map(w => w[0]?.toUpperCase() || "").join("")
    })
    this._markDirty()
  }

  updateHeadline(event) {
    const text    = event.currentTarget.value.trim()
    const wrapper = this.element.querySelector("[data-pv-headline-wrapper]")
    const el      = this.element.querySelector("[data-pv-headline]")
    if (wrapper) wrapper.hidden = !text
    if (el)      el.textContent = text
    this._markDirty()
  }

  // ── CTA ───────────────────────────────────────────────────────────────────

  updateCta(event) {
    const label = event.currentTarget.value
    const btn   = this.element.querySelector('[data-payment-link-compose-target="pvPayButton"]')
    if (btn) btn.textContent = label || btn.dataset.defaultLabel || "Pay now"
    this._markDirty()
  }

  // ── Terms ─────────────────────────────────────────────────────────────────

  toggleTerms(event) {
    const fields     = this.element.querySelector("[data-terms-fields]")
    const previewRow = this.element.querySelector("[data-pv-terms-row]")
    if (fields)     fields.style.display = event.currentTarget.checked ? "" : "none"
    if (previewRow) previewRow.hidden = !event.currentTarget.checked
    this._markDirty()
  }

  updateTermsLabel(event) {
    const el = this.element.querySelector("[data-pv-terms-label]")
    if (el) el.textContent = event.currentTarget.value.trim() || "I agree to the Terms & Conditions"
    this._markDirty()
  }

  updateTermsUrl(event) {
    const el = this.element.querySelector("[data-pv-terms-label]")
    if (el) {
      const hasUrl = event.currentTarget.value.trim().length > 0
      el.classList.toggle("underline", hasUrl)
      el.classList.toggle("text-gray-500", !hasUrl)
      el.style.color = hasUrl ? "var(--preview-brand, #3D47F5)" : ""
    }
    this._markDirty()
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  save() {
    const layout = this._collectLayout()
    this.saveBtnTarget.disabled = true
    this.saveBtnTarget.textContent = "Saving…"

    fetch(this.saveUrlValue, {
      method:  "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfValue },
      body:    JSON.stringify({ layout })
    })
      .then(r => r.json())
      .then(data => {
        if (data.ok) {
          this._dirty = false
          this._setSavedState()
          if (this.hasSavedBadgeTarget) {
            this.savedBadgeTarget.hidden = false
            setTimeout(() => { this.savedBadgeTarget.hidden = true }, 3000)
          }
          if (this.hasCheckoutUrlTarget && data.checkout_url) {
            this.checkoutUrlTarget.textContent = data.checkout_url
            this.checkoutUrlTarget.href        = data.checkout_url
          }
        } else {
          this._handleError(data.error)
        }
      })
      .catch(() => this._handleError("Network error — please try again."))
  }

  _handleError(msg) {
    this.saveBtnTarget.textContent = "Save layout"
    this.saveBtnTarget.disabled = false
    alert(msg || "Failed to save layout.")
  }

  _setSavedState() {
    this.saveBtnTarget.disabled = true
    this.saveBtnTarget.textContent = "Saved"
    this.saveBtnTarget.style.opacity = "0.55"
    this.saveBtnTarget.style.cursor  = "default"
  }

  _markDirty() {
    if (this._dirty) return
    this._dirty = true
    this.saveBtnTarget.disabled = false
    this.saveBtnTarget.textContent = "Save layout"
    this.saveBtnTarget.style.opacity = ""
    this.saveBtnTarget.style.cursor  = ""
  }

  _collectLayout() {
    const logo_url      = this.hasLogoUrlInputTarget ? this.logoUrlInputTarget.value.trim() : ""
    const hexInput      = this.element.querySelector("[data-preview-color-hex]")
    const brand_color   = hexInput?.value.trim() || ""
    const fontSelect    = this.element.querySelector("select[data-action*='updateFont']")
    const font_family   = fontSelect?.value || ""
    const bizInput      = this.element.querySelector("[data-action*='updateBusinessName']")
    const business_name = bizInput?.value.trim() || ""
    const headlineInput = this.element.querySelector("[data-action*='updateHeadline']")
    const headline      = headlineInput?.value.trim() || ""
    const ctaSelect     = this.element.querySelector("select[data-action*='updateCta']")
    const cta_text      = ctaSelect?.value || ""
    const termsToggle   = this.element.querySelector("[data-terms-toggle]")
    const termsLabel    = this.element.querySelector("[data-action*='updateTermsLabel']")
    const termsUrl      = this.element.querySelector("[data-action*='updateTermsUrl']")
    const terms = {
      enabled: termsToggle?.checked ?? false,
      label:   termsLabel?.value.trim() || "I agree to the Terms & Conditions",
      url:     termsUrl?.value.trim() || ""
    }

    return {
      mode: this.modeValue,
      ...(logo_url    ? { logo_url }    : {}),
      ...(brand_color ? { brand_color } : {}),
      ...(font_family ? { font_family } : {}),
      business_name,
      headline,
      cta_text,
      terms
    }
  }
}
