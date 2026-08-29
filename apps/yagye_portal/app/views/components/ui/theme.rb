# frozen_string_literal: true

# Single source of truth for every Tailwind string in the portal.
# Rules:
#   1. All colour/surface/typography tokens MUST come from this module.
#   2. Layout utilities (flex, gap, px, sizing, position) are exempt — inline is fine.
#   3. Status colours go through Theme.status_classes(status_string).
#   4. Tailwind JIT must scan app/components/**/*.rb for class detection.
module UI
  module Theme
    BRAND = "#3D47F5"

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # TYPE SCALE — single source of truth for hierarchy.
    # Rule: every visible text element MUST use one of these levels.
    # Never define ad-hoc font-size/color/weight outside this scale.
    #
    # Hierarchy (most → least prominent):
    #   DISPLAY → TITLE → HEADING → BODY → CAPTION → LABEL → MICRO
    #
    # Color ladder (high → low contrast on white):
    #   INK (#111827, 15:1) → BODY_TEXT (#374151, 9:1) → PROSE_TEXT (#4B5563, 7:1)
    #   → MUTED_TEXT (#6B7280, 4.7:1 — minimum for readable text)
    #   → SUBTLE_TEXT (#9CA3AF, 2.9:1 — decorative / placeholders only)
    #   → FAINT_TEXT (#D1D5DB — icons, separators, never body text)
    #
    # Surface / border:
    #   SURFACE (#F9FAFB) · BORDER (#F3F4F6) · BORDER_MED (#E5E7EB)
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    # ── Color tokens ──────────────────────────────────────────────────────────
    INK         = "#111827"   # Titles, key data, primary text
    BODY_TEXT   = "#374151"   # Secondary text, subtitles, important body
    PROSE_TEXT  = "#4B5563"   # Body text, descriptions, paragraphs
    MUTED_TEXT  = "#6B7280"   # Labels, timestamps, captions (min for readability)
    SUBTLE_TEXT = "#9CA3AF"   # Decorative only — placeholders, resting icons
    FAINT_TEXT  = "#D1D5DB"   # Separators, faint icons — never body text
    SURFACE     = "#F9FAFB"   # Card backgrounds, hover fills
    BORDER      = "#F3F4F6"   # Default border / divider
    BORDER_MED  = "#E5E7EB"   # Stronger border for interactive elements

    # ── Type scale (inline-style fragments — paste into style: strings) ───────
    # DISPLAY  — page/breadcrumb title, stat values, hero numbers
    TYPE_DISPLAY = "font-size:16px;font-weight:700;color:#{INK};letter-spacing:-0.025em;line-height:1.1"
    # TITLE    — card headers, section names, modal headings
    TYPE_TITLE   = "font-size:14px;font-weight:600;color:#{INK};line-height:1.2"
    # HEADING  — sub-section labels, table column titles (uppercase)
    TYPE_HEADING = "font-size:10.5px;font-weight:700;color:#{MUTED_TEXT};text-transform:uppercase;letter-spacing:0.09em;line-height:1"
    # BODY     — standard body text, cell values, descriptions
    TYPE_BODY    = "font-size:13px;font-weight:400;color:#{PROSE_TEXT};line-height:1.5"
    # BODY_MD  — slightly heavier body for key values, names
    TYPE_BODY_MD = "font-size:13px;font-weight:500;color:#{BODY_TEXT};line-height:1.5"
    # CAPTION  — small supporting text, timestamps, metadata
    TYPE_CAPTION = "font-size:11.5px;font-weight:400;color:#{MUTED_TEXT};line-height:1.4"
    # LABEL    — badge labels, status text inside pill badges
    TYPE_LABEL   = "font-size:12px;font-weight:500;color:#{MUTED_TEXT}"
    # MICRO    — uppercase section labels, keyboard shortcut hints
    TYPE_MICRO   = "font-size:10px;font-weight:700;color:#{SUBTLE_TEXT};text-transform:uppercase;letter-spacing:0.1em"
    # MONO     — transaction references, codes, API keys
    TYPE_MONO    = "font-family:ui-monospace,monospace;font-size:12px;font-weight:500;color:#{BODY_TEXT}"
    # NUM      — append to any type level for financial figures
    TYPE_NUM     = "font-variant-numeric:tabular-nums;font-feature-settings:'tnum'"

    # ── Surfaces ───────────────────────────────────────────────────────────
    CANVAS_BG     = "bg-gray-50 min-h-screen text-gray-900 antialiased"
    SURFACE_CARD  = "bg-white border border-gray-100 rounded-2xl shadow-sm"
    # Legacy alias — kept for existing StatCard/layout components
    CARD          = "bg-white rounded-xl border border-gray-100 shadow-sm"

    # ── Typography ─────────────────────────────────────────────────────────
    TEXT_H1       = "text-[28px] font-bold tracking-tight text-gray-900"
    TEXT_H2       = "text-lg font-semibold text-gray-900"
    TEXT_BODY     = "text-sm text-gray-600"
    TEXT_LABEL    = "text-[10px] font-semibold text-gray-500 uppercase tracking-[0.18em]"
    TEXT_MONO     = "font-mono text-sm text-gray-700"
    TEXT_MUTED    = "text-xs text-gray-400"
    TEXT_VALUE    = "text-3xl font-bold tracking-tight text-gray-900"

    # Legacy aliases used by existing components
    PAGE_TITLE    = "text-lg font-semibold text-gray-900"
    PAGE_SUBTITLE = "text-sm text-gray-500"
    SECTION_TITLE = "text-sm font-semibold text-gray-700"
    LABEL         = "text-xs font-medium text-gray-500 uppercase tracking-wide"
    MUTED         = "text-sm text-gray-500"
    BODY          = "text-sm text-gray-700"
    HEADING       = "font-semibold text-gray-900"
    AUTH_TITLE    = "text-xl font-semibold text-gray-900"
    AUTH_TITLE_LG = "text-2xl font-bold text-gray-900 tracking-tight"
    FORM_LABEL    = "block text-sm font-medium text-gray-700"
    FORM_HINT     = "text-xs text-gray-500"
    FORM_MUTED    = "text-xs text-gray-400"

    # ── Links ──────────────────────────────────────────────────────────────
    LINK_PRIMARY  = "font-medium text-blue-600 hover:text-blue-700 transition-colors"
    LINK_MUTED    = "text-gray-400 hover:text-gray-600 transition-colors"

    # ── Buttons ────────────────────────────────────────────────────────────
    BTN_PRIMARY   = "bg-[#3D47F5] hover:opacity-90 text-white font-semibold rounded-xl " \
                    "text-sm px-5 py-2.5 transition-opacity inline-flex items-center gap-2 " \
                    "disabled:opacity-50 disabled:cursor-not-allowed"
    BTN_SECONDARY = "bg-white hover:border-gray-400 text-gray-700 border border-gray-200 " \
                    "font-medium rounded-xl text-sm px-5 py-2.5 transition-colors " \
                    "inline-flex items-center gap-2"
    BTN_DANGER    = "bg-white hover:bg-red-50 text-red-600 border border-red-200 " \
                    "font-medium rounded-xl text-sm px-5 py-2.5 transition-colors " \
                    "inline-flex items-center gap-2"
    BTN_GHOST     = "text-gray-500 hover:text-gray-900 hover:bg-gray-100 font-medium " \
                    "rounded-xl text-sm px-4 py-2 transition-colors inline-flex items-center gap-2"
    BTN_ICON      = "w-9 h-9 rounded-lg grid place-items-center text-gray-400 " \
                    "hover:text-gray-700 hover:bg-gray-100 transition-colors"

    # Legacy aliases used by existing sign-in form / layout components
    BUTTON_PRIMARY   = "inline-flex items-center gap-2 rounded-lg px-4 py-2 text-sm " \
                       "font-medium bg-[#3D47F5] text-white hover:opacity-90 transition-opacity"
    BUTTON_BRAND     = "inline-flex items-center justify-center rounded-xl px-4 py-2.5 text-sm " \
                       "font-semibold text-white transition-opacity hover:opacity-90 shadow-sm"
    BUTTON_SECONDARY = "inline-flex items-center gap-2 rounded-lg border border-gray-200 " \
                       "px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 transition-colors"
    ICON_BUTTON      = "rounded-lg text-gray-400 hover:text-gray-600 hover:bg-gray-50 transition-colors"
    CHECKBOX         = "h-4 w-4 rounded border-gray-300 text-blue-600 focus:ring-blue-500"

    # ── Form controls ──────────────────────────────────────────────────────
    INPUT_FIELD   = "w-full rounded-xl border border-gray-200 bg-gray-50 px-4 py-3 text-sm " \
                    "text-gray-900 placeholder:text-gray-400 focus:bg-white focus:border-blue-400 " \
                    "focus:ring-2 focus:ring-blue-500/10 focus:outline-none transition-all"
    SELECT_FIELD  = "w-full rounded-xl border border-gray-200 bg-gray-50 px-4 py-3 text-sm " \
                    "text-gray-900 focus:bg-white focus:border-blue-400 focus:ring-2 " \
                    "focus:ring-blue-500/10 focus:outline-none transition-all"
    DATE_FIELD    = "rounded-xl border border-gray-200 bg-gray-50 px-3 py-2.5 text-sm " \
                    "focus:bg-white focus:border-blue-400 focus:ring-2 " \
                    "focus:ring-blue-500/10 focus:outline-none transition-all"
    TEXTAREA_FIELD = "w-full rounded-xl border border-gray-200 bg-gray-50 px-4 py-3 text-sm " \
                     "text-gray-900 placeholder:text-gray-400 focus:bg-white focus:border-blue-400 " \
                     "focus:ring-2 focus:ring-blue-500/10 focus:outline-none transition-all resize-none"
    CHECKBOX_INPUT = "h-4 w-4 rounded border-gray-300 text-blue-600 focus:ring-blue-500 " \
                     "accent-blue-600"

    # Legacy aliases
    INPUT        = "w-full rounded-lg border border-gray-200 px-3 py-2 text-sm " \
                   "text-gray-900 placeholder:text-gray-400 " \
                   "focus:outline-none focus:ring-2 focus:ring-blue-400"
    SEARCH_INPUT = "rounded-lg border border-gray-200 text-sm text-gray-900 " \
                   "placeholder:text-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-400"

    # ── Badges ─────────────────────────────────────────────────────────────
    BADGE_SUCCESS = "bg-green-50 text-green-700 text-xs px-3 py-1 rounded-full font-semibold " \
                    "inline-flex items-center gap-1.5"
    BADGE_PENDING = "bg-violet-50 text-violet-700 text-xs px-3 py-1 rounded-full font-semibold " \
                    "inline-flex items-center gap-1.5"
    BADGE_FAILED  = "bg-red-50 text-red-600 text-xs px-3 py-1 rounded-full font-semibold " \
                    "inline-flex items-center gap-1.5"
    BADGE_WARNING = "bg-amber-50 text-amber-700 text-xs px-3 py-1 rounded-full font-semibold " \
                    "inline-flex items-center gap-1.5"
    BADGE_INFO    = "bg-blue-50 text-blue-700 text-xs px-3 py-1 rounded-full font-semibold " \
                    "inline-flex items-center gap-1.5"
    BADGE_NEUTRAL = "bg-gray-100 text-gray-500 text-xs px-3 py-1 rounded-full font-semibold " \
                    "inline-flex items-center gap-1.5"

    # ── Toast / Flash ──────────────────────────────────────────────────────
    TOAST_STACK = "fixed top-5 right-5 z-[90] flex flex-col items-end pointer-events-none"
    # Layout / animation classes only — colors and shadow use inline styles in UI::Flash
    # so Tailwind scanning can't break them.
    TOAST_BASE  = "pointer-events-auto relative overflow-hidden flex items-start gap-3 " \
                  "rounded-2xl transition-[opacity,transform] duration-300 ease-out"
    # Legacy aliases kept for backward compat.
    TOAST       = TOAST_BASE
    TOAST_ALERT = TOAST_BASE

    FLASH_NOTICE = "bg-green-50 border border-green-200 text-green-800 rounded-xl p-4 text-sm mb-5"
    FLASH_ALERT  = "bg-red-50 border border-red-200 text-red-700 rounded-xl p-4 text-sm mb-5"

    # ── Tables ─────────────────────────────────────────────────────────────
    TABLE_HEADER = "border-b border-gray-100"
    TABLE_ROW    = "border-b border-gray-50 hover:bg-gray-50 transition-colors cursor-pointer"
    TABLE_CELL   = "px-3.5 py-3 text-sm text-gray-700 first:pl-5"
    TABLE_TH     = "px-3.5 py-2.5 text-left text-[10px] font-semibold uppercase tracking-[0.16em] " \
                   "text-gray-400 whitespace-nowrap first:pl-5"
    TABLE_CARD   = "bg-white border border-gray-100 rounded-2xl overflow-hidden"

    # Legacy table aliases
    TH = "text-xs font-medium text-gray-500 px-4 py-3 text-left select-none"
    TD = "text-sm text-gray-800 px-4 py-3"

    # ── Pagination ─────────────────────────────────────────────────────────
    PAGER              = "flex items-center gap-1"
    PAGER_BTN          = "w-8 h-8 rounded-lg grid place-items-center text-gray-500 " \
                         "hover:border hover:border-gray-200 transition-colors"
    PAGER_BTN_ON       = "w-8 h-8 rounded-lg grid place-items-center bg-[#3D47F5] " \
                         "text-white font-semibold"
    PAGER_GAP          = "w-8 h-8 grid place-items-center text-gray-400"
    PAGINATION_STANDALONE = "flex items-center justify-between mt-4 text-[12.5px] text-gray-400"
    PAGINATION_TFOOT   = "flex items-center justify-between px-6 py-4 border-t border-gray-100 " \
                         "text-[12.5px] text-gray-400"

    # ── Dropdown ───────────────────────────────────────────────────────────
    DROPDOWN_MENU      = "absolute z-40 min-w-[200px] bg-white border border-gray-100 rounded-xl " \
                         "shadow-lg p-1.5 opacity-0 -translate-y-1 scale-[0.98] pointer-events-none " \
                         "transition-[opacity,transform] duration-150"
    DROPDOWN_ITEM      = "flex items-center gap-2.5 w-full px-3 py-2.5 rounded-lg text-[13px] " \
                         "text-gray-500 hover:bg-gray-50 hover:text-gray-900 transition-colors text-left"
    DROPDOWN_ITEM_DANGER = "flex items-center gap-2.5 w-full px-3 py-2.5 rounded-lg " \
                           "text-[13px] text-red-600 hover:bg-red-50 transition-colors text-left"
    DROPDOWN_SEP       = "h-px bg-gray-100 my-1.5 mx-2"
    DROPDOWN_TITLE     = "px-3 pt-2 pb-1.5 text-[10px] font-semibold tracking-[0.16em] uppercase text-gray-400"

    # ── Tabs ───────────────────────────────────────────────────────────────
    TAB        = "pb-3 text-[13px] font-medium text-gray-400 border-b-[1.5px] border-transparent " \
                 "hover:text-gray-900 transition-colors whitespace-nowrap -mb-px cursor-pointer"
    TAB_ON     = "pb-3 text-[13px] font-medium text-gray-900 border-b-[1.5px] border-[#3D47F5] " \
                 "transition-colors whitespace-nowrap -mb-px cursor-pointer"
    TAB_COUNT  = "text-[11.5px] text-gray-400 ml-1.5"
    TABS_BAR   = "flex gap-6 border-b border-gray-100 mb-6"

    # ── Avatar ─────────────────────────────────────────────────────────────
    AVATAR     = "rounded-full bg-blue-50 text-blue-700 grid place-items-center font-semibold shrink-0"

    # Legacy icon/avatar teal tints (kept for stat_card.rb)
    ICON_BG_TEAL = "bg-blue-50 text-blue-600"
    LOGO_ICON    = "bg-[#3D47F5] text-white"

    # ── Sidebar & Nav ──────────────────────────────────────────────────────
    # Width (240px/64px), overflow-x, and transition are in application.css (.sidebar-wrapper)
    SIDEBAR       = "sidebar-wrapper shrink-0 bg-white border-r border-gray-100 flex flex-col h-full"
    SIDEBAR_LABEL = "text-[10px] text-gray-400 font-semibold uppercase tracking-[0.18em] " \
                    "px-2 pt-4 pb-2"
    TOPBAR        = "bg-white border-b border-gray-100"

    NAV_ITEM      = "flex items-center gap-3 px-2.5 py-2 rounded-xl text-[13.5px] font-medium " \
                    "text-gray-500 hover:text-gray-900 hover:bg-gray-50 transition-colors"
    NAV_ITEM_ON   = "relative flex items-center gap-3 px-2.5 py-2 rounded-xl text-[13.5px] " \
                    "font-semibold text-gray-900 bg-blue-50"
    NAV_ACCENT_BAR = "absolute left-[-16px] top-1/2 -translate-y-1/2 w-0.5 h-4 bg-[#3D47F5]"
    NAV_ICON_ON   = "text-blue-600"
    NAV_ICON_OFF  = "text-gray-400"

    # ── Icons ──────────────────────────────────────────────────────────────
    ICON_NAV = "w-4 h-4"
    ICON_SM  = "w-[13px] h-[13px]"

    # ── Drawer ─────────────────────────────────────────────────────────────
    DRAWER_OVERLAY = "fixed inset-0 bg-gray-900/30 z-50 opacity-0 pointer-events-none " \
                     "transition-opacity duration-300"
    DRAWER_PANEL   = "fixed top-0 right-0 bottom-0 w-full sm:w-[min(640px,100vw)] bg-white " \
                     "border-l border-gray-100 z-[60] translate-x-full overflow-y-auto " \
                     "transition-transform duration-300 ease-out"
    DRAWER_HEAD    = "sticky top-0 z-10 flex items-center justify-between bg-white/90 " \
                     "backdrop-blur border-b border-gray-100 px-7 py-4"

    # ── Modal ──────────────────────────────────────────────────────────────
    MODAL_OVERLAY  = "fixed inset-0 z-[70] grid place-items-center p-5 bg-gray-900/30 " \
                     "opacity-0 pointer-events-none transition-opacity duration-200"
    MODAL_PANEL    = "w-full max-w-2xl bg-white border border-gray-100 rounded-2xl " \
                     "shadow-2xl translate-y-3 scale-[0.98] transition-[transform,opacity] " \
                     "duration-200 max-h-[90vh] overflow-y-auto"
    MODAL_HEAD     = "flex items-center justify-between px-7 py-5 border-b border-gray-100"
    MODAL_BODY     = "px-7 py-6"
    MODAL_FOOT     = "flex items-center justify-end gap-3 px-7 py-5 border-t border-gray-100"

    # ── Stat band ──────────────────────────────────────────────────────────
    STAT_BAND = "grid grid-cols-2 lg:grid-cols-4 border border-gray-100 rounded-2xl bg-white overflow-hidden"
    STAT_CELL = "py-6 px-6 border-l border-gray-50 first:border-l-0 relative"
    STAT_UP   = "text-green-600 font-semibold"
    STAT_DOWN = "text-red-500 font-semibold"

    # ── Filter chips ───────────────────────────────────────────────────────
    CHIP = "peer-checked:bg-gray-900 peer-checked:border-gray-900 peer-checked:text-white " \
           "inline-flex items-center border border-gray-200 rounded-full px-3.5 py-1.5 text-xs " \
           "font-medium text-gray-500 transition-colors cursor-pointer"

    # ── Row action button ──────────────────────────────────────────────────
    ROWBTN = "w-8 h-8 rounded-full grid place-items-center text-gray-400 " \
             "hover:bg-gray-100 hover:text-gray-700 transition-colors"

    # ── Close / X button ───────────────────────────────────────────────────
    XBTN = "w-8 h-8 rounded-lg border border-gray-200 grid place-items-center " \
           "text-gray-400 hover:border-gray-400 hover:text-gray-700 transition-colors"

    # ── Form error feedback ────────────────────────────────────────────────
    FIELD_ERROR_TEXT = "text-xs text-red-600 mt-1"
    ERROR_BANNER = "p-4 bg-red-50 border border-red-200 rounded-xl text-sm text-red-700 mb-4"
    ERROR_ITEM   = "text-xs text-red-600 space-y-0.5 list-disc list-inside"

    # ── Status semantic colours ────────────────────────────────────────────
    STATUS_SUCCESS = "bg-green-100 text-green-700"
    STATUS_FAILED  = "bg-red-100 text-red-600"
    STATUS_PENDING = "bg-violet-100 text-violet-700"
    STATUS_WARNING = "bg-amber-100 text-amber-700"
    STATUS_NEUTRAL = "bg-gray-100 text-gray-600"

    # ── Priority pills ─────────────────────────────────────────────────────
    PRIORITY_HIGH   = "bg-red-100 text-red-600"
    PRIORITY_MEDIUM = "bg-blue-100 text-blue-700"
    PRIORITY_LOW    = "bg-violet-100 text-violet-600"

    # ── Legacy primary / accent (kept for backward compat) ─────────────────
    PRIMARY        = "bg-[#3D47F5] text-white hover:opacity-90"
    PRIMARY_GHOST  = "text-blue-600 hover:bg-blue-50"
    PRIMARY_ACTIVE = "bg-blue-50 text-blue-700 font-medium"

    # ── Status dispatch ────────────────────────────────────────────────────
    STATUS_MAP = {
      "settled"            => STATUS_SUCCESS,
      "paid"               => STATUS_SUCCESS,
      "success"            => STATUS_SUCCESS,
      "completed"          => STATUS_SUCCESS,
      "approved"           => STATUS_SUCCESS,
      "active"             => STATUS_SUCCESS,
      "clean"              => STATUS_SUCCESS,
      "won"                => STATUS_SUCCESS,
      "collected"          => STATUS_SUCCESS,
      "failed"             => STATUS_FAILED,
      "rejected"           => STATUS_FAILED,
      "expired"            => STATUS_FAILED,
      "blocked"            => STATUS_FAILED,
      "lost"               => STATUS_FAILED,
      "true_match_blocked" => STATUS_FAILED,
      "processing"         => STATUS_PENDING,
      "pending"            => STATUS_PENDING,
      "under_review"       => STATUS_PENDING,
      "initiated"          => STATUS_PENDING,
      "invited"            => STATUS_PENDING,
      "confirmed_pep"      => STATUS_PENDING,
      "potential_match"    => STATUS_PENDING,
      "disputed"           => STATUS_WARNING,
      "refunded"           => STATUS_WARNING,
      "suspended"          => STATUS_WARNING,
      "overdue"            => STATUS_WARNING,
      "cleared"            => STATUS_WARNING
    }.freeze

    def self.status_classes(status)
      STATUS_MAP.fetch(status.to_s, STATUS_NEUTRAL)
    end
  end
end
