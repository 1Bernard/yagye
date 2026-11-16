import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "overlay", "messages", "welcome", "header", "input", "form", "submit",
                     "fileInput", "fileChip", "fileLabel",
                     "chatScreen", "threadScreen", "threadsList"]
  static values  = { chatUrl: { type: String, default: "/ai/chat" } }

  connect() {
    this.isOpen   = false
    this.threadId = null
    this.pendingCsv = null
  }

  // ── Open / close ──────────────────────────────────────────────────────────

  toggle() { this.isOpen ? this.close() : this.open() }

  open() {
    this.isOpen = true
    document.body.classList.add("overflow-hidden")
    this.overlayTarget.classList.remove("opacity-0", "pointer-events-none")
    this.panelTarget.classList.remove("translate-x-full")
    if (this.threadId && this.hasHeaderTarget) {
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

    let content     = typed
    let displayText = typed
    if (this.pendingCsv) {
      const { name, content: csv } = this.pendingCsv
      content     = `[CSV: ${name}]\n\n${csv}${typed ? `\n\n${typed}` : ""}`
      displayText = typed ? typed : `Attached: ${name}`
      this.removeFile()
    }

    this.hideWelcome()
    this.appendUserBubble(displayText)
    this.inputTarget.value = ""
    this.autoResize()
    this.setLoading(true)

    const thinkingEl = this.appendThinking()

    try {
      const resp = await fetch(this.chatUrlValue, {
        method:  "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfToken() },
        body:    JSON.stringify({ message: content, thread_id: this.threadId })
      })
      const data = await resp.json()
      thinkingEl.remove()

      if (resp.ok && data.reply) {
        this.threadId = data.thread_id
        this.appendAssistantBubble(data.reply)
      } else {
        this.appendErrorBubble(data.error || "Something went wrong. Please try again.")
      }
    } catch {
      thinkingEl.remove()
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
    setTimeout(() => this.formTarget.requestSubmit(), 80)
  }

  keydown(event) {
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
      event.preventDefault()
      this.formTarget.requestSubmit()
    }
  }

  autoResizeInput() { this.autoResize() }

  // ── Thread history ────────────────────────────────────────────────────────

  async showThreads() {
    if (!this.hasThreadScreenTarget || !this.hasChatScreenTarget) return
    this.chatScreenTarget.classList.add("hidden")
    this.threadScreenTarget.classList.remove("hidden")
    this.threadScreenTarget.classList.add("flex")
    await this.renderThreadList()
  }

  hideThreads() {
    if (!this.hasThreadScreenTarget || !this.hasChatScreenTarget) return
    this.threadScreenTarget.classList.add("hidden")
    this.threadScreenTarget.classList.remove("flex")
    this.chatScreenTarget.classList.remove("hidden")
    setTimeout(() => this.inputTarget.focus(), 60)
  }

  async newChat() {
    this.threadId = null

    // Clear all rendered message bubbles
    this.messagesTarget.querySelectorAll(".ai-msg-in").forEach(el => el.remove())

    // Restore welcome screen
    if (this.hasWelcomeTarget) {
      const w = this.welcomeTarget
      w.style.display  = ""
      w.style.opacity  = "1"
      w.style.transition = ""
    }
    if (this.hasHeaderTarget) this.headerTarget.classList.add("invisible")

    this.hideThreads()
  }

  async loadThread(event) {
    const threadId = event.currentTarget.dataset.threadId
    if (!threadId) return

    try {
      const resp = await fetch(`${this.chatUrlValue}/threads/${threadId}`, {
        headers: { "X-CSRF-Token": this.csrfToken() }
      })
      const data = await resp.json()
      if (!resp.ok) return

      this.threadId = threadId

      // Clear existing bubbles and render loaded messages
      this.messagesTarget.querySelectorAll(".ai-msg-in").forEach(el => el.remove())
      data.messages.forEach(m => {
        if (m.role === "user") this.appendUserBubble(m.content)
        else                   this.appendAssistantBubble(m.content)
      })

      this.hideWelcome()
      if (this.hasHeaderTarget) this.headerTarget.classList.remove("invisible")
      this.hideThreads()
      this.scrollBottom()
    } catch { /* silent — user stays on thread screen */ }
  }

  async deleteThread(event) {
    event.stopPropagation()
    const threadId = event.currentTarget.dataset.threadId
    if (!threadId) return

    try {
      await fetch(`${this.chatUrlValue}/threads/${threadId}`, {
        method:  "DELETE",
        headers: { "X-CSRF-Token": this.csrfToken() }
      })
      // If we deleted the active thread, start fresh
      if (this.threadId === threadId) {
        this.threadId = null
        this.messagesTarget.querySelectorAll(".ai-msg-in").forEach(el => el.remove())
        if (this.hasWelcomeTarget) {
          this.welcomeTarget.style.display = ""
          this.welcomeTarget.style.opacity = "1"
        }
      }
      await this.renderThreadList()
    } catch { /* silent */ }
  }

  async renderThreadList() {
    if (!this.hasThreadsListTarget) return

    let threads = []
    try {
      const resp = await fetch(`${this.chatUrlValue}/threads`, {
        headers: { "X-CSRF-Token": this.csrfToken() }
      })
      const data = await resp.json()
      threads = data.threads || []
    } catch { /* fall through to empty state */ }

    if (!threads.length) {
      this.threadsListTarget.innerHTML = `
        <div class="flex flex-col items-center justify-center h-full px-6 text-center pt-10">
          <div class="w-10 h-10 rounded-xl mb-3 flex items-center justify-center"
               style="background:#f4f4f5">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#9ca3af"
                 stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
            </svg>
          </div>
          <p class="text-[13px] font-medium" style="color:#374151">No conversations yet</p>
          <p class="text-[11.5px] mt-1" style="color:#9ca3af">Your history will appear here</p>
        </div>`
      return
    }

    this.threadsListTarget.innerHTML = threads.map(t => `
      <div class="group relative flex items-start gap-3 mx-3 px-3 py-3 rounded-xl cursor-pointer
                  transition-colors hover:bg-gray-50"
           data-action="click->ai-chat#loadThread"
           data-thread-id="${this.esc(t.id)}">
        <div class="flex-1 min-w-0">
          <p class="text-[13px] font-medium truncate" style="color:#0f172a">
            ${this.esc(t.title)}
          </p>
          <p class="text-[11px] mt-0.5" style="color:#9ca3af">
            ${this.relativeTime(t.last_message_at)}
          </p>
        </div>
        <button type="button"
                class="opacity-0 group-hover:opacity-100 flex-shrink-0 w-6 h-6 rounded-lg
                       flex items-center justify-center transition-all hover:bg-red-50"
                style="color:#d1d5db"
                data-action="click->ai-chat#deleteThread"
                data-thread-id="${this.esc(t.id)}"
                title="Delete">
          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor"
               stroke-width="2.5" stroke-linecap="round">
            <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
          </svg>
        </button>
      </div>`
    ).join("")
  }

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
    s = s.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    s = s.replace(/`([^`]+)`/g,
      '<code style="font-family:monospace;font-size:12.5px;background:#f1f5f9;' +
      'padding:1px 5px;border-radius:4px;color:#4f46e5">$1</code>')
    s = s.replace(/^[-•]\s+(.+)$/gm,
      '<div style="display:flex;gap:8px;margin-top:4px">' +
      '<span style="color:#a5b4fc;flex-shrink:0;margin-top:1px">•</span><span>$1</span></div>')
    s = s.replace(/\n/g, '<br>')
    return s
  }

  // ── CSV file attach ───────────────────────────────────────────────────────

  attach() { this.fileInputTarget.click() }

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
    const MAX_ROWS  = 50
    const header    = lines[0]
    const dataRows  = lines.slice(1)
    const preview   = dataRows.slice(0, MAX_ROWS)
    const truncated = dataRows.length > MAX_ROWS
    let out = header + "\n" + preview.join("\n")
    if (truncated) out += `\n\n(Note: showing first ${MAX_ROWS} of ${dataRows.length} data rows)`
    return out
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  hideWelcome() {
    if (!this.hasWelcomeTarget || this.welcomeTarget.style.display === "none") return
    this.welcomeTarget.style.transition = "opacity 0.2s"
    this.welcomeTarget.style.opacity    = "0"
    setTimeout(() => { this.welcomeTarget.style.display = "none" }, 200)
    if (this.hasHeaderTarget && this.headerTarget.classList.contains("invisible")) {
      this.headerTarget.classList.remove("invisible")
    }
  }

  setLoading(on) { this.submitTarget.disabled = on }

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

  relativeTime(iso) {
    if (!iso) return ""
    const delta = (Date.now() - new Date(iso)) / 1000
    if (delta < 60)      return "Just now"
    if (delta < 3600)    return `${Math.floor(delta / 60)}m ago`
    if (delta < 86400)   return `${Math.floor(delta / 3600)}h ago`
    if (delta < 604800)  return `${Math.floor(delta / 86400)}d ago`
    return new Date(iso).toLocaleDateString()
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
