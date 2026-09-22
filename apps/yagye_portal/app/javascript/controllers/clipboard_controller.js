import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { text: String }
  static targets = ["label"]

  copy() {
    const text = this.textValue
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(() => this.flash()).catch(() => this.legacyCopy(text))
    } else {
      this.legacyCopy(text)
    }
  }

  flash() {
    if (!this.hasLabelTarget) return
    const original = this.labelTarget.textContent
    this.labelTarget.textContent = "Copied!"
    setTimeout(() => { this.labelTarget.textContent = original }, 1500)
  }

  legacyCopy(text) {
    const el = document.createElement("textarea")
    el.value = text
    el.style.cssText = "position:fixed;left:-9999px;top:-9999px;opacity:0"
    document.body.appendChild(el)
    el.focus()
    el.select()
    try { document.execCommand("copy"); this.flash() } catch (_) {}
    document.body.removeChild(el)
  }
}
