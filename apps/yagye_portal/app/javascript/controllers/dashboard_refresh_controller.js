import { Controller } from "@hotwired/stimulus"

// Auto-refreshes the dashboard every `interval` seconds via Turbo.
// Also ticks a human-friendly "last updated" label every 30 s.
export default class extends Controller {
  static targets = ["timestamp"]
  static values  = { interval: { type: Number, default: 60 } }

  connect() {
    this._loadedAt  = Date.now()
    this._tick()
    this._tickTimer    = setInterval(() => this._tick(),    30_000)
    this._refreshTimer = setInterval(() => this._reload(),  this.intervalValue * 1_000)
  }

  disconnect() {
    clearInterval(this._tickTimer)
    clearInterval(this._refreshTimer)
  }

  // Called by the manual refresh button
  reload() {
    this._reload()
  }

  _reload() {
    Turbo.visit(window.location.href, { action: "replace" })
  }

  _tick() {
    if (!this.hasTimestampTarget) return
    const secs = Math.floor((Date.now() - this._loadedAt) / 1_000)
    if      (secs <  60)  this.timestampTarget.textContent = "just now"
    else if (secs < 120)  this.timestampTarget.textContent = "1 min ago"
    else                  this.timestampTarget.textContent = `${Math.floor(secs / 60)} min ago`
  }
}
