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
    this.ensureStyles()
  }

  ensureStyles() {
    if (document.getElementById('ai-page-styles')) return
    const style = document.createElement('style')
    style.id = 'ai-page-styles'
    style.textContent =
      `.ai-trow:last-child td{border-bottom:none!important}` +
      `.ai-trow:hover td{background:#f9fafb}` +
      `.ai-fb-row{display:flex;align-items:center;gap:3px;margin-top:8px}` +
      `.ai-fb-btn{display:flex;align-items:center;justify-content:center;` +
        `width:24px;height:24px;border-radius:5px;border:none;` +
        `background:none;cursor:pointer;color:#9ca3af;opacity:0.4;` +
        `transition:opacity 0.15s,color 0.15s,background 0.15s;padding:0}` +
      `.ai-fb-btn:hover{opacity:1;background:#f3f4f6}` +
      `.ai-fb-btn.ai-fb-active{opacity:1}` +
      `.ai-dot{width:6px;height:6px;border-radius:50%;background:#9ca3af;` +
        `animation:ai-pulse 1.2s ease-in-out infinite}` +
      `@keyframes ai-pulse{0%,100%{opacity:0.3;transform:scale(0.8)}50%{opacity:1;transform:scale(1)}}`
    document.head.appendChild(style)
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
      </div>
      ${this.feedbackRowHtml(text)}`
    this.messagesTarget.appendChild(el)
    this.scrollBottom()
  }

  feedbackRowHtml(text) {
    const encoded = this.esc(text)
    return `
      <div class="ai-fb-row">
        <button type="button" class="ai-fb-btn" title="Copy response"
                data-action="click->ai-chat#copyMessage" data-text="${encoded}">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor"
               stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>
          </svg>
        </button>
        <button type="button" class="ai-fb-btn" title="Good response"
                data-action="click->ai-chat#thumbsUp">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor"
               stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M14 9V5a3 3 0 0 0-3-3l-4 9v11h11.28a2 2 0 0 0 2-1.7l1.38-9a2 2 0 0 0-2-2.3H14z"/>
            <path d="M7 22H4a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2h3"/>
          </svg>
        </button>
        <button type="button" class="ai-fb-btn" title="Bad response"
                data-action="click->ai-chat#thumbsDown">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor"
               stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M10 15v4a3 3 0 0 0 3 3l4-9V2H5.72a2 2 0 0 0-2 1.7l-1.38 9a2 2 0 0 0 2 2.3H10z"/>
            <path d="M17 2h2.67A2.31 2.31 0 0 1 22 4v7a2.31 2.31 0 0 1-2.33 2H17"/>
          </svg>
        </button>
      </div>`
  }

  copyMessage(event) {
    const text = event.currentTarget.dataset.text
    navigator.clipboard?.writeText(text)
      .then(() => {
        const btn = event.currentTarget
        const prev = btn.style.color
        btn.style.color = "#10b981"
        btn.style.opacity = "1"
        setTimeout(() => { btn.style.color = prev; btn.style.opacity = "" }, 1800)
      })
      .catch(() => {})
  }

  thumbsUp(event) {
    const btn = event.currentTarget
    const row = btn.closest(".ai-fb-row")
    const wasActive = btn.classList.contains("ai-fb-active")
    row.querySelectorAll(".ai-fb-btn").forEach(b => { b.classList.remove("ai-fb-active"); b.style.color = "" })
    if (!wasActive) { btn.classList.add("ai-fb-active"); btn.style.color = "#6366f1" }
  }

  thumbsDown(event) {
    const btn = event.currentTarget
    const row = btn.closest(".ai-fb-row")
    const wasActive = btn.classList.contains("ai-fb-active")
    row.querySelectorAll(".ai-fb-btn").forEach(b => { b.classList.remove("ai-fb-active"); b.style.color = "" })
    if (!wasActive) { btn.classList.add("ai-fb-active"); btn.style.color = "#ef4444" }
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

  // ── Markdown ──────────────────────────────────────────────────────────────

  renderMarkdown(raw) {
    const lines  = raw.split('\n')
    const blocks = []
    let i = 0

    while (i < lines.length) {
      if (i + 1 < lines.length &&
          this.#isTableRow(lines[i]) &&
          this.#isTableSep(lines[i + 1])) {
        const tLines = [lines[i], lines[i + 1]]
        i += 2
        while (i < lines.length && this.#isTableRow(lines[i])) {
          tLines.push(lines[i++])
        }
        blocks.push(this.#renderTable(tLines))
      } else {
        blocks.push(this.#renderInline(lines[i]))
        i++
      }
    }

    return blocks.join('<br>')
  }

  #isTableRow(line) {
    return /^\s*\|/.test(line) && /\|\s*$/.test(line)
  }

  #isTableSep(line) {
    return /^\s*\|[\s|:=-]+\|\s*$/.test(line)
  }

  #parseRow(line) {
    return line.split('|').slice(1, -1).map(c => c.trim())
  }

  #renderTable(lines) {
    const headers = this.#parseRow(lines[0])
    const rows    = lines.slice(2).map(l => this.#parseRow(l))

    const ths = headers.map(h =>
      `<th style="padding:6px 10px;text-align:left;font-size:11px;font-weight:600;` +
      `color:#6b7280;background:#f8fafc;border-bottom:1px solid #e5e7eb;white-space:nowrap">` +
      `${this.#renderInline(h)}</th>`
    ).join('')

    const trs = rows.map(row => {
      const tds = row.map(cell =>
        `<td style="padding:5px 10px;font-size:12px;color:#374151;` +
        `border-bottom:1px solid #f3f4f6">${this.#renderInline(cell)}</td>`
      ).join('')
      return `<tr class="ai-trow">${tds}</tr>`
    }).join('')

    return `<div style="overflow-x:auto;margin:4px 0;border-radius:8px;` +
           `border:1px solid #e5e7eb;background:#fff">` +
           `<table style="width:100%;border-collapse:collapse">` +
           `<thead><tr>${ths}</tr></thead>` +
           `<tbody>${trs}</tbody>` +
           `</table></div>`
  }

  #renderInline(text) {
    let s = this.esc(text)
    s = s.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    s = s.replace(/`([^`]+)`/g,
      '<code style="font-family:monospace;font-size:12px;background:#f1f5f9;' +
      'padding:1px 4px;border-radius:4px;color:#4f46e5">$1</code>')
    s = s.replace(/^[-•]\s+(.+)$/,
      '<div style="display:flex;gap:8px;margin-top:4px">' +
      '<span style="color:#a5b4fc;flex-shrink:0;margin-top:1px">•</span><span>$1</span></div>')
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
