import { Controller } from "@hotwired/stimulus"

const RULES = {
  minLength: v => v.length >= 12,
  uppercase: v => /[A-Z]/.test(v),
  number:    v => /[0-9]/.test(v),
  special:   v => /[^A-Za-z0-9]/.test(v),
}

export default class extends Controller {
  static targets = ["password", "submit", "rule"]

  connect() {
    this.check()
  }

  check() {
    const val = this.hasPasswordTarget ? this.passwordTarget.value : ""
    let allMet = true

    this.ruleTargets.forEach(el => {
      const fn  = RULES[el.dataset.rule]
      const met = fn ? fn(val) : false

      el.querySelector("[data-role='unmet']").hidden = met
      el.querySelector("[data-role='met']").hidden   = !met

      el.classList.toggle("text-gray-400",  !met)
      el.classList.toggle("text-green-600", met)

      if (!met) allMet = false
    })

    if (this.hasSubmitTarget) this.submitTarget.disabled = !allMet
  }
}
