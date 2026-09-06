import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    challengeUrl: String,
    authUrl:      String,
    csrfToken:    String
  }

  async authenticate() {
    try {
      const opts = await this._jsonPost(this.challengeUrlValue)
      const assertion = await navigator.credentials.get({
        publicKey: {
          ...opts,
          challenge:        this._decode(opts.challenge),
          allowCredentials: (opts.allowCredentials || []).map(c => ({
            ...c, id: this._decode(c.id)
          }))
        }
      })
      this._submitForm(this.authUrlValue, this._serializeGet(assertion))
    } catch (e) {
      if (e.name !== "NotAllowedError") {
        console.error("Passkey auth error:", e)
        alert(e.message || "Passkey authentication failed. Please try again.")
      }
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

  _serializeGet(assertion) {
    return {
      type:   assertion.type,
      id:     assertion.id,
      rawId:  this._encode(assertion.rawId),
      response: {
        clientDataJSON:    this._encode(assertion.response.clientDataJSON),
        authenticatorData: this._encode(assertion.response.authenticatorData),
        signature:         this._encode(assertion.response.signature),
        userHandle:        assertion.response.userHandle
                             ? this._encode(assertion.response.userHandle)
                             : null
      }
    }
  }

  _submitForm(action, data) {
    const form = document.createElement("form")
    form.method = "post"
    form.action = action
    form.setAttribute("data-turbo", "false")
    const add = (name, value) => {
      const i = document.createElement("input")
      i.type = "hidden"; i.name = name; i.value = value
      form.appendChild(i)
    }
    add("authenticity_token", this.csrfTokenValue)
    add("credential", JSON.stringify(data))
    document.body.appendChild(form)
    form.submit()
  }

  async _jsonPost(url, body = {}) {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfTokenValue },
      body: JSON.stringify(body)
    })
    if (!res.ok) {
      const err = await res.json().catch(() => ({}))
      throw new Error(err.error || `HTTP ${res.status}`)
    }
    return res.json()
  }
}
