import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "showIcon", "hideIcon"]

  toggle() {
    const showing = this.inputTarget.type === "text"
    this.inputTarget.type = showing ? "password" : "text"
    this.showIconTarget.hidden = showing    // eye: visible when password is now shown
    this.hideIconTarget.hidden = !showing   // eye_off: visible when password is now hidden
  }
}
