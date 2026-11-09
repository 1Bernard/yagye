import { Controller } from "@hotwired/stimulus"

// Applies syntax highlighting to a <pre> element.
// data-code-highlight-lang-value must be one of: node, python, php, ruby.
// Colors match the GitHub-dark palette used in the hand-crafted curl block.

const COMMENT  = "#8b949e"
const KEYWORD  = "#ff7b72"
const STRING   = "#a5d6ff"
const NUMBER   = "#f0883e"
const VAR      = "#ffa657" // PHP $var / Ruby @ivar
const HASH_KEY = "#79c0ff" // Ruby symbol keys and JS object keys (word:)

const LANG_KEYWORDS = {
  node: new Set([
    "const", "let", "var", "function", "return", "async", "await",
    "if", "else", "for", "of", "in", "new", "throw", "try", "catch",
    "true", "false", "null", "undefined", "import", "from", "export", "class"
  ]),
  python: new Set([
    "import", "from", "def", "return", "if", "else", "elif", "for",
    "in", "True", "False", "None", "not", "and", "or", "with", "as",
    "class", "try", "except", "finally", "raise", "lambda"
  ]),
  php: new Set([
    "require", "use", "new", "if", "else", "foreach", "return",
    "true", "false", "null", "function", "class", "echo", "header", "throw"
  ]),
  ruby: new Set([
    "require", "def", "end", "do", "if", "else", "elsif", "return",
    "true", "false", "nil", "class", "module", "begin", "rescue", "then"
  ])
}

function esc(s) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

function span(color, text) {
  return `<span style="color:${color}">${esc(text)}</span>`
}

function highlight(code, lang) {
  const kw = LANG_KEYWORDS[lang] || new Set()
  let out = ""
  let i = 0
  const n = code.length

  while (i < n) {
    const ch = code[i]

    // Line comment: # (Python / Ruby / shell) or // (JS / PHP)
    if (ch === "#" || (ch === "/" && code[i + 1] === "/")) {
      const eol = code.indexOf("\n", i)
      const end = eol === -1 ? n : eol
      out += span(COMMENT, code.slice(i, end))
      i = end
      continue
    }

    // Python string prefixes: f, r, b, u before a quote
    const nextCh = code[i + 1] || ""
    const isPrefix = (ch === "f" || ch === "r" || ch === "b" || ch === "u") &&
                     (nextCh === '"' || nextCh === "'")
    if (isPrefix || ch === '"' || ch === "'" || ch === "`") {
      const start = i
      if (isPrefix) i++
      const q = code[i]
      let str = code.slice(start, i + 1)
      i++
      while (i < n) {
        if (code[i] === "\\" && i + 1 < n) { str += code[i] + code[i + 1]; i += 2; continue }
        str += code[i]
        if (code[i] === q) { i++; break }
        i++
      }
      out += span(STRING, str)
      continue
    }

    // PHP $variable or Ruby @ivar / @@cvar
    if ((ch === "$" || ch === "@") && /[a-zA-Z_]/.test(code[i + 1] || "")) {
      let word = ch; i++
      if (ch === "@" && code[i] === "@") { word += "@"; i++ }
      while (i < n && /[a-zA-Z0-9_]/.test(code[i])) word += code[i++]
      out += span(VAR, word)
      continue
    }

    // Integer / float
    if (/[0-9]/.test(ch)) {
      let num = ""
      while (i < n && /[0-9._]/.test(code[i])) num += code[i++]
      out += span(NUMBER, num)
      continue
    }

    // Identifier or keyword
    if (/[a-zA-Z_]/.test(ch)) {
      let word = ""
      while (i < n && /[a-zA-Z0-9_]/.test(code[i])) word += code[i++]
      // word: but not :: — Ruby symbol key or JS/PHP object key
      const isKey = code[i] === ":" && code[i + 1] !== ":"
      if (isKey)         out += span(HASH_KEY, word)
      else if (kw.has(word)) out += span(KEYWORD, word)
      else               out += esc(word)
      continue
    }

    out += esc(ch)
    i++
  }

  return out
}

export default class extends Controller {
  static values = { lang: String }

  connect() {
    if (this.element.dataset.highlighted) return
    this.element.innerHTML = highlight(this.element.textContent, this.langValue)
    this.element.dataset.highlighted = "1"
  }
}
