import { Controller } from "@hotwired/stimulus"

// Shows a countdown modal 2 minutes before the session expires.
// data-session-expiry-timeout-seconds-value = server-side timeout in seconds
// data-session-expiry-keepalive-url-value   = POST URL for the keepalive endpoint
// data-session-expiry-sign-out-url-value    = sign-out URL (for the sign-out button)
export default class extends Controller {
  static values = {
    timeoutSeconds:  Number,
    keepaliveUrl:    String,
    signOutUrl:      String,
  }

  static targets = ["modal", "countdown"]

  connect() {
    this.reset()
    this._bindActivity()
  }

  disconnect() {
    this._clearTimers()
    this._unbindActivity()
  }

  // ── Public (called from the modal buttons) ────────────────────────────────

  stayLoggedIn() {
    this._dismiss()
    fetch(this.keepaliveUrlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": this._csrfToken(), "Content-Type": "application/json" },
    }).then(() => this.reset()).catch(() => this.reset())
  }

  signOut() {
    window.location.href = this.signOutUrlValue
  }

  // ── Private ───────────────────────────────────────────────────────────────

  reset() {
    this._clearTimers()
    this._dismiss()
    const warnAt = (this.timeoutSecondsValue - 120) * 1000   // 2 min before expiry
    const expireAt = this.timeoutSecondsValue * 1000
    if (warnAt > 0) {
      this._warnTimer   = setTimeout(() => this._showWarning(), warnAt)
    }
    this._expireTimer = setTimeout(() => window.location.reload(), expireAt)
  }

  _showWarning() {
    if (!this.hasModalTarget) return
    this.modalTarget.hidden = false
    this._startCountdown(120)
  }

  _dismiss() {
    if (this.hasModalTarget) this.modalTarget.hidden = true
    clearInterval(this._countdownInterval)
  }

  _startCountdown(seconds) {
    let remaining = seconds
    this._updateCountdown(remaining)
    this._countdownInterval = setInterval(() => {
      remaining -= 1
      this._updateCountdown(remaining)
      if (remaining <= 0) {
        clearInterval(this._countdownInterval)
        window.location.reload()
      }
    }, 1000)
  }

  _updateCountdown(s) {
    if (!this.hasCountdownTarget) return
    const m = Math.floor(s / 60)
    const sec = String(s % 60).padStart(2, "0")
    this.countdownTarget.textContent = `${m}:${sec}`
  }

  _clearTimers() {
    clearTimeout(this._warnTimer)
    clearTimeout(this._expireTimer)
    clearInterval(this._countdownInterval)
  }

  _csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content ?? ""
  }

  _bindActivity() {
    this._onActivity = () => this.reset()
    ;["click", "keydown", "scroll", "mousemove"].forEach(ev =>
      document.addEventListener(ev, this._onActivity, { passive: true })
    )
  }

  _unbindActivity() {
    ;["click", "keydown", "scroll", "mousemove"].forEach(ev =>
      document.removeEventListener(ev, this._onActivity)
    )
  }
}
