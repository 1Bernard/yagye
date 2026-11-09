import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel", "copyArea"]
  static values  = { active: { type: String, default: "curl" } }

  connect() {
    this.show(this.activeValue)
  }

  switch(event) {
    this.show(event.params.lang)
  }

  show(lang) {
    this.activeValue = lang

    this.tabTargets.forEach(tab => {
      const isActive = tab.dataset.codeTabsLangParam === lang
      tab.style.color      = isActive ? "#c9d1d9" : "#8b949e"
      tab.style.background = isActive ? "rgba(201,209,217,0.1)" : "transparent"
    })

    this.panelTargets.forEach(panel => {
      panel.hidden = panel.dataset.lang !== lang
    })

    if (this.hasCopyAreaTarget) {
      this.copyAreaTargets.forEach(area => {
        area.hidden = area.dataset.lang !== lang
      })
    }
  }
}
