import { Controller } from "@hotwired/stimulus"
// Drawflow loaded as global script tag — UMD build, not ESM

export default class extends Controller {
  static targets = ["canvas", "emptyState", "nameInput", "picker"]
  static values  = { graph: { type: Object, default: {} }, providers: Array, saveUrl: String, saveMethod: String, csrf: String }

  NODE_ICONS = {
    ProviderNode:  `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="3" y1="22" x2="21" y2="22"/><line x1="6" y1="18" x2="6" y2="11"/><line x1="10" y1="18" x2="10" y2="11"/><line x1="14" y1="18" x2="14" y2="11"/><line x1="18" y1="18" x2="18" y2="11"/><polygon points="12 2 20 7 4 7 12 2"/></svg>`,
    FallbackNode:  `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 .49-4.98"/></svg>`,
    ConditionNode: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3"/></svg>`,
    SplitNode:     `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="16 3 21 8 16 13"/><line x1="3" y1="8" x2="21" y2="8"/><polyline points="8 21 3 16 8 11"/><line x1="21" y1="16" x2="3" y2="16"/></svg>`
  }

  NODE_TYPES = {
    ProviderNode: {
      label: "Provider", color: "#16a34a", bg: "rgba(22,163,74,0.08)",
      inputs: 1, outputs: 1,
      defaultData: { provider_code: "", label: "Select provider" }
    },
    ConditionNode: {
      label: "Condition", color: "#d97706", bg: "rgba(217,119,6,0.08)",
      inputs: 1, outputs: 2,
      defaultData: { field: "currency", operator: "eq", value: "" }
    },
    SplitNode: {
      label: "Split", color: "#3D47F5", bg: "rgba(61,71,245,0.08)",
      inputs: 1, outputs: 2,
      defaultData: { pct_a: 70, pct_b: 30, label_a: "Primary", label_b: "Secondary" }
    },
    FallbackNode: {
      label: "Fallback", color: "#6b7280", bg: "rgba(107,114,128,0.08)",
      inputs: 1, outputs: 1,
      defaultData: { provider_code: "", label: "Select provider", max_retries: 3 }
    },
    // SimulatorNode has no live-mode credentials — test/development use only.
    // Publishing a config containing this node will be rejected by Core.
    SimulatorNode: {
      label: "Simulator", color: "#6b7280", bg: "rgba(107,114,128,0.08)",
      inputs: 1, outputs: 1,
      defaultData: { provider_code: "simulator", label: "Gateway Simulator" },
      testOnly: true
    }
  }

  TEMPLATES = {
    // Three independent paths — one explicit ConditionNode per Ghana mobile network.
    // Each MSISDN prefix maps to exactly one network (024→MTN, 050→Telecel, 026→AirtelTigo),
    // so each condition is a precise match, never an implicit "else".
    // If no condition matches (unknown network), no rule fires and the static priority
    // fallback takes over — safe by default.
    network_routing: {
      name: "Network routing",
      nodes: [
        { id: 1, type: "ConditionNode", x:  60, y:  60, data: { field: "network", operator: "eq", value: "MTN" } },
        { id: 2, type: "ProviderNode",  x: 440, y:  60, data: { provider_code: "mtn_momo",     label: "MTN MoMo" } },
        { id: 3, type: "ConditionNode", x:  60, y: 280, data: { field: "network", operator: "eq", value: "TELECEL" } },
        { id: 4, type: "ProviderNode",  x: 440, y: 280, data: { provider_code: "telecel_cash", label: "Telecel Cash" } },
        { id: 5, type: "ConditionNode", x:  60, y: 500, data: { field: "network", operator: "eq", value: "AIRTELTIGO" } },
        { id: 6, type: "ProviderNode",  x: 440, y: 500, data: { provider_code: "airteltigo",   label: "AirtelTigo Money" } }
      ],
      connections: [
        { from: 1, fromOutput: 1, to: 2, toInput: 1 },
        { from: 3, fromOutput: 1, to: 4, toInput: 1 },
        { from: 5, fromOutput: 1, to: 6, toInput: 1 }
      ]
    },
    // Percentage traffic split between two providers — for card or bank payments
    // where either processor can handle the same transaction (e.g. Paystack / Flutterwave).
    // NOT for mobile money: each MSISDN is locked to one network and cannot be
    // redirected to a different one. True weighted randomisation requires runtime
    // support (planned for P20).
    traffic_split: {
      name: "Traffic split",
      nodes: [
        { id: 1, type: "SplitNode",    x: 160, y: 200, data: { pct_a: 70, pct_b: 30, label_a: "Primary", label_b: "Secondary" } },
        { id: 2, type: "ProviderNode", x: 560, y:  80, data: { provider_code: "", label: "Primary processor" } },
        { id: 3, type: "ProviderNode", x: 560, y: 320, data: { provider_code: "", label: "Secondary processor" } }
      ],
      connections: [
        { from: 1, fromOutput: 1, to: 2, toInput: 1 },
        { from: 1, fromOutput: 2, to: 3, toInput: 1 }
      ]
    },
    // Single network condition — the simplest starting point for momo routing.
    // Only the match output (output_1) is wired; the no-match output is left
    // unconnected so payments for other networks fall through to the static
    // priority fallback rather than being misrouted.
    // Duplicate this pair for each additional network.
    network_filter: {
      name: "Network filter",
      nodes: [
        { id: 1, type: "ConditionNode", x: 100, y: 180, data: { field: "network", operator: "eq", value: "MTN" } },
        { id: 2, type: "ProviderNode",  x: 500, y: 180, data: { provider_code: "mtn_momo", label: "MTN MoMo" } }
      ],
      connections: [
        { from: 1, fromOutput: 1, to: 2, toInput: 1 }
      ]
    },
    // Route by payment method — MoMo goes to one PSP, card to another.
    // Provider nodes are left blank so you pick your connected PSPs.
    // Unmatched methods (e.g. bank transfer) fall through to the static
    // priority fallback; wire the no-match output (output_2) to handle them
    // explicitly if needed.
    method_routing: {
      name: "Method routing",
      nodes: [
        { id: 1, type: "ConditionNode", x:  60, y:  60, data: { field: "method", operator: "eq", value: "mobile_money" } },
        { id: 2, type: "ProviderNode",  x: 460, y:  60, data: { provider_code: "", label: "Mobile money provider" } },
        { id: 3, type: "ConditionNode", x:  60, y: 280, data: { field: "method", operator: "eq", value: "card" } },
        { id: 4, type: "ProviderNode",  x: 460, y: 280, data: { provider_code: "", label: "Card provider" } }
      ],
      connections: [
        { from: 1, fromOutput: 1, to: 2, toInput: 1 },
        { from: 3, fromOutput: 1, to: 4, toInput: 1 }
      ]
    }
  }

  connect() {
    // Drawflow loads from a CDN <script> tag in the page body. Stimulus may
    // connect before the external fetch completes, so we wait for the class
    // to be available rather than calling new window.Drawflow() immediately.
    const DrawflowClass = window.Drawflow?.default || window.Drawflow
    if (typeof DrawflowClass === "function") {
      this._initEditor(DrawflowClass)
    } else {
      const script = document.querySelector('script[src*="drawflow"]')
      if (script) {
        script.addEventListener("load", () => {
          const Cls = window.Drawflow?.default || window.Drawflow
          if (typeof Cls === "function") this._initEditor(Cls)
        }, { once: true })
      }
    }
  }

  _initEditor(DrawflowClass) {
    this.editor = new DrawflowClass(this.canvasTarget)
    this.editor.reroute = false
    this.editor.start()

    this.element.__routingGraph = this

    if (this.graphValue && Object.keys(this.graphValue).length > 0) {
      this._loadGraph(this.graphValue)
    } else {
      this._updateEmptyState()
    }

    this.editor.on("nodeSelected",   id => this._onNodeSelected(id))
    this.editor.on("nodeUnselected", ()  => this._onNodeUnselected())
    this.editor.on("nodeMoved",      ()  => this._updateEmptyState())
    this.editor.on("nodeCreated",    ()  => this._updateEmptyState())
    this.editor.on("nodeRemoved",    ()  => this._updateEmptyState())

    // Re-render downstream ProviderNodes when a connection is added or removed so
    // the provider dropdown filters to only methods compatible with the upstream condition.
    this.editor.on("connectionCreated", ({ output_id, input_id }) => this._rerenderProviderNode(input_id))
    this.editor.on("connectionRemoved", ({ output_id, input_id }) => this._rerenderProviderNode(input_id))

    // Delegated change listener — catches all <select> and <input> changes inside
    // any node card. Using delegation means it works after innerHTML re-renders and
    // never relies on inline onchange strings or the __routingGraph reference trick.
    this._onCanvasChange = e => {
      const field = e.target.dataset.rgField
      if (!field) return
      const nodeEl = e.target.closest("[id^='node-']")
      if (!nodeEl) return
      const nodeId = nodeEl.id.replace("node-", "")
      this.updateNodeField(field, e.target.value, nodeId)
    }
    this.canvasTarget.addEventListener("change", this._onCanvasChange)

    // Capture-phase delete listener — fires before Drawflow's bubble-phase handlers
    // so Drawflow cannot preventDefault/stopPropagation the click away from us.
    this._onDelCapture = e => {
      const btn = e.target.closest(".rg-del")
      if (!btn) return
      const nodeEl = btn.closest(".drawflow-node")
      if (!nodeEl) return
      e.stopPropagation()
      this.editor.removeNodeId(nodeEl.id)
      this._selectedNodeId = null
      this._updateEmptyState()
    }
    this.element.addEventListener("click", this._onDelCapture, { capture: true })

    // Close picker when clicking outside its wrapper
    this._onDocClick = e => {
      if (!this.hasPickerTarget) return
      const wrapper = this.pickerTarget.parentElement
      if (wrapper && !wrapper.contains(e.target)) this.closePicker()
    }

    // Document drag listeners — picker items are draggable onto canvas
    this._onDocDragstart = e => {
      const node = e.target.closest("[data-node-type]")
      if (node && this.element.contains(node)) {
        this._dragType = node.dataset.nodeType
        e.dataTransfer.setData("text/plain", this._dragType)
        e.dataTransfer.effectAllowed = "copy"
        this.closePicker()
      }
    }
    this._onDocDragend   = () => { this._dragType = null }
    this._onDocDragenter = e => {
      if (this.canvasTarget.contains(e.target) || e.target === this.canvasTarget) e.preventDefault()
    }
    this._onDocDragover  = e => {
      if (this.canvasTarget.contains(e.target) || e.target === this.canvasTarget) {
        e.preventDefault()
        if (e.dataTransfer) e.dataTransfer.dropEffect = "copy"
      }
    }
    this._onDocDrop = e => {
      if (this.canvasTarget.contains(e.target) || e.target === this.canvasTarget) this._onDrop(e)
    }

    document.addEventListener("click",     this._onDocClick)
    document.addEventListener("dragstart", this._onDocDragstart)
    document.addEventListener("dragend",   this._onDocDragend)
    document.addEventListener("dragenter", this._onDocDragenter)
    document.addEventListener("dragover",  this._onDocDragover)
    document.addEventListener("drop",      this._onDocDrop)
  }

  disconnect() {
    delete this.element.__routingGraph
    if (this._onDelCapture)   this.element.removeEventListener("click",  this._onDelCapture, { capture: true })
    if (this._onCanvasChange) this.canvasTarget.removeEventListener("change", this._onCanvasChange)
    if (this._onDocClick)     document.removeEventListener("click",     this._onDocClick)
    if (this._onDocDragstart) document.removeEventListener("dragstart", this._onDocDragstart)
    if (this._onDocDragend)   document.removeEventListener("dragend",   this._onDocDragend)
    if (this._onDocDragenter) document.removeEventListener("dragenter", this._onDocDragenter)
    if (this._onDocDragover)  document.removeEventListener("dragover",  this._onDocDragover)
    if (this._onDocDrop)      document.removeEventListener("drop",      this._onDocDrop)
  }

  // ── Zoom / fit ───────────────────────────────────────────────────────────

  zoomIn()  { this.editor.zoom_in() }
  zoomOut() { this.editor.zoom_out() }
  fitView() { this.editor.zoom_reset() }

  // ── Node picker dropdown ─────────────────────────────────────────────────

  togglePicker(event) {
    event.stopPropagation()
    if (!this.hasPickerTarget) return
    const open = this.pickerTarget.style.display === "block"
    this.pickerTarget.style.display = open ? "none" : "block"
  }

  closePicker() {
    if (this.hasPickerTarget) this.pickerTarget.style.display = "none"
  }

  addNodeFromPicker(event) {
    const type         = event.params.nodeType
    const providerCode = event.params.providerCode
    if (!type) return
    this.closePicker()
    const rect = this.canvasTarget.getBoundingClientRect()
    // Place near canvas center with slight jitter so stacked nodes are visible
    const x = (rect.width  / 2 - this.editor.canvas_x) / this.editor.zoom - 120 + (Math.random() * 60 - 30)
    const y = (rect.height / 2 - this.editor.canvas_y) / this.editor.zoom -  60 + (Math.random() * 60 - 30)
    let data = null
    if (providerCode && type === "ProviderNode") {
      const p = this.providersValue.find(p => p.code === providerCode)
      if (p) data = { provider_code: p.code, label: p.label }
    }
    this._addNode(type, x, y, data)
    this._updateEmptyState()
  }

  // ── Drop from drag ───────────────────────────────────────────────────────

  _onDrop(event) {
    event.preventDefault()
    const type = this._dragType || event.dataTransfer.getData("text/plain")
    if (!type) return
    this._dragType = null
    const rect = this.canvasTarget.getBoundingClientRect()
    const x = (event.clientX - rect.left  - this.editor.canvas_x) / this.editor.zoom
    const y = (event.clientY - rect.top   - this.editor.canvas_y) / this.editor.zoom
    this._addNode(type, x, y, null)
    this._updateEmptyState()
  }

  // ── Templates ────────────────────────────────────────────────────────────

  loadTemplate(event) {
    const key = event.params.template
    const tpl = this.TEMPLATES[key]
    if (!tpl) return

    this.editor.clearModuleSelected()
    if (this.hasNameInputTarget && !this.nameInputTarget.value) {
      this.nameInputTarget.value = tpl.name
    }

    const idMap = {}
    tpl.nodes.forEach(n => { idMap[n.id] = this._addNode(n.type, n.x, n.y, n.data) })
    tpl.connections.forEach(c => {
      const from = idMap[c.from], to = idMap[c.to]
      if (!from || !to) return
      try { this.editor.addConnection(from, to, `output_${c.fromOutput}`, `input_${c.toInput}`) } catch(_) {}
    })
    this._updateEmptyState()
    // Centre the view on the loaded template so nodes aren't off-screen
    requestAnimationFrame(() => this.fitView())
  }

  // ── Node rendering ───────────────────────────────────────────────────────

  _addNode(type, x, y, data) {
    const def = this.NODE_TYPES[type]
    if (!def) return null
    const d   = data ? { ...data } : { ...def.defaultData }
    return this.editor.addNode(type, def.inputs, def.outputs, x, y, type, d, this._nodeHtml(type, def, d))
  }

  _nodeHtml(type, def, data, nodeId = null) {
    const icon = this.NODE_ICONS[type] || ""

    const inputCss = `width:100%;border:1px solid rgba(0,0,0,0.10);border-radius:8px;background:#fafafa;
                      padding:6px 10px;font-size:12px;color:#111827;outline:none;box-sizing:border-box;
                      font-family:inherit;appearance:none;-webkit-appearance:none;`
    const labelCss = `display:block;font-size:9.5px;font-weight:700;color:#9ca3af;margin-bottom:4px;
                      letter-spacing:.07em;text-transform:uppercase;`
    const fieldDiv  = (label, inner) =>
      `<div style="margin-bottom:9px;"><label style="${labelCss}">${label}</label>${inner}</div>`
    const selectWrap = (key, opts) =>
      `<div style="position:relative;">
         <select data-rg-field="${key}"
                 style="${inputCss}padding-right:26px;cursor:pointer;">${opts}</select>
         <span style="position:absolute;right:9px;top:50%;transform:translateY(-50%);
                      color:#9ca3af;pointer-events:none;font-size:10px;line-height:1;">▾</span>
       </div>`

    // ── Trash icon — hidden by default; CSS reveals it on .drawflow-node.selected
    // No onclick here — deletion is handled by a capture-phase delegated listener
    // in _initEditor so Drawflow's own node handlers cannot intercept it first.
    const trashBtn = `
      <button class="rg-del"
              style="display:none;width:24px;height:24px;border-radius:6px;
                     border:none;background:transparent;color:#c4c9d4;cursor:pointer;
                     align-items:center;justify-content:center;flex-shrink:0;
                     padding:0;transition:background .12s,color .12s;">
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor"
             stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
          <polyline points="3 6 5 6 21 6"/>
          <path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/>
          <path d="M10 11v6"/><path d="M14 11v6"/>
          <path d="M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/>
        </svg>
      </button>`

    // ── Accent bar + header ──────────────────────────────────────────────────
    const header = `
      <div style="height:3px;background:${def.color};"></div>
      <div style="display:flex;align-items:center;gap:9px;padding:10px 14px 9px;
                  border-bottom:1px solid rgba(0,0,0,0.05);">
        <div style="width:26px;height:26px;border-radius:7px;background:${def.color}18;
                    display:flex;align-items:center;justify-content:center;flex-shrink:0;color:${def.color};">
          ${icon}
        </div>
        <div style="min-width:0;flex:1;">
          <div style="font-size:9px;font-weight:700;text-transform:uppercase;letter-spacing:.11em;
                      color:${def.color};line-height:1;margin-bottom:2px;">${def.label}</div>
          <div class="rg-node-title"
               style="font-size:12.5px;font-weight:600;color:#111827;line-height:1.25;
                      white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:148px;">
            ${this._nodeTitle(type, def, data)}
          </div>
        </div>
        ${trashBtn}
      </div>`

    // ── Per-type body with embedded controls ─────────────────────────────────
    let body = ""

    if (type === "SimulatorNode") {
      body = `<div style="background:#fefce8;border:1px solid #fde68a;border-radius:8px;
                          padding:8px 10px;font-size:11px;color:#92400e;line-height:1.4;">
        <strong style="font-weight:700;">Test only</strong> — no live credentials.<br>
        Publishing a config with this node will be rejected.
      </div>`
    }

    if (type === "ProviderNode" || type === "FallbackNode") {
      const upstreamMethod = this._upstreamMethod(nodeId)
      const eligibleProviders = this.providersValue.filter(p => {
        if (p.kind === "simulator") return false
        if (!upstreamMethod) return true
        // If the provider has no methods list, include it (safe fallback for unlisted PSPs)
        if (!p.methods || !p.methods.length) return true
        return p.methods.includes(upstreamMethod)
      })
      const methodHint = upstreamMethod
        ? `<div style="font-size:10px;color:#9ca3af;margin-top:-5px;margin-bottom:9px;">
             Showing providers that support <strong style="color:#6b7280">${upstreamMethod.replace("_", " ")}</strong>
           </div>`
        : ""
      const provOpts = `<option value="">Choose provider…</option>` +
        eligibleProviders.map(p =>
          `<option value="${p.code}" ${p.code === data.provider_code ? "selected" : ""}>${p.label}</option>`
        ).join("")
      body = methodHint + fieldDiv("Provider", selectWrap("provider_code", provOpts))
      if (type === "FallbackNode") {
        body += fieldDiv("Max retries",
          `<input type="number" min="1" max="10" value="${data.max_retries ?? 3}"
                  data-rg-field="max_retries"
                  style="${inputCss}">`)
      }
    }

    if (type === "ConditionNode") {
      const fieldOpts = [
        ["network",    "network — MTN / Telecel / AirtelTigo"],
        ["method",     "method — mobile_money / card / bank_transfer"],
        ["currency",   "currency — GHS / USD / EUR"],
        ["amount",     "amount — transaction value (minor units)"],
        ["card_brand", "card_brand — Visa / Mastercard"],
        ["risk_score", "risk_score — 0–100 from scoring service"]
      ].map(([v, l]) => `<option value="${v}" ${v === data.field ? "selected" : ""}>${l}</option>`).join("")
      const opOpts = [
        ["eq","= equals"],["neq","≠ not equals"],
        ["gt","> greater than"],["gte","≥ at least"],
        ["lt","< less than"],["lte","≤ at most"],
        ["in","in list"],["not_in","not in list"]
      ].map(([v,l]) => `<option value="${v}" ${v === data.operator ? "selected" : ""}>${l}</option>`).join("")
      body = fieldDiv("Field", selectWrap("field", fieldOpts)) +
             fieldDiv("Operator", selectWrap("operator", opOpts)) +
             fieldDiv("Value",
               `<input type="text" value="${data.value ?? ""}" placeholder="e.g. GHS"
                       data-rg-field="value"
                       style="${inputCss}">`)
    }

    if (type === "SplitNode") {
      const halfCard = (pctKey, lblKey, pctVal, lblVal, accent, bg) =>
        `<div style="flex:1;border:1.5px solid ${accent}33;border-radius:10px;padding:8px 8px 6px;
                     background:${bg};text-align:center;">
           <div>
             <input type="number" min="1" max="99" value="${pctVal}"
                    data-rg-field="${pctKey}"
                    style="width:60%;border:none;background:transparent;font-size:20px;font-weight:800;
                           color:${accent};outline:none;text-align:center;padding:0;font-family:inherit;">
             <span style="font-size:12px;font-weight:700;color:${accent};">%</span>
           </div>
           <div style="font-size:10px;color:${accent};opacity:.7;margin-top:2px;font-weight:500;">
             ${lblVal}
           </div>
         </div>`
      body = `<div style="display:flex;gap:6px;">
        ${halfCard("pct_a","label_a", data.pct_a??70, data.label_a||"Primary",   def.color, def.bg)}
        ${halfCard("pct_b","label_b", data.pct_b??30, data.label_b||"Secondary", "#6b7280", "#f9fafb")}
      </div>`
    }

    const bodyWrap = body
      ? `<div style="padding:11px 14px 10px;">${body}</div>`
      : `<div style="padding:6px 0;"></div>`

    return `<div class="rg-card"
                 style="min-width:248px;background:white;border:1px solid rgba(0,0,0,0.08);
                        border-radius:14px;overflow:hidden;
                        box-shadow:0 1px 2px rgba(0,0,0,0.04),0 4px 16px rgba(0,0,0,0.06);
                        font-family:-apple-system,BlinkMacSystemFont,'Inter',sans-serif;">
      ${header}${bodyWrap}
    </div>`
  }

  _nodeTitle(type, def, data) {
    if (type === "SimulatorNode") return "Gateway Simulator"
    if (type === "ProviderNode" || type === "FallbackNode") {
      return data.label || `<span style="color:#d1d5db;font-weight:400">Select provider</span>`
    }
    if (type === "ConditionNode") {
      const op  = { eq:"=",neq:"≠",gt:">",gte:"≥",lt:"<",lte:"≤",in:"in",not_in:"not in" }[data.operator] || "="
      const val = data.value ? `"${data.value}"` : "…"
      return `${data.field || "field"} ${op} ${val}`
    }
    if (type === "SplitNode") return `${data.pct_a || 70}% / ${data.pct_b || 30}%`
    return def.label
  }

  // ── Method-aware provider filtering ──────────────────────────────────────

  // Walk the graph to find the nearest upstream ConditionNode filtering on
  // field=method. Returns the method value string (e.g. "mobile_money") or null.
  _upstreamMethod(nodeId) {
    if (!nodeId) return null
    const allNodes = this.editor?.drawflow?.drawflow?.Home?.data
    if (!allNodes) return null
    const node = allNodes[nodeId]
    if (!node) return null
    const inputConns = Object.values(node.inputs || {}).flatMap(inp => inp.connections || [])
    for (const conn of inputConns) {
      const upstream = allNodes[conn.node]
      if (upstream?.name === "ConditionNode" && upstream.data?.field === "method") {
        return upstream.data.value || null
      }
    }
    return null
  }

  // Re-render a ProviderNode or FallbackNode in-place so its dropdown reflects
  // any new upstream method filter (called on connectionCreated/connectionRemoved).
  _rerenderProviderNode(nodeId) {
    const node = this.editor.getNodeFromId(nodeId)
    if (!node || (node.name !== "ProviderNode" && node.name !== "FallbackNode")) return
    const contentEl = this.canvasTarget.querySelector(`#node-${nodeId} .drawflow_content_node`)
    if (!contentEl) return
    contentEl.innerHTML = this._nodeHtml(node.name, this.NODE_TYPES[node.name], node.data, nodeId)
  }

  // ── Selection state (no separate panel) ──────────────────────────────────

  _onNodeSelected(id) {
    this._selectedNodeId = id
  }

  _onNodeUnselected() {
    this._selectedNodeId = null
  }

  updateNodeField(field, value, nodeId) {
    if (!nodeId) return
    const node = this.editor.getNodeFromId(nodeId)
    if (!node) return
    const newData = { ...node.data, [field]: value }
    if (field === "provider_code") {
      const p = this.providersValue.find(p => p.code === value)
      if (p) newData.label = p.label
    }
    // Changing the field makes the current value semantically stale (e.g. "mobile_money"
    // is not a valid currency). Reset it so the user is prompted to enter the right value.
    if (field === "field") newData.value = ""
    this.editor.updateNodeDataFromId(nodeId, newData)
    const contentEl = this.canvasTarget.querySelector(`#node-${nodeId} .drawflow_content_node`)
    if (!contentEl) return
    // Full re-render for select fields (interaction is done); title-only for text/number
    const isSelect = ["provider_code", "field", "operator"].includes(field)
    if (isSelect) {
      contentEl.innerHTML = this._nodeHtml(node.name, this.NODE_TYPES[node.name], newData, nodeId)
    } else {
      const titleEl = contentEl.querySelector(".rg-node-title")
      if (titleEl) titleEl.innerHTML = this._nodeTitle(node.name, this.NODE_TYPES[node.name], newData)
    }
  }


  // ── Save ─────────────────────────────────────────────────────────────────

  save() {
    const payload = this._toGraphPayload(this.editor.export())
    const name    = this.hasNameInputTarget ? this.nameInputTarget.value.trim() : "Untitled"
    const hasSimulator = payload.nodes.some(n => n.type === "SimulatorNode")
    if (hasSimulator) {
      const proceed = window.confirm(
        "This configuration contains a Simulator node.\n\n" +
        "The Simulator has no live-mode credentials — publishing this configuration will fail. " +
        "Remove the Simulator node before publishing.\n\n" +
        "Save as draft anyway?"
      )
      if (!proceed) return
    }

    const form = document.createElement("form")
    form.method = "post"
    form.action = this.saveUrlValue

    const fields = {
      authenticity_token: this.csrfValue,
      name: name || "Untitled configuration",
      graph_payload: JSON.stringify(payload)
    }
    if (this.saveMethodValue === "patch") fields["_method"] = "patch"

    Object.entries(fields).forEach(([k, v]) => {
      const inp = document.createElement("input")
      inp.type = "hidden"; inp.name = k; inp.value = v
      form.appendChild(inp)
    })

    document.body.appendChild(form)
    form.submit()
  }

  // ── Serialization ────────────────────────────────────────────────────────

  _toGraphPayload(drawflowData) {
    const nodes = [], edges = []
    const data  = drawflowData.drawflow.Home.data

    Object.entries(data).forEach(([id, node]) => {
      nodes.push({ id: `n${id}`, type: node.name, position: { x: node.pos_x, y: node.pos_y }, data: node.data })
      Object.entries(node.outputs || {}).forEach(([outputKey, output]) => {
        const outIdx = parseInt(outputKey.replace("output_", ""))
        ;(output.connections || []).forEach(conn => {
          edges.push({
            id: `e_${id}_${conn.node}_${outIdx}`,
            source: `n${id}`, target: `n${conn.node}`,
            sourceHandle: outputKey, targetHandle: conn.input,
            label: this._edgeLabel(node.name, node.data, outIdx)
          })
        })
      })
    })

    return { nodes, edges, schema_version: 1 }
  }

  _edgeLabel(nodeType, data, outputIdx) {
    if (nodeType === "ConditionNode") {
      const op = { eq:"=",neq:"≠",gt:">",gte:"≥",lt:"<",lte:"≤",in:"in",not_in:"not in" }[data.operator] || ""
      return outputIdx === 1 ? `${data.field} ${op} ${data.value}` : "no match"
    }
    if (nodeType === "SplitNode") return outputIdx === 1 ? `${data.pct_a}%` : `${data.pct_b}%`
    return ""
  }

  _loadGraph(payload) {
    if (!payload || !Array.isArray(payload.nodes)) return
    const idMap = {}
    payload.nodes.forEach(n => {
      const localId = this._addNode(n.type, n.position.x, n.position.y, n.data)
      if (localId != null) idMap[n.id] = localId
    })
    payload.edges.forEach(e => {
      const from = idMap[e.source], to = idMap[e.target]
      if (!from || !to) return
      const outIdx = parseInt((e.sourceHandle || "output_1").replace("output_", ""))
      const inIdx  = parseInt((e.targetHandle || "input_1").replace("input_", ""))
      try { this.editor.addConnection(from, to, `output_${outIdx}`, `input_${inIdx}`) } catch(_) {}
    })
    this._updateEmptyState()
  }

  // ── Empty state ──────────────────────────────────────────────────────────

  _updateEmptyState() {
    if (!this.hasEmptyStateTarget) return
    const data    = this.editor.export().drawflow.Home.data
    const isEmpty = Object.keys(data).length === 0
    this.emptyStateTarget.style.display = isEmpty ? "flex" : "none"
  }
}
