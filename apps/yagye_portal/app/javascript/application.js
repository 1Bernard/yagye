// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// ── Session expiry guard ──────────────────────────────────────────────────────
// When the user returns to a tab after a long absence (≥ 28 min, just under
// Devise's 30-min timeoutable window), reload the page so CSRF tokens are
// fresh and the server-side session hasn't silently expired behind the scenes.
let lastActivityAt = Date.now()

document.addEventListener("turbo:load",         () => { lastActivityAt = Date.now() })
document.addEventListener("turbo:submit-start", () => { lastActivityAt = Date.now() })

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState !== "visible") return
  const awayMs = Date.now() - lastActivityAt
  if (awayMs > 28 * 60 * 1000) window.location.reload()
})

// ── Global submit-button loading state ───────────────────────────────────────
// Dims and locks the submitting button on every form POST so users get
// immediate feedback that something is happening. Skips buttons already
// managed by the loading-button Stimulus controller (which shows a spinner
// and swap text — a richer interaction for primary auth/action buttons).
document.addEventListener("turbo:submit-start", (event) => {
  const btn = event.detail.formSubmission.submitter
  if (!btn) return
  if (btn.dataset.controller?.includes("loading-button")) return
  btn.classList.add("opacity-70", "cursor-wait", "pointer-events-none")
  btn.dataset.turboLoading = "true"
})

document.addEventListener("turbo:submit-end", () => {
  document.querySelectorAll("[data-turbo-loading='true']").forEach((btn) => {
    btn.classList.remove("opacity-70", "cursor-wait", "pointer-events-none")
    delete btn.dataset.turboLoading
  })
})
