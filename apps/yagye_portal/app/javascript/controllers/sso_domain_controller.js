import { Controller } from "@hotwired/stimulus"

// Fires on email field blur. If the domain has an active SSO config,
// reveals the SSO sign-in button and sets the correct initiate URL.
export default class extends Controller {
  static targets = ["email", "ssoSection", "ssoLink", "ssoLabel"]
  static values  = { checkUrl: String, initiateUrl: String }

  async check() {
    const email = this.emailTarget.value.trim()
    if (!email.includes("@")) { this.#hide(); return }

    try {
      const res  = await fetch(`${this.checkUrlValue}?email=${encodeURIComponent(email)}`)
      const data = await res.json()

      if (data.active) {
        this.ssoLabelTarget.textContent = `Sign in with ${data.name || "SSO"}`
        const domain = email.split("@")[1]
        this.ssoLinkTarget.href = `${this.initiateUrlValue}?domain=${encodeURIComponent(domain)}`
        this.ssoSectionTarget.hidden = false
      } else {
        this.#hide()
      }
    } catch {
      this.#hide()
    }
  }

  #hide() {
    if (this.hasSsoSectionTarget) this.ssoSectionTarget.hidden = true
  }
}
