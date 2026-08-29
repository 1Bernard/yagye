import { Controller } from "@hotwired/stimulus"

// tabs — JS-toggled tab panels. Each panel element needs data-tabs-target="panel"
// and data-tabs-id="panel-name". Each tab button needs data-tabs-panel-param="panel-name".
export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    this._activate(this.tabTargets[0]?.dataset.tabsPanelParam)
  }

  show({ params: { panel } }) {
    this._activate(panel)
  }

  _activate(panelId) {
    if (!panelId) return
    this.tabTargets.forEach(tab => {
      const active = tab.dataset.tabsPanelParam === panelId
      tab.classList.toggle("border-[#3D47F5]", active)
      tab.classList.toggle("text-gray-900",     active)
      tab.classList.toggle("font-semibold",     active)
      tab.classList.toggle("border-transparent", !active)
      tab.classList.toggle("text-gray-400",     !active)
      tab.classList.toggle("font-medium",       !active)
    })
    this.panelTargets.forEach(panel => {
      panel.hidden = panel.dataset.tabsId !== panelId
    })
  }
}
