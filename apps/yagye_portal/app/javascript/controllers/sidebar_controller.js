import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "yagye:sidebar:collapsed"

export default class extends Controller {
  connect() {
    if (localStorage.getItem(STORAGE_KEY) === "true") {
      this.element.classList.add("sidebar-collapsed")
    }
  }

  toggle() {
    const isCollapsed = this.element.classList.toggle("sidebar-collapsed")
    localStorage.setItem(STORAGE_KEY, isCollapsed)
  }
}
