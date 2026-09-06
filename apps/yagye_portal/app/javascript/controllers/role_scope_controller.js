import { Controller } from "@hotwired/stimulus"

const ALLOWED = {
  merchant: new Set(["developers", "disputes", "payments", "payouts", "settlements", "team"]),
  internal: new Set(["disputes", "kyb", "merchants", "payments", "payouts", "platform_finance", "settlements", "team"])
}

export default class extends Controller {
  static targets = ["select", "card", "permCount"]

  connect() {
    this.filter()
  }

  filter() {
    const scope  = this.selectTarget.value
    const allowed = ALLOWED[scope]

    this.cardTargets.forEach(card => {
      card.hidden = allowed ? !allowed.has(card.dataset.resource) : false
    })

    // Update the visible permission count badge
    if (this.hasPermCountTarget) {
      const visible = this.cardTargets
        .filter(c => !c.hidden)
        .reduce((n, c) => n + parseInt(c.dataset.permCount || 0, 10), 0)
      this.permCountTarget.textContent = `${visible} available`
    }
  }
}
