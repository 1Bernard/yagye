import { Controller } from "@hotwired/stimulus"

// Trims the live payment feed to maxValue rows after Turbo Stream prepends.
// Also hides the "No payments yet" empty state on first arrival.
export default class extends Controller {
  static values = { max: { type: Number, default: 6 } }

  connect() {
    this.observer = new MutationObserver(() => this.onMutation())
    this.observer.observe(this.element, { childList: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  onMutation() {
    if (this.element.children.length > 0) {
      const empty = document.getElementById("payment-feed-empty")
      if (empty) empty.hidden = true
    }
    const rows = Array.from(this.element.children)
    rows.slice(this.maxValue).forEach(el => el.remove())
  }
}
