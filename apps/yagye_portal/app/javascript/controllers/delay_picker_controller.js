import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["card"]

  connect() {
    this.sync()
  }

  select(e) {
    this.sync()
  }

  sync() {
    const checkedRadio = this.element.querySelector("input[name='settlement_delay_days']:checked")
    const val = checkedRadio ? checkedRadio.value : "0"

    this.cardTargets.forEach(card => {
      const cardVal = card.dataset.delayValue
      const isSelected = (cardVal === val)
      const indicator = card.querySelector("[data-radio-indicator]")

      if (isSelected) {
        card.classList.add("border-[#3D47F5]", "bg-indigo-50/25", "ring-1", "ring-[#3D47F5]/25")
        card.classList.remove("border-gray-200", "bg-white", "hover:border-gray-300")
        if (indicator) {
          indicator.classList.remove("border-gray-300", "bg-white")
          indicator.classList.add("border-[#3D47F5]", "bg-[#3D47F5]")
        }
      } else {
        card.classList.remove("border-[#3D47F5]", "bg-indigo-50/25", "ring-1", "ring-[#3D47F5]/25")
        card.classList.add("border-gray-200", "bg-white", "hover:border-gray-300")
        if (indicator) {
          indicator.classList.remove("border-[#3D47F5]", "bg-[#3D47F5]")
          indicator.classList.add("border-gray-300", "bg-white")
        }
      }
    })
  }
}
