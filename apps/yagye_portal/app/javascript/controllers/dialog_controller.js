import { Controller } from "@hotwired/stimulus"

// Opens and closes native <dialog> elements by ID.
// Usage:
//   data-controller="dialog"  — on any ancestor (or the button itself)
//   data-action="click->dialog#open" data-dialog-target-param="my-dialog-id"
//   data-action="click->dialog#close" data-dialog-target-param="my-dialog-id"
export default class extends Controller {
  static values = { target: String }

  open(event) {
    const id = event.params?.target || this.targetValue
    document.getElementById(id)?.showModal()
  }

  close(event) {
    const id = event.params?.target || this.targetValue
    document.getElementById(id)?.close()
  }
}
