import { Controller } from "@hotwired/stimulus"

const HIDDEN = ["opacity-0", "-translate-y-1", "scale-[0.98]", "pointer-events-none"]
const SHOWN  = ["opacity-100", "translate-y-0", "scale-100", "pointer-events-auto"]

export default class extends Controller {
  static targets = ["menu"]

  connect() {
    this._onDocClick    = this._onDocClick.bind(this)
    this._onDocKeydown  = this._onDocKeydown.bind(this)
    this._onOtherOpened = this._onOtherOpened.bind(this)
    document.addEventListener("click",            this._onDocClick)
    document.addEventListener("keydown",          this._onDocKeydown)
    document.addEventListener("dropdown:opened",  this._onOtherOpened)
  }

  disconnect() {
    document.removeEventListener("click",           this._onDocClick)
    document.removeEventListener("keydown",         this._onDocKeydown)
    document.removeEventListener("dropdown:opened", this._onOtherOpened)
  }

  toggle(event) {
    event.stopPropagation()
    this.isOpen ? this.close() : this.open()
  }

  open() {
    document.dispatchEvent(new CustomEvent("dropdown:opened", { detail: { source: this.element } }))
    this.menuTarget.classList.remove(...HIDDEN)
    this.menuTarget.classList.add(...SHOWN)
  }

  close() {
    this.menuTarget.classList.remove(...SHOWN)
    this.menuTarget.classList.add(...HIDDEN)
  }

  get isOpen() {
    return this.menuTarget.classList.contains("opacity-100")
  }

  _onOtherOpened(event) {
    if (event.detail.source !== this.element) this.close()
  }

  _onDocClick(event) {
    if (!this.element.contains(event.target)) { this.close(); return }
    if (this.hasMenuTarget && event.target.closest("a") && this.menuTarget.contains(event.target)) {
      this.close()
    }
  }

  _onDocKeydown(event) {
    if (event.key === "Escape") this.close()
  }
}
