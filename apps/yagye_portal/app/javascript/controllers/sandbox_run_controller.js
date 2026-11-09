import { Controller } from "@hotwired/stimulus"

function escapeHtml(str) {
  return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

function highlightJson(json) {
  const lines = json.split("\n")
  return lines.map(raw => {
    const m = raw.match(/^(\s*)("(?:[^"\\]|\\.)*")(\s*:\s*)(.*?)(,?)$/)
    if (m) {
      const [, indent, key, sep, rawVal, comma] = m
      return (
        escapeHtml(indent) +
        `<span style="color:#79c0ff">${escapeHtml(key)}</span>` +
        escapeHtml(sep) +
        colorValue(rawVal.trim()) +
        escapeHtml(comma)
      )
    }
    return escapeHtml(raw)
  }).join("\n")
}

function colorValue(token) {
  if (/^"(?:[^"\\]|\\.)*"$/.test(token)) {
    return `<span style="color:#a5d6ff">${escapeHtml(token)}</span>`
  }
  if (/^-?\d+(\.\d+)?$/.test(token)) {
    return `<span style="color:#a5d6ff">${escapeHtml(token)}</span>`
  }
  if (token === "true" || token === "false" || token === "null") {
    return `<span style="color:#79c0ff">${escapeHtml(token)}</span>`
  }
  return escapeHtml(token)
}

export default class extends Controller {
  static targets = ["btn", "result", "code"]
  static values  = { url: String }

  async run() {
    this.btnTarget.disabled    = true
    this.btnTarget.textContent = "Running…"

    try {
      const resp = await fetch(this.urlValue, {
        method:  "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
        }
      })
      const data = await resp.json()
      this.codeTarget.innerHTML      = highlightJson(JSON.stringify(data, null, 2))
      this.resultTarget.style.display = ""
      this.resultTarget.dataset.ok   = resp.ok ? "true" : "false"
    } catch {
      this.codeTarget.innerHTML      = highlightJson(JSON.stringify({ error: "Network error — check your connection." }, null, 2))
      this.resultTarget.style.display = ""
      this.resultTarget.dataset.ok   = "false"
    } finally {
      this.btnTarget.disabled    = false
      this.btnTarget.textContent = "Run in sandbox"
    }
  }
}
