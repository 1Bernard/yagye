import { Controller } from "@hotwired/stimulus"

// Instant theme switch: flips body[data-theme] immediately on click,
// before the form round-trip completes, so the palette feels instantaneous.
export default class extends Controller {
  set({ params: { value } }) {
    document.body.dataset.theme = value
  }
}
