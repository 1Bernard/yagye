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
    }
  }

  TEMPLATES = {
    simple_failover: {
      name: "Simple failover",
      nodes: [
        { id: 1, type: "ProviderNode", x: 340, y: 180, data: { provider_code: "mtn_momo",     label: "MTN MoMo" } },
        { id: 2, type: "FallbackNode", x: 660, y: 180, data: { provider_code: "telecel_cash", label: "Telecel Cash", max_retries: 3 } }
      ],
      connections: [{ from: 1, fromOutput: 1, to: 2, toInput: 1 }]
    },
    currency_split: {
      name: "Currency split",
      nodes: [
        { id: 1, type: "ConditionNode", x: 200, y: 200, data: { field: "currency", operator: "eq", value: "GHS" } },
        { id: 2, type: "ProviderNode",  x: 520, y:  90, data: { provider_code: "mtn_momo", label: "MTN MoMo" } },
        { id: 3, type: "ProviderNode",  x: 520, y: 310, data: { provider_code: "stripe",   label: "Stripe" } }
      ],
      connections: [
        { from: 1, fromOutput: 1, to: 2, toInput: 1 },
        { from: 1, fromOutput: 2, to: 3, toInput: 1 }
      ]
    },
    amount_threshold: {
      name: "Amount threshold",
      nodes: [
        { id: 1, type: "ConditionNode", x: 200, y: 200, data: { field: "amount", operator: "gt", value: "50000" } },
        { id: 2, type: "ProviderNode",  x: 520, y:  90, data: { provider_code: "stripe",   label: "Stripe (high value)" } },
        { id: 3, type: "ProviderNode",  x: 520, y: 310, data: { provider_code: "mtn_momo", label: "MTN MoMo (standard)" } }
      ],
      connections: [
        { from: 1, fromOutput: 1, to: 2, toInput: 1 },
        { from: 1, fromOutput: 2, to: 3, toInput: 1 }
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
    const type = event.params.nodeType
    if (!type) return
    this.closePicker()
    const rect = this.canvasTarget.getBoundingClientRect()
    // Place near canvas center with slight jitter so stacked nodes are visible
    const x = (rect.width  / 2 - this.editor.canvas_x) / this.editor.zoom - 120 + (Math.random() * 60 - 30)
    const y = (rect.height / 2 - this.editor.canvas_y) / this.editor.zoom -  60 + (Math.random() * 60 - 30)
    this._addNode(type, x, y, null)
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
  }

  // ── Node rendering ───────────────────────────────────────────────────────

  _addNode(type, x, y, data) {
    const def = this.NODE_TYPES[type]
    if (!def) return null
    const d   = data ? { ...data } : { ...def.defaultData }
    return this.editor.addNode(type, def.inputs, def.outputs, x, y, type, d, this._nodeHtml(type, def, d))
  }

  _nodeHtml(type, def, data) {
    const icon = this.NODE_ICONS[type] || ""
    const rc   = "this.closest('[data-controller]').__routingGraph"

    const inputCss = `width:100%;border:1px solid rgba(0,0,0,0.10);border-radius:8px;background:#fafafa;
                      padding:6px 10px;font-size:12px;color:#111827;outline:none;box-sizing:border-box;
                      font-family:inherit;appearance:none;-webkit-appearance:none;`
    const labelCss = `display:block;font-size:9.5px;font-weight:700;color:#9ca3af;margin-bottom:4px;
                      letter-spacing:.07em;text-transform:uppercase;`
    const fieldDiv  = (label, inner) =>
      `<div style="margin-bottom:9px;"><label style="${labelCss}">${label}</label>${inner}</div>`
    const selectWrap = (key, opts) =>
      `<div style="position:relative;">
         <select onchange="${rc}.updateNodeField('${key}', this.value)"
                 style="${inputCss}padding-right:26px;cursor:pointer;">${opts}</select>
         <span style="position:absolute;right:9px;top:50%;transform:translateY(-50%);
                      color:#9ca3af;pointer-events:none;font-size:10px;line-height:1;">▾</span>
       </div>`

    // ── Trash icon — hidden by default; CSS reveals it on .drawflow-node.selected
    const trashBtn = `
      <button class="rg-del" onclick="${rc}.deleteSelected()"
              style="display:none;width:24px;height:24px;border-radius:6px;
                     border:none;background:transparent;color:#c4c9d4;cursor:pointer;
                     align-items:center;justify-content:center;flex-shrink:0;
                     padding:0;transition:background .12s,color .12s;"
              onmouseover="this.style.background='#fef2f2';this.style.color='#ef4444'"
              onmouseout="this.style.background='transparent';this.style.color='#c4c9d4'">
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

    if (type === "ProviderNode" || type === "FallbackNode") {
      const provOpts = `<option value="">Choose provider…</option>` +
        this.providersValue.map(p =>
          `<option value="${p.code}" ${p.code === data.provider_code ? "selected" : ""}>${p.label}</option>`
        ).join("")
      body = fieldDiv("Provider", selectWrap("provider_code", provOpts))
      if (type === "FallbackNode") {
        body += fieldDiv("Max retries",
          `<input type="number" min="1" max="10" value="${data.max_retries ?? 3}"
                  onchange="${rc}.updateNodeField('max_retries', this.value)"
                  style="${inputCss}">`)
      }
    }

    if (type === "ConditionNode") {
      const fieldOpts = ["currency","amount","country","mcc_code","method","risk_score"]
        .map(f => `<option value="${f}" ${f === data.field ? "selected" : ""}>${f}</option>`).join("")
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
                       onchange="${rc}.updateNodeField('value', this.value)"
                       style="${inputCss}">`)
    }

    if (type === "SplitNode") {
      const halfCard = (pctKey, lblKey, pctVal, lblVal, accent, bg) =>
        `<div style="flex:1;border:1.5px solid ${accent}33;border-radius:10px;padding:8px 8px 6px;
                     background:${bg};text-align:center;">
           <div>
             <input type="number" min="1" max="99" value="${pctVal}"
                    onchange="${rc}.updateNodeField('${pctKey}', this.value)"
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

  // ── Selection state (no separate panel) ──────────────────────────────────

  _onNodeSelected(id) {
    this._selectedNodeId = id
  }

  _onNodeUnselected() {
    this._selectedNodeId = null
  }

  updateNodeField(field, value) {
    if (!this._selectedNodeId) return
    const node = this.editor.getNodeFromId(this._selectedNodeId)
    if (!node) return
    const newData = { ...node.data, [field]: value }
    if (field === "provider_code") {
      const p = this.providersValue.find(p => p.code === value)
      if (p) newData.label = p.label
    }
    this.editor.updateNodeDataFromId(this._selectedNodeId, newData)
    const el = this.canvasTarget.querySelector(`#node-${this._selectedNodeId} .drawflow_content_node`)
    if (!el) return
    // Full re-render for select fields (interaction is done); title-only for text/number
    const isSelect = ["provider_code", "field", "operator"].includes(field)
    if (isSelect) {
      el.innerHTML = this._nodeHtml(node.name, this.NODE_TYPES[node.name], newData)
    } else {
      const titleEl = el.querySelector(".rg-node-title")
      if (titleEl) titleEl.innerHTML = this._nodeTitle(node.name, this.NODE_TYPES[node.name], newData)
    }
  }

  deleteSelected() {
    if (!this._selectedNodeId) return
    this.editor.removeNodeId(`node-${this._selectedNodeId}`)
    this._onNodeUnselected()
    this._updateEmptyState()
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  save() {
    const payload = this._toGraphPayload(this.editor.export())
    const name    = this.hasNameInputTarget ? this.nameInputTarget.value.trim() : "Untitled"

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
