import { Controller } from "@hotwired/stimulus"

// Syntax-highlights the text content of a <pre> element as JSON.
// Keys → blue, string values → light blue, numbers → orange,
// booleans → red/green, null → grey. Falls back to plain text if
// the content isn't valid JSON.
export default class extends Controller {
  connect() {
    const raw = this.element.textContent
    try {
      JSON.parse(raw)
      this.element.innerHTML = tokenize(raw)
    } catch {
      // Not valid JSON — leave as plain text.
    }
  }
}

const KEY_COLOR    = "#79c0ff"   // blue   – object keys
const STR_COLOR    = "#a5d6ff"   // sky    – string values
const NUM_COLOR    = "#f0883e"   // orange – numbers
const BOOL_COLOR   = "#ff7b72"   // red    – true / false
const NULL_COLOR   = "#8b949e"   // grey   – null

function escape(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

function span(color, text) {
  return `<span style="color:${color}">${escape(text)}</span>`
}

// Minimal hand-written JSON tokenizer — no regex, handles escapes correctly.
function tokenize(json) {
  let out = ""
  let i = 0
  const len = json.length

  while (i < len) {
    const ch = json[i]

    if (ch === '"') {
      // Read the full quoted string (respecting backslash escapes).
      let str = '"'
      i++
      while (i < len) {
        const c = json[i]
        if (c === "\\") { str += c + json[i + 1]; i += 2; continue }
        str += c
        i++
        if (c === '"') break
      }
      // Peek past whitespace to decide: is this a key (followed by ':')?
      let j = i
      while (j < len && " \t\r\n".includes(json[j])) j++
      const isKey = json[j] === ":"
      out += span(isKey ? KEY_COLOR : STR_COLOR, str)

    } else if (json.startsWith("true", i)) {
      out += span(BOOL_COLOR, "true"); i += 4

    } else if (json.startsWith("false", i)) {
      out += span(BOOL_COLOR, "false"); i += 5

    } else if (json.startsWith("null", i)) {
      out += span(NULL_COLOR, "null"); i += 4

    } else if (ch === "-" || (ch >= "0" && ch <= "9")) {
      let num = ""
      while (i < len && "-+.eE0123456789".includes(json[i])) { num += json[i]; i++ }
      out += span(NUM_COLOR, num)

    } else {
      // Structural characters and whitespace — pass through with escaping.
      out += escape(ch); i++
    }
  }

  return out
}
