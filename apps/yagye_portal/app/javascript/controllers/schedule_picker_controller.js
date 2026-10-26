import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["frequency", "weekday", "monthday", "card", "weekdayCard"]

  connect() {
    this.sync()
  }

  toggle(e) {
    this.sync()
  }

  sync() {
    const checkedRadio = this.element.querySelector("input[name='settlement_frequency']:checked")
    const val = checkedRadio ? checkedRadio.value : (this.hasFrequencyTarget ? this.frequencyTarget.value : "daily")

    if (this.hasCardTarget) {
      this.cardTargets.forEach(card => {
        const cardVal = card.dataset.frequencyValue
        const isSelected = (cardVal === val)
        const checkIndicator = card.querySelector("[data-check-indicator]")

        if (isSelected) {
          card.classList.add("border-[#3D47F5]", "bg-indigo-50/20", "ring-1", "ring-[#3D47F5]/20")
          card.classList.remove("border-gray-200", "bg-white", "hover:border-gray-300")
          if (checkIndicator) {
            checkIndicator.classList.remove("border-gray-300", "bg-white")
            checkIndicator.classList.add("border-[#3D47F5]", "bg-[#3D47F5]")
          }
        } else {
          card.classList.remove("border-[#3D47F5]", "bg-indigo-50/20", "ring-1", "ring-[#3D47F5]/20")
          card.classList.add("border-gray-200", "bg-white", "hover:border-gray-300")
          if (checkIndicator) {
            checkIndicator.classList.remove("border-[#3D47F5]", "bg-[#3D47F5]")
            checkIndicator.classList.add("border-gray-300", "bg-white")
          }
        }
      })
    }

    if (this.hasWeekdayCardTarget) {
      const checkedDay = this.element.querySelector("input[name='settlement_day_weekly']:checked")
      this.weekdayCardTargets.forEach(card => {
        const isSelected = checkedDay && (checkedDay.value === card.dataset.weekdayValue)
        if (isSelected) {
          card.classList.add("border-[#3D47F5]", "bg-indigo-50/40", "font-semibold")
          card.classList.remove("border-gray-200", "bg-white", "hover:border-gray-300")
          card.style.color = "#3D47F5"
        } else {
          card.classList.remove("border-[#3D47F5]", "bg-indigo-50/40", "font-semibold")
          card.classList.add("border-gray-200", "bg-white", "hover:border-gray-300")
          card.style.color = ""
        }
      })
    }

    if (this.hasWeekdayTarget) {
      this.setPanel(this.weekdayTarget, val === "weekly")
    }
    if (this.hasMonthdayTarget) {
      this.setPanel(this.monthdayTarget, val === "monthly")
    }
  }

  setPanel(el, visible) {
    el.classList.toggle("hidden", !visible)
  }
}
