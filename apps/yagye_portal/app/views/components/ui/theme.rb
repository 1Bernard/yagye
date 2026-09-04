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

    # ── Semantic palette ──────────────────────────────────────────────────────
    GREEN  = "#16a34a"   # Success, upward deltas
    AMBER  = "#d97706"   # Warning, pending
    RED    = "#dc2626"   # Error, downward deltas, failed
    TEAL   = "#0d9488"   # Secondary accent (KYB, teal contexts)
    PURPLE = "#6d28d9"   # Refunds, secondary data series

    # ── Semantic tints (8% opacity fills for icon containers / delta chips) ──────
    TINT_BRAND  = "rgba(61,71,245,0.08)"
    TINT_GREEN  = "rgba(22,163,74,0.08)"
    TINT_AMBER  = "rgba(217,119,6,0.08)"
    TINT_RED    = "rgba(220,38,38,0.08)"
    TINT_PURPLE = "rgba(109,40,217,0.08)"
    TINT_TEAL   = "rgba(13,148,136,0.08)"
    TINT_GRAY   = "rgba(107,114,128,0.08)"

    # ── Color tokens (CSS vars — auto-adapt to light/dark theme) ─────────────
    # See app/assets/tailwind/application.css for the token definitions.
    INK         = "var(--ink)"          # Titles, key data, primary text
    BODY_TEXT   = "var(--body-text)"    # Secondary text, subtitles, important body
    PROSE_TEXT  = "var(--prose-text)"   # Body text, descriptions, paragraphs
    MUTED_TEXT  = "var(--muted-text)"   # Labels, timestamps, captions
    SUBTLE_TEXT = "var(--subtle-text)"  # Decorative only — placeholders, resting icons
    FAINT_TEXT  = "var(--faint-text)"   # Separators, faint icons — never body text
    SURFACE     = "var(--surface)"      # Hover fills, input backgrounds
    BORDER      = "var(--border)"       # Default border / divider
    BORDER_MED  = "var(--border-med)"   # Stronger border for interactive elements
    CARD_BG     = "var(--card-bg)"      # White card / raised panel surface

    # ── Type scale (Tailwind class strings — use with class:) ────────────────
    # DISPLAY  — page/breadcrumb title, stat values, hero numbers
    TYPE_DISPLAY = "text-[16px] font-bold text-gray-900 tracking-tight leading-tight"
    # TITLE    — card headers, section names, modal headings
    TYPE_TITLE   = "text-[14px] font-semibold text-gray-900 leading-snug"
    # HEADING  — sub-section labels, table column titles (uppercase)
    TYPE_HEADING = "text-[10.5px] font-bold text-gray-500 uppercase tracking-[0.09em] leading-none"
    # BODY     — standard body text, cell values, descriptions
    TYPE_BODY    = "text-[13px] text-gray-600 leading-normal"
    # BODY_MD  — slightly heavier body for key values, names
    TYPE_BODY_MD = "text-[13px] font-medium text-gray-700 leading-normal"
    # CAPTION  — small supporting text, timestamps, metadata
    TYPE_CAPTION = "text-[11.5px] text-gray-500 leading-snug"
    # LABEL    — badge labels, status text inside pill badges
    TYPE_LABEL   = "text-[12px] font-medium text-gray-500"
    # MICRO    — uppercase section labels, keyboard shortcut hints
    TYPE_MICRO   = "text-[10px] font-bold text-gray-400 uppercase tracking-[0.1em]"
    # MONO     — transaction references, codes, API keys
    TYPE_MONO    = "font-mono text-[12px] font-medium text-gray-700"
    # NUM      — append to any type level for financial figures
    TYPE_NUM     = "tabular-nums"
    # STAT     — large KPI value in stat cards (26px, Plus Jakarta Sans 800)
    #            color is separate — append a text-* class after this token
    TYPE_STAT    = "font-display text-[26px] font-extrabold tracking-[-0.03em] tabular-nums leading-none"
    # AMOUNT   — hero-scale financial figure on show/detail pages (36px)
    TYPE_AMOUNT  = "font-display text-[36px] font-extrabold tracking-[-0.035em] tabular-nums leading-none"

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
    BTN_PRIMARY   = "bg-[#3D47F5] hover:opacity-90 text-white font-medium rounded-[8px] " \
                    "text-[12.5px] px-3 py-[5px] transition-opacity inline-flex items-center gap-[5px] " \
                    "disabled:opacity-50 disabled:cursor-not-allowed border-0 cursor-pointer"
    BTN_SECONDARY = "bg-white hover:border-gray-300 text-gray-700 border border-gray-200 " \
                    "font-medium rounded-[8px] text-[12.5px] px-3 py-[5px] transition-colors " \
                    "inline-flex items-center gap-[5px] cursor-pointer"
    BTN_DANGER    = "btn-danger bg-white text-red-600 border border-red-200 " \
                    "font-medium rounded-[8px] text-[12.5px] px-3 py-[5px] transition-colors " \
                    "inline-flex items-center gap-[5px] cursor-pointer"
    BTN_GHOST     = "text-gray-500 hover:text-gray-700 hover:bg-gray-100 font-medium " \
                    "rounded-[8px] text-[12.5px] px-3 py-[5px] transition-colors " \
                    "inline-flex items-center gap-[5px] cursor-pointer"
    BTN_ICON      = "w-7 h-7 rounded-[7px] grid place-items-center text-gray-400 " \
                    "hover:text-gray-700 hover:bg-gray-100 transition-colors border-0 cursor-pointer"

    # Legacy aliases used by existing sign-in form / layout components
    BUTTON_PRIMARY   = "inline-flex items-center gap-[5px] rounded-[8px] px-3 py-[5px] " \
                       "text-[12.5px] font-medium bg-[#3D47F5] text-white hover:opacity-90 " \
                       "transition-opacity border-0 cursor-pointer"
    BUTTON_BRAND     = "inline-flex items-center justify-center rounded-[8px] px-3 py-[5px] " \
                       "text-[12.5px] font-medium text-white transition-opacity hover:opacity-90 " \
                       "shadow-sm cursor-pointer"
    BUTTON_SECONDARY = "inline-flex items-center gap-[5px] rounded-[8px] border border-gray-200 " \
                       "px-3 py-[5px] text-[12.5px] font-medium text-gray-700 hover:bg-gray-100 " \
                       "transition-colors cursor-pointer"
    ICON_BUTTON      = "rounded-[7px] text-gray-400 hover:text-gray-600 hover:bg-gray-100 " \
                       "transition-colors cursor-pointer"
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
    BADGE_BASE    = "inline-flex items-center gap-1.5 text-[12px] font-semibold " \
                    "px-[9px] py-[3px] rounded-full"
    BADGE_SUCCESS = "badge-green #{BADGE_BASE}"
    BADGE_PENDING = "badge-violet #{BADGE_BASE}"
    BADGE_FAILED  = "badge-red #{BADGE_BASE}"
    BADGE_WARNING = "badge-amber #{BADGE_BASE}"
    BADGE_INFO    = "badge-blue #{BADGE_BASE}"
    BADGE_NEUTRAL = "badge-gray #{BADGE_BASE}"

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
                    "font-semibold nav-active"
    NAV_ACCENT_BAR = "absolute left-[-16px] top-1/2 -translate-y-1/2 w-0.5 h-4 bg-[#3D47F5]"
    NAV_ICON_ON   = "nav-active-icon flex-shrink-0"
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

    # ── Charts ─────────────────────────────────────────────────────────────
    SR_ONLY            = "sr-only"
    CHART_DOWNLOAD_BTN = "absolute top-2 right-2 opacity-0 group-hover:opacity-100 " \
                         "transition-opacity w-7 h-7 rounded-lg border border-gray-100 " \
                         "bg-white/90 grid place-items-center text-gray-400 " \
                         "hover:text-gray-700 hover:border-gray-300"
    CHART_EMPTY_STATE  = "h-full flex flex-col items-center justify-center gap-2 " \
                         "text-sm text-gray-400"

    # ── Form error feedback ────────────────────────────────────────────────
    FIELD_ERROR_TEXT = "text-xs text-red-600 mt-1"
    ERROR_BANNER = "p-4 bg-red-50 border border-red-200 rounded-xl text-sm text-red-700 mb-4"
    ERROR_ITEM   = "text-xs text-red-600 space-y-0.5 list-disc list-inside"

    # ── Status semantic colours ────────────────────────────────────────────
    STATUS_SUCCESS = "badge-green"
    STATUS_FAILED  = "badge-red"
    STATUS_PENDING = "badge-violet"
    STATUS_WARNING = "badge-amber"
    STATUS_NEUTRAL = "badge-gray"

    # ── Priority pills ─────────────────────────────────────────────────────
    PRIORITY_HIGH   = "badge-red"
    PRIORITY_MEDIUM = "badge-blue"
    PRIORITY_LOW    = "badge-violet"

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
