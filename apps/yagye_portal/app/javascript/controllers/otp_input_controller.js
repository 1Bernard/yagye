import { Controller } from "@hotwired/stimulus"

// Wires 6 individual digit boxes into a single OTP code.
// - Auto-advances on digit entry
// - Backspace moves to previous box
// - Paste of a full 6-digit code fills all boxes
// - Keeps the hidden #otp-combined input in sync so the form submits the full code
export default class extends Controller {
  static targets = ["digit", "combined"]

  connect() {
    this.digitTargets.forEach((input, i) => {
      input.addEventListener("keydown",  (e) => this.onKeyDown(e, i))
      input.addEventListener("input",    (e) => this.onInput(e, i))
      input.addEventListener("paste",    (e) => this.onPaste(e))
      input.addEventListener("focus",    ()  => input.select())
    })
  }

  onKeyDown(e, i) {
    if (e.key === "Backspace") {
      if (this.digitTargets[i].value === "" && i > 0) {
        this.digitTargets[i - 1].focus()
        this.digitTargets[i - 1].value = ""
      }
      this.sync()
    }
  }

  onInput(e, i) {
    const val = e.target.value.replace(/\D/g, "")
    e.target.value = val.slice(-1)   // keep only the last digit typed
    if (val && i < this.digitTargets.length - 1) {
      this.digitTargets[i + 1].focus()
    }
    this.sync()
  }

  onPaste(e) {
    e.preventDefault()
    const digits = (e.clipboardData.getData("text") || "").replace(/\D/g, "").slice(0, 6)
    this.digitTargets.forEach((input, i) => {
      input.value = digits[i] || ""
    })
    const last = Math.min(digits.length, this.digitTargets.length - 1)
    this.digitTargets[last].focus()
    this.sync()
  }

  sync() {
    const code = this.digitTargets.map(d => d.value).join("")
    this.combinedTarget.value = code
    if (code.length === 6) this.element.closest("form").requestSubmit()
  }
}
