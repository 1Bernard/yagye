import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  toggle() {
    window.dispatchEvent(new CustomEvent("ai:toggle"))
  }
}
