import { Controller } from "@hotwired/stimulus"
import Drawflow from "drawflow"

export default class extends Controller {
  static targets = ["configPanel", "panelTitle", "panelBody", "emptyState", "nameInput"]
  static values  = { graph: Object, providers: Array, saveUrl: String, saveMethod: String, csrf: String }

  NODE_TYPES = {
    ProviderNode: {
      label: "Provider",
      color: "#16a34a",
      bg: "rgba(22,163,74,0.08)",
      inputs: 1,
      outputs: 1,
      defaultData: { provider_code: "", label: "Select provider" }
    },
    ConditionNode: {
      label: "Condition",
      color: "#d97706",
      bg: "rgba(217,119,6,0.08)",
      inputs: 1,
      outputs: 2,
      defaultData: { field: "currency", operator: "eq", value: "" }
    },
    SplitNode: {
      label: "Split",
      color: "#3D47F5",
      bg: "rgba(61,71,245,0.08)",
      inputs: 1,
      outputs: 2,
      defaultData: { pct_a: 70, pct_b: 30, label_a: "Primary", label_b: "Secondary" }
    },
    FallbackNode: {
      label: "Fallback",
      color: "#6b7280",
      bg: "rgba(107,114,128,0.08)",
      inputs: 1,
      outputs: 1,
      defaultData: { provider_code: "", label: "Select provider", max_retries: 3 }
    }
  }

  TEMPLATES = {
    simple_failover: {
      name: "Simple failover",
      nodes: [
        { id: 1, type: "ProviderNode", x: 340, y: 180, data: { provider_code: "mtn_momo",     label: "MTN MoMo" } },
        { id: 2, type: "FallbackNode", x: 620, y: 180, data: { provider_code: "telecel_cash", label: "Telecel Cash", max_retries: 3 } }
      ],
      connections: [{ from: 1, fromOutput: 1, to: 2, toInput: 1 }]
    },
    currency_split: {
      name: "Currency split",
      nodes: [
        { id: 1, type: "ConditionNode", x: 200, y: 200, data: { field: "currency", operator: "eq", value: "GHS" } },
        { id: 2, type: "ProviderNode",  x: 480, y: 100, data: { provider_code: "mtn_momo", label: "MTN MoMo" } },
        { id: 3, type: "ProviderNode",  x: 480, y: 300, data: { provider_code: "stripe",   label: "Stripe" } }
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
        { id: 2, type: "ProviderNode",  x: 480, y: 100, data: { provider_code: "stripe",   label: "Stripe (high value)" } },
        { id: 3, type: "ProviderNode",  x: 480, y: 300, data: { provider_code: "mtn_momo", label: "MTN MoMo (standard)" } }
      ],
      connections: [
        { from: 1, fromOutput: 1, to: 2, toInput: 1 },
        { from: 1, fromOutput: 2, to: 3, toInput: 1 }
      ]
    }
  }

  connect() {
    this.editor = new Drawflow(this.element)
    this.editor.reroute = true
    this.editor.start()

    // Expose instance for inline handlers in panel HTML
    this.element.__routingGraph = this

    if (this.graphValue && Object.keys(this.graphValue).length > 0) {
      this._loadGraph(this.graphValue)
    } else {
      this._updateEmptyState()
    }

    this.editor.on("nodeSelected",   (id) => this._onNodeSelected(id))
    this.editor.on("nodeUnselected", ()    => this._onNodeUnselected())
    this.editor.on("nodeMoved",      ()    => this._updateEmptyState())
    this.editor.on("nodeCreated",    ()    => this._updateEmptyState())
    this.editor.on("nodeRemoved",    ()    => this._updateEmptyState())

    this.element.addEventListener("dragover", e => e.preventDefault())
    this.element.addEventListener("drop",     e => this._onDrop(e))
  }

  disconnect() {
    delete this.element.__routingGraph
  }

  // ── Palette drag ─────────────────────────────────────────────────────────

  paletteDragStart(event) {
    this._dragType = event.currentTarget.dataset.nodeType
  }

  _onDrop(event) {
    if (!this._dragType) return
    const rect = this.element.getBoundingClientRect()
    const x = (event.clientX - rect.left - this.editor.canvas_x) / this.editor.zoom
    const y = (event.clientY - rect.top  - this.editor.canvas_y) / this.editor.zoom
    this._addNode(this._dragType, x, y, null)
    this._dragType = null
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
    tpl.nodes.forEach(n => {
      const localId = this._addNode(n.type, n.x, n.y, n.data)
      idMap[n.id] = localId
    })
    tpl.connections.forEach(c => {
      const fromId = idMap[c.from]
      const toId   = idMap[c.to]
      if (!fromId || !toId) return
      try { this.editor.addConnection(fromId, toId, `output_${c.fromOutput}`, `input_${c.toInput}`) } catch(_) {}
    })
    this._updateEmptyState()
  }

  // ── Node rendering ───────────────────────────────────────────────────────

  _addNode(type, x, y, data) {
    const def = this.NODE_TYPES[type]
    if (!def) return null
    const d   = data ? { ...data } : { ...def.defaultData }
    const html = this._nodeHtml(type, def, d)
    return this.editor.addNode(type, def.inputs, def.outputs, x, y, type, d, html)
  }

  _nodeHtml(type, def, data) {
    const badge = `<span style="display:inline-flex;align-items:center;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.08em;color:${def.color};background:${def.bg};padding:2px 8px;border-radius:99px;">${def.label}</span>`

    if (type === "ProviderNode") {
      return `<div style="padding:14px 16px;">${badge}
        <div style="margin-top:10px;font-size:13px;font-weight:600;color:#111827;">${data.label || "Select provider"}</div>
        <div style="font-size:11px;color:#9ca3af;margin-top:2px;">${data.provider_code || "No provider selected"}</div>
      </div>`
    }
    if (type === "FallbackNode") {
      return `<div style="padding:14px 16px;">${badge}
        <div style="margin-top:10px;font-size:13px;font-weight:600;color:#111827;">If fails → ${data.label || "Select provider"}</div>
        <div style="font-size:11px;color:#9ca3af;margin-top:2px;">${data.provider_code || "No provider selected"} · max ${data.max_retries || 3} retries</div>
      </div>`
    }
    if (type === "ConditionNode") {
      const opLabel = { eq:"=", neq:"≠", gt:">", gte:"≥", lt:"<", lte:"≤", in:"in", not_in:"not in" }[data.operator] || data.operator
      return `<div style="padding:14px 16px;">${badge}
        <div style="margin-top:10px;font-size:13px;font-weight:600;color:#111827;">${data.field || "field"} ${opLabel} ${data.value || "…"}</div>
        <div style="display:flex;gap:8px;margin-top:8px;">
          <span style="font-size:10px;background:#f0fdf4;color:#16a34a;padding:2px 7px;border-radius:99px;font-weight:600;">✓ Match</span>
          <span style="font-size:10px;background:#fef3c7;color:#d97706;padding:2px 7px;border-radius:99px;font-weight:600;">✗ No match</span>
        </div>
      </div>`
    }
    if (type === "SplitNode") {
      return `<div style="padding:14px 16px;">${badge}
        <div style="margin-top:10px;display:flex;gap:6px;">
          <span style="font-size:11px;background:#eff0fe;color:#3D47F5;padding:2px 8px;border-radius:99px;font-weight:600;">${data.pct_a || 70}%</span>
          <span style="font-size:11px;background:#f9fafb;color:#6b7280;padding:2px 8px;border-radius:99px;font-weight:600;">${data.pct_b || 30}%</span>
        </div>
      </div>`
    }
    return `<div style="padding:14px 16px;">${badge}</div>`
  }

  // ── Config panel ─────────────────────────────────────────────────────────

  _onNodeSelected(id) {
    const node = this.editor.getNodeFromId(id)
    if (!node) return
    this._selectedNodeId = id
    this.configPanelTarget.classList.remove("hidden")
    this.panelTitleTarget.textContent = (this.NODE_TYPES[node.name]?.label || "Node") + " configuration"
    this.panelBodyTarget.innerHTML = this._panelHtml(node.name, node.data)
  }

  _onNodeUnselected() {
    this.configPanelTarget.classList.add("hidden")
    this._selectedNodeId = null
  }

  closePanel() {
    this._onNodeUnselected()
  }

  _panelHtml(type, data) {
    const providers = this.providersValue

    const providerSelect = (val) => `
      <div style="margin-bottom:12px;">
        <label style="display:block;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.08em;color:#9ca3af;margin-bottom:6px;">Provider</label>
        <select onchange="this.closest('[data-controller]').__routingGraph.updateNodeField('provider_code', this.value)"
                style="width:100%;border:1px solid #e5e7eb;border-radius:10px;background:#f9fafb;padding:8px 12px;font-size:13px;color:#111827;outline:none;">
          <option value="">Select provider…</option>
          ${providers.map(p => `<option value="${p.code}" ${p.code === val ? "selected" : ""}>${p.label} (${p.kind})</option>`).join("")}
        </select>
      </div>`

    const fieldInput = (label, key, val, inputType = "text", extra = "") => `
      <div style="margin-bottom:12px;">
        <label style="display:block;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.08em;color:#9ca3af;margin-bottom:6px;">${label}</label>
        <input type="${inputType}" value="${val ?? ""}" ${extra}
               onchange="this.closest('[data-controller]').__routingGraph.updateNodeField('${key}', this.value)"
               style="width:100%;border:1px solid #e5e7eb;border-radius:10px;background:#f9fafb;padding:8px 12px;font-size:13px;color:#111827;outline:none;box-sizing:border-box;">
      </div>`

    const deleteBtn = `<button onclick="this.closest('[data-controller]').__routingGraph.deleteSelected()"
      style="margin-top:8px;width:100%;padding:7px 12px;border:1px solid #fecaca;border-radius:10px;background:white;color:#dc2626;font-size:12px;font-weight:600;cursor:pointer;">
      Delete node
    </button>`

    if (type === "ProviderNode") {
      return providerSelect(data.provider_code) + fieldInput("Display label", "label", data.label) + deleteBtn
    }

    if (type === "FallbackNode") {
      return providerSelect(data.provider_code) +
             fieldInput("Max retries", "max_retries", data.max_retries, "number", 'min="1" max="10"') +
             deleteBtn
    }

    if (type === "ConditionNode") {
      const fields = ["currency", "amount", "country", "mcc_code", "method", "risk_score"]
        .map(f => `<option value="${f}" ${f === data.field ? "selected" : ""}>${f}</option>`).join("")
      const ops = [["eq","= equals"],["neq","≠ not equals"],["gt","> greater than"],["gte","≥ at least"],["lt","< less than"],["lte","≤ at most"],["in","in list"],["not_in","not in list"]]
        .map(([v, l]) => `<option value="${v}" ${v === data.operator ? "selected" : ""}>${l}</option>`).join("")
      return `
        <div style="margin-bottom:12px;">
          <label style="display:block;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.08em;color:#9ca3af;margin-bottom:6px;">Field</label>
          <select onchange="this.closest('[data-controller]').__routingGraph.updateNodeField('field', this.value)"
                  style="width:100%;border:1px solid #e5e7eb;border-radius:10px;background:#f9fafb;padding:8px 12px;font-size:13px;color:#111827;outline:none;">${fields}</select>
        </div>
        <div style="margin-bottom:12px;">
          <label style="display:block;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.08em;color:#9ca3af;margin-bottom:6px;">Operator</label>
          <select onchange="this.closest('[data-controller]').__routingGraph.updateNodeField('operator', this.value)"
                  style="width:100%;border:1px solid #e5e7eb;border-radius:10px;background:#f9fafb;padding:8px 12px;font-size:13px;color:#111827;outline:none;">${ops}</select>
        </div>
        ${fieldInput("Value", "value", data.value)}
        ${deleteBtn}`
    }

    if (type === "SplitNode") {
      return fieldInput("Path A label", "label_a", data.label_a) +
             fieldInput("Path A %",     "pct_a",   data.pct_a,   "number", 'min="1" max="99"') +
             fieldInput("Path B label", "label_b", data.label_b) +
             fieldInput("Path B %",     "pct_b",   data.pct_b,   "number", 'min="1" max="99"') +
             deleteBtn
    }

    return deleteBtn
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
    const el = this.element.querySelector(`#node-${this._selectedNodeId} .drawflow_content_node`)
    if (el) el.innerHTML = this._nodeHtml(node.name, this.NODE_TYPES[node.name], newData)
    // Re-render panel to keep inputs in sync
    this.panelBodyTarget.innerHTML = this._panelHtml(node.name, newData)
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
      inp.type  = "hidden"
      inp.name  = k
      inp.value = v
      form.appendChild(inp)
    })

    document.body.appendChild(form)
    form.submit()
  }

  // ── Serialization ────────────────────────────────────────────────────────

  _toGraphPayload(drawflowData) {
    const nodes = []
    const edges = []
    const data  = drawflowData.drawflow.Home.data

    Object.entries(data).forEach(([id, node]) => {
      nodes.push({
        id:       `n${id}`,
        type:     node.name,
        position: { x: node.pos_x, y: node.pos_y },
        data:     node.data
      })
      Object.entries(node.outputs || {}).forEach(([outputKey, output]) => {
        const outputIdx = parseInt(outputKey.replace("output_", ""))
        ;(output.connections || []).forEach(conn => {
          edges.push({
            id:           `e_${id}_${conn.node}_${outputIdx}`,
            source:       `n${id}`,
            target:       `n${conn.node}`,
            sourceHandle: outputKey,
            targetHandle: conn.input,
            label:        this._edgeLabel(node.name, node.data, outputIdx)
          })
        })
      })
    })

    return { nodes, edges, schema_version: 1 }
  }

  _edgeLabel(nodeType, data, outputIdx) {
    if (nodeType === "ConditionNode") {
      const op = { eq:"=", neq:"≠", gt:">", gte:"≥", lt:"<", lte:"≤", in:"in", not_in:"not in" }[data.operator] || ""
      return outputIdx === 1 ? `${data.field} ${op} ${data.value}` : "no match"
    }
    if (nodeType === "SplitNode") {
      return outputIdx === 1 ? `${data.pct_a}%` : `${data.pct_b}%`
    }
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
      const fromId = idMap[e.source]
      const toId   = idMap[e.target]
      if (!fromId || !toId) return
      const outIdx = parseInt((e.sourceHandle || "output_1").replace("output_", ""))
      const inIdx  = parseInt((e.targetHandle || "input_1").replace("input_", ""))
      try { this.editor.addConnection(fromId, toId, `output_${outIdx}`, `input_${inIdx}`) } catch(_) {}
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
