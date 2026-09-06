import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    registerChallengeUrl: String,
    registerUrl:          String,
    csrfToken:            String
  }

  async register() {
    try {
      const opts = await this._jsonPost(this.registerChallengeUrlValue)
      const cred = await navigator.credentials.create({
        publicKey: {
          ...opts,
          challenge:          this._decode(opts.challenge),
          user:             { ...opts.user, id: this._decode(opts.user.id) },
          excludeCredentials: (opts.excludeCredentials || []).map(c => ({
            ...c, id: this._decode(c.id)
          }))
        }
      })
      await this._jsonPost(this.registerUrlValue, { credential: this._serializeCreate(cred) })
      window.location.reload()
    } catch (e) {
      if (e.name !== "NotAllowedError") console.error("Passkey registration error:", e)
    }
  }

  _decode(base64url) {
    const base64 = base64url.replace(/-/g, "+").replace(/_/g, "/")
    const binary = atob(base64)
    return Uint8Array.from(binary, c => c.charCodeAt(0)).buffer
  }

  _encode(buffer) {
    const bytes = new Uint8Array(buffer)
    let binary = ""
    bytes.forEach(b => (binary += String.fromCharCode(b)))
    return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "")
  }

  _serializeCreate(cred) {
    return {
      type:   cred.type,
      id:     cred.id,
      rawId:  this._encode(cred.rawId),
      response: {
        clientDataJSON:    this._encode(cred.response.clientDataJSON),
        attestationObject: this._encode(cred.response.attestationObject)
      }
    }
  }

  async _jsonPost(url, body = {}) {
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token":  this.csrfTokenValue
      },
      body: JSON.stringify(body)
    })
    if (!res.ok) {
      const err = await res.json().catch(() => ({}))
      throw new Error(err.error || `HTTP ${res.status}`)
    }
    return res.json()
  }
}
