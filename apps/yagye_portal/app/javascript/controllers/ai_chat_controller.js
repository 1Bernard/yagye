import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "overlay", "messages", "welcome", "header", "input", "form", "submit",
                     "fileInput", "fileChip", "fileLabel"]
  static values  = { chatUrl: { type: String, default: "/ai/chat" } }

  connect() {
    this.isOpen   = false
    this.history  = []
    this.pendingCsv = null  // { name, content } when a file is loaded
  }

  // ── Open / close ──────────────────────────────────────────────────────────

  toggle() { this.isOpen ? this.close() : this.open() }

  open() {
    this.isOpen = true
    document.body.classList.add("overflow-hidden")
    this.overlayTarget.classList.remove("opacity-0", "pointer-events-none")
    this.panelTarget.classList.remove("translate-x-full")
    // If reopening with existing history, show logo immediately
    if (this.history.length > 0 && this.hasHeaderTarget) {
      this.headerTarget.classList.remove("invisible")
    }
    setTimeout(() => this.inputTarget.focus(), 320)
  }

  close() {
    this.isOpen = false
    document.body.classList.remove("overflow-hidden")
    this.overlayTarget.classList.add("opacity-0", "pointer-events-none")
    this.panelTarget.classList.add("translate-x-full")
  }

  // ── Chat ──────────────────────────────────────────────────────────────────

  async send(event) {
    event.preventDefault()
    const typed = this.inputTarget.value.trim()
    if (!typed && !this.pendingCsv) return

    // Build the full message content — CSV block first, then user's question
    let fullContent = typed
    let displayText = typed
    if (this.pendingCsv) {
      const { name, content } = this.pendingCsv
      fullContent = `[CSV: ${name}]\n\n${content}${typed ? `\n\n${typed}` : ""}`
      displayText = typed ? typed : `Attached: ${name}`
      this.removeFile()
    }

    this.hideWelcome()
    this.history.push({ role: "user", content: fullContent })
    this.appendUserBubble(displayText)
    this.inputTarget.value = ""
    this.autoResize()
    this.setLoading(true)

    const thinkingEl = this.appendThinking()

    try {
      const resp = await fetch(this.chatUrlValue, {
        method:  "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken()
        },
        body: JSON.stringify({ history: this.history })
      })
      const data = await resp.json()
      thinkingEl.remove()

      if (resp.ok && data.reply) {
        this.history.push({ role: "assistant", content: data.reply })
        this.appendAssistantBubble(data.reply)
      } else {
        this.history.pop()
        this.appendErrorBubble(data.error || "Something went wrong. Please try again.")
      }
    } catch {
      thinkingEl.remove()
      this.history.pop()
      this.appendErrorBubble("Connection error — check your network and try again.")
    } finally {
      this.setLoading(false)
    }
  }

  suggest(event) {
    this.inputTarget.value = event.params.text
    this.autoResize()
    this.inputTarget.focus()
    this.hideWelcome()
    // Auto-submit after a brief delay so the user sees the text
    setTimeout(() => this.formTarget.requestSubmit(), 80)
  }

  keydown(event) {
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
      event.preventDefault()
      this.formTarget.requestSubmit()
    }
  }

  autoResizeInput() { this.autoResize() }

  // ── Bubble builders ───────────────────────────────────────────────────────

  appendUserBubble(text) {
    const el = document.createElement("div")
    el.className = "ai-msg-in flex justify-end px-5 mb-3"
    el.innerHTML = `
      <div class="max-w-[82%] text-gray-800 text-[13.5px] leading-relaxed whitespace-pre-wrap px-4 py-2.5 rounded-2xl rounded-br-sm"
           style="background:#f4f4f5;border:1px solid #ebebeb">
        ${this.esc(text)}
      </div>`
    this.messagesTarget.appendChild(el)
    this.scrollBottom()
  }

  appendAssistantBubble(text) {
    const el = document.createElement("div")
    el.className = "ai-msg-in px-5 mb-5"
    el.innerHTML = `
      <div class="text-[13.5px] leading-relaxed text-gray-700"
           style="word-break:break-word">
        ${this.renderMarkdown(text)}
      </div>`
    this.messagesTarget.appendChild(el)
    this.scrollBottom()
  }

  appendThinking() {
    const el = document.createElement("div")
    el.className = "flex items-center gap-[5px] px-5 mb-4 pt-1"
    el.innerHTML = `
      <span class="ai-dot"></span>
      <span class="ai-dot" style="animation-delay:.15s"></span>
      <span class="ai-dot" style="animation-delay:.30s"></span>`
    this.messagesTarget.appendChild(el)
    this.scrollBottom()
    return el
  }

  appendErrorBubble(text) {
    const el = document.createElement("div")
    el.className = "ai-msg-in px-5 mb-4"
    el.innerHTML = `
      <div class="text-[12.5px] text-red-500 px-4 py-3 rounded-xl"
           style="background:#fff1f2;border:1px solid #fecdd3">
        ${this.esc(text)}
      </div>`
    this.messagesTarget.appendChild(el)
    this.scrollBottom()
  }

  // ── Markdown-lite ─────────────────────────────────────────────────────────

  renderMarkdown(raw) {
    let s = this.esc(raw)
    // Bold: **text**
    s = s.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    // Inline code: `code`
    s = s.replace(/`([^`]+)`/g,
      '<code style="font-family:monospace;font-size:12.5px;background:#f1f5f9;' +
      'padding:1px 5px;border-radius:4px;color:#4f46e5">$1</code>')
    // Bullet list lines
    s = s.replace(/^[-•]\s+(.+)$/gm,
      '<div style="display:flex;gap:8px;margin-top:4px">' +
      '<span style="color:#a5b4fc;flex-shrink:0;margin-top:1px">•</span><span>$1</span></div>')
    // Line breaks
    s = s.replace(/\n/g, '<br>')
    return s
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  // ── CSV file attach ───────────────────────────────────────────────────────

  attach() {
    this.fileInputTarget.click()
  }

  fileChange(event) {
    const file = event.target.files[0]
    if (!file) return

    if (file.size > 2 * 1024 * 1024) {
      this.appendErrorBubble("CSV file is too large (max 2 MB). Please upload a smaller file.")
      event.target.value = ""
      return
    }

    const reader = new FileReader()
    reader.onload = (e) => {
      const parsed = this.parseCSV(e.target.result, file.name)
      this.pendingCsv = { name: file.name, content: parsed }
      this.fileLabelTarget.textContent = file.name
      this.fileChipTarget.classList.remove("hidden")
      this.inputTarget.focus()
    }
    reader.readAsText(file)
    // Reset input so the same file can be re-attached after removal
    event.target.value = ""
  }

  removeFile() {
    this.pendingCsv = null
    this.fileChipTarget.classList.add("hidden")
    this.fileLabelTarget.textContent = ""
  }

  parseCSV(text, filename) {
    const lines = text.trim().split(/\r?\n/).filter(l => l.trim())
    if (!lines.length) return `(empty file: ${filename})`

    const MAX_ROWS = 50
    const header   = lines[0]
    const dataRows = lines.slice(1)
    const preview  = dataRows.slice(0, MAX_ROWS)
    const truncated = dataRows.length > MAX_ROWS

    let out = header + "\n" + preview.join("\n")
    if (truncated) {
      out += `\n\n(Note: showing first ${MAX_ROWS} of ${dataRows.length} data rows)`
    }
    return out
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  hideWelcome() {
    if (this.hasWelcomeTarget && this.welcomeTarget.style.display !== "none") {
      this.welcomeTarget.style.transition = "opacity 0.2s"
      this.welcomeTarget.style.opacity    = "0"
      setTimeout(() => { this.welcomeTarget.style.display = "none" }, 200)

      // Reveal the logo the first time a message is sent
      if (this.hasHeaderTarget && this.headerTarget.classList.contains("invisible")) {
        this.headerTarget.classList.remove("invisible")
      }
    }
  }

  setLoading(on) {
    this.submitTarget.disabled = on
  }

  scrollBottom() {
    requestAnimationFrame(() => {
      this.messagesTarget.scrollTo({ top: this.messagesTarget.scrollHeight, behavior: "smooth" })
    })
  }

  autoResize() {
    const ta = this.inputTarget
    ta.style.height = "auto"
    ta.style.height = Math.min(ta.scrollHeight, 120) + "px"
  }

  esc(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
