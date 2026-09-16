import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["frequency", "weekday", "monthday"]

  toggle() {
    const val = this.frequencyTarget.value
    this.weekdayTarget.style.display  = val === "weekly"  ? "" : "none"
    this.monthdayTarget.style.display = val === "monthly" ? "" : "none"
  }
}
