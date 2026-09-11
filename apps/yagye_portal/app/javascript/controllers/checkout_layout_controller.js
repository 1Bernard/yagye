import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["methodList", "previewList", "emptyPreview", "saveBtn", "savedBadge", "checkoutUrl", "logoUrlInput", "previewLogoImg"]
  static values  = {
    saveUrl:  String,
    csrf:     String,
    layout:   { type: Object, default: {} }
  }

  connect() {
    this._dirty = false
    this._drag  = null
    this._setupDrag()
    this._syncPreview()
  }

  disconnect() {
    this._cancelDrag()
  }

  // ── Pointer-based drag-and-drop (no external library) ─────────────────────

  _setupDrag() {
    this.methodListTarget.addEventListener("pointerdown", this._onPointerDown.bind(this))
  }

  _tiles() {
    return [...this.methodListTarget.querySelectorAll("[data-method-id]")]
  }

  _onPointerDown(e) {
    // Skip interactive controls
    if (e.target.closest("input, label, button, a, select")) return
    const tile = e.target.closest("[data-method-id]")
    if (!tile) return

    e.preventDefault()
    tile.setPointerCapture(e.pointerId)

    const rect   = tile.getBoundingClientRect()
    const clone  = tile.cloneNode(true)

    // Style the floating clone
    Object.assign(clone.style, {
      position:      "fixed",
      top:           rect.top + "px",
      left:          rect.left + "px",
      width:         rect.width + "px",
      pointerEvents: "none",
      zIndex:        "9999",
      opacity:       "0.92",
      boxShadow:     "0 12px 32px rgba(0,0,0,0.15), 0 2px 8px rgba(0,0,0,0.08)",
      borderRadius:  "12px",
      transform:     "rotate(1.5deg) scale(1.02)",
      transition:    "box-shadow 0.1s",
      background:    "white",
    })
    document.body.appendChild(clone)

    // Drop indicator line
    const indicator = document.createElement("div")
    Object.assign(indicator.style, {
      position:     "absolute",
      left:         "8px",
      right:        "8px",
      height:       "2px",
      background:   "#3D47F5",
      borderRadius: "2px",
      pointerEvents:"none",
      zIndex:       "9998",
      display:      "none",
    })
    this.methodListTarget.style.position = "relative"
    this.methodListTarget.appendChild(indicator)

    this._drag = {
      tile,
      clone,
      indicator,
      offsetY:   e.clientY - rect.top,
      dropIndex: null,
    }

    tile.style.opacity = "0.3"

    tile.addEventListener("pointermove", this._onPointerMove.bind(this))
    tile.addEventListener("pointerup",   this._onPointerUp.bind(this))
    tile.addEventListener("pointercancel", this._cancelDrag.bind(this))
  }

  _onPointerMove(e) {
    if (!this._drag) return
    const { clone, indicator, tile, offsetY } = this._drag

    const y = e.clientY - offsetY
    clone.style.top = y + "px"

    // Find insert position by comparing cursor Y to tile midpoints
    const tiles = this._tiles().filter(t => t !== tile)
    let dropIndex = tiles.length
    for (let i = 0; i < tiles.length; i++) {
      const mid = tiles[i].getBoundingClientRect().top + tiles[i].offsetHeight / 2
      if (e.clientY < mid) { dropIndex = i; break }
    }
    this._drag.dropIndex = dropIndex

    // Position the indicator line
    if (dropIndex < tiles.length) {
      const refRect = tiles[dropIndex].getBoundingClientRect()
      const listRect = this.methodListTarget.getBoundingClientRect()
      indicator.style.top    = (refRect.top - listRect.top - 3) + "px"
      indicator.style.display = "block"
    } else if (tiles.length > 0) {
      const lastRect  = tiles[tiles.length - 1].getBoundingClientRect()
      const listRect  = this.methodListTarget.getBoundingClientRect()
      indicator.style.top    = (lastRect.bottom - listRect.top + 1) + "px"
      indicator.style.display = "block"
    }
  }

  _onPointerUp(e) {
    if (!this._drag) return
    const { tile, dropIndex } = this._drag

    // Reorder DOM
    const list  = this.methodListTarget
    const tiles = this._tiles().filter(t => t !== tile)
    if (dropIndex !== null) {
      if (dropIndex >= tiles.length) {
        list.appendChild(tile)
      } else {
        list.insertBefore(tile, tiles[dropIndex])
      }
      this._syncPreview()
      this._markDirty()
    }

    this._cancelDrag()
  }

  // ── Live preview sync ──────────────────────────────────────────────────────

  _syncPreview() {
    if (!this.hasPreviewListTarget) return
    const preview = this.previewListTarget
    const order   = this._tiles().map(t => t.dataset.methodId)

    order.forEach(id => {
      const tile = preview.querySelector(`[data-preview-method="${id}"]`)
      if (!tile) return
      // Move to end in new order (always visible, dimmed when inactive)
      tile.hidden = false
      preview.appendChild(tile)
      const editorTile = this.methodListTarget.querySelector(`[data-method-id="${id}"]`)
      const active     = editorTile?.dataset.visible === "true"
      tile.style.opacity = active ? "1" : "0.35"
      tile.style.filter  = active ? "" : "grayscale(0.5)"
    })
  }

  _cancelDrag() {
    if (!this._drag) return
    const { tile, clone, indicator } = this._drag
    tile.style.opacity = ""
    clone.remove()
    indicator.remove()
    this._drag = null
  }

  updateLogo(event) {
    const url = event.currentTarget.value.trim()
    if (!this.hasPreviewLogoImgTarget) return
    const el = this.previewLogoImgTarget
    if (url) {
      if (el.tagName === "IMG") {
        el.src = url
      } else {
        // Swap icon div for an img
        const img = document.createElement("img")
        img.src = url
        img.alt = "Logo"
        img.className = "w-7 h-7 rounded-lg object-cover flex-shrink-0 border border-gray-100"
        img.dataset.checkoutLayoutTarget = "previewLogoImg"
        el.replaceWith(img)
      }
    } else {
      // Restore icon bubble when URL cleared
      if (el.tagName === "IMG") {
        const div = document.createElement("div")
        div.className = "w-7 h-7 rounded-lg bg-[#3D47F5] flex items-center justify-center"
        div.dataset.checkoutLayoutTarget = "previewLogoImg"
        div.innerHTML = `<span class="flex w-[13px] h-[13px] text-white"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg></span>`
        el.replaceWith(div)
      }
    }
    this._markDirty()
  }

  navigateLink(event) {
    window.location = `/payment-links/${event.target.value}/layout`
  }

  toggleMethod(event) {
    const toggle  = event.currentTarget
    const tile    = toggle.closest("[data-method-id]")
    const visible = toggle.checked

    tile.dataset.visible = visible ? "true" : "false"
    tile.classList.toggle("opacity-60", !visible)
    this._syncPreview()
    this._markDirty()
  }

  toggleRail(event) {
    const railRow  = event.currentTarget.closest("[data-rail-id]")
    const tile     = event.currentTarget.closest("[data-method-id]")
    if (!railRow || !tile) { this._markDirty(); return }

    const methodId = tile.dataset.methodId
    const railId   = railRow.dataset.railId
    const visible  = event.currentTarget.checked

    // Sync the preview chip
    if (this.hasPreviewListTarget) {
      const railsContainer = this.previewListTarget.querySelector(`[data-preview-rails-for="${methodId}"]`)
      const chip = railsContainer?.querySelector(`[data-preview-rail="${railId}"]`)
      if (chip) chip.hidden = !visible
    }

    this._markDirty()
  }

  setTileStyle(event) {
    const tile     = event.currentTarget.closest("[data-method-id]")
    const expanded = event.currentTarget.value === "expanded"

    if (tile && this.hasPreviewListTarget) {
      const methodId      = tile.dataset.methodId
      const railsContainer = this.previewListTarget.querySelector(`[data-preview-rails-for="${methodId}"]`)
      if (railsContainer) railsContainer.classList.toggle("hidden", !expanded)
    }

    this._markDirty()
  }

  save() {
    const layout = this._collectLayout()
    this.saveBtnTarget.disabled = true
    this.saveBtnTarget.textContent = "Saving…"

    fetch(this.saveUrlValue, {
      method:  "PATCH",
      headers: {
        "Content-Type":  "application/json",
        "X-CSRF-Token":  this.csrfValue
      },
      body: JSON.stringify({ layout })
    })
      .then(r => r.json())
      .then(data => {
        if (data.ok) {
          this._dirty = false
          this.saveBtnTarget.textContent = "Save layout"
          this.saveBtnTarget.disabled = false
          if (this.hasSavedBadgeTarget) {
            this.savedBadgeTarget.hidden = false
            setTimeout(() => { this.savedBadgeTarget.hidden = true }, 3000)
          }
          if (this.hasCheckoutUrlTarget && data.checkout_url) {
            this.checkoutUrlTarget.textContent = data.checkout_url
            this.checkoutUrlTarget.href        = data.checkout_url
          }
        } else {
          this._handleError(data.error)
        }
      })
      .catch(() => this._handleError("Network error — please try again."))
  }

  _handleError(msg) {
    this.saveBtnTarget.textContent = "Save layout"
    this.saveBtnTarget.disabled = false
    alert(msg || "Failed to save layout.")
  }

  _markDirty() {
    this._dirty = true
    this.saveBtnTarget.disabled = false
  }

  _collectLayout() {
    const methods = []

    this.methodListTarget.querySelectorAll("[data-method-id]").forEach(tile => {
      const methodId  = tile.dataset.methodId
      const visible   = tile.querySelector("[data-role='method-toggle']")?.checked ?? true
      const tileStyle = tile.querySelector("[data-role='tile-style']:checked")?.value ?? "compact"

      const rails = []
      tile.querySelectorAll("[data-rail-id]").forEach(railRow => {
        rails.push({
          id:      railRow.dataset.railId,
          label:   railRow.dataset.railLabel,
          visible: railRow.querySelector("[data-role='rail-toggle']")?.checked ?? true
        })
      })

      methods.push({ id: methodId, label: tile.dataset.methodLabel, visible, tile_style: tileStyle, rails })
    })

    const logo_url = this.hasLogoUrlInputTarget ? this.logoUrlInputTarget.value.trim() : ""
    return { methods, ...(logo_url ? { logo_url } : {}) }
  }
}
