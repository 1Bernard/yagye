import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "yagye:sidebar:collapsed"

export default class extends Controller {
  connect() {
    if (localStorage.getItem(STORAGE_KEY) === "true") {
      this.element.classList.add("sidebar-collapsed")
    }

    this._tooltip = document.getElementById("sidebar-nav-tooltip")

    this.element.querySelectorAll("[data-nav-tooltip]").forEach(el => {
      el.addEventListener("mouseenter", this._show)
      el.addEventListener("mouseleave", this._hide)
    })
  }

  disconnect() {
    this.element.querySelectorAll("[data-nav-tooltip]").forEach(el => {
      el.removeEventListener("mouseenter", this._show)
      el.removeEventListener("mouseleave", this._hide)
    })
    this._hide()
  }

  toggle() {
    const isCollapsed = this.element.classList.toggle("sidebar-collapsed")
    localStorage.setItem(STORAGE_KEY, isCollapsed)
    if (!isCollapsed) this._hide()
  }

  _show = (e) => {
    if (!this.element.classList.contains("sidebar-collapsed")) return
    if (!this._tooltip) return
    const rect = e.currentTarget.getBoundingClientRect()
    this._tooltip.textContent = e.currentTarget.dataset.navTooltip
    this._tooltip.style.top  = `${rect.top + rect.height / 2}px`
    this._tooltip.style.left = `${rect.right + 10}px`
    this._tooltip.classList.add("is-visible")
  }

  _hide = () => {
    this._tooltip?.classList.remove("is-visible")
  }
}
