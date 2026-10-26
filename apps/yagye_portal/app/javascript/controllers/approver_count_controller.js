import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["label", "card"]

  connect() {
    this.update()
    this.element.addEventListener("change", () => this.update())
  }

  update() {
    const checkboxes = this.element.querySelectorAll("input[type=checkbox][name='approver_user_codes[]']")
    let checkedCount = 0

    checkboxes.forEach(cb => {
      const card = cb.closest("[data-approver-card]")
      if (cb.checked) {
        checkedCount++
        if (card) {
          card.classList.add("border-[#3D47F5]", "bg-indigo-50/20")
          card.classList.remove("border-gray-200", "bg-white")
        }
      } else {
        if (card) {
          card.classList.remove("border-[#3D47F5]", "bg-indigo-50/20")
          card.classList.add("border-gray-200", "bg-white")
        }
      }
    })

    if (this.hasLabelTarget) {
      this.labelTarget.textContent =
        checkedCount === 0 ? "No approvers selected"
                           : `${checkedCount} ${checkedCount === 1 ? "approver" : "approvers"} authorized`
    }
  }
}
