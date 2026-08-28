# Single source of truth for all design tokens.
# Rules:
#   1. Colour/surface/typography tokens MUST come from this module.
#   2. Layout utilities (flex, gap, px, sizing, position) are exempt — inline is fine.
#   3. Status colours go through Theme.status_classes(status_string).
#   4. Tailwind JIT must scan app/components/**/*.rb for class detection.
module UI
  module Theme
    # ── Primary / accent (teal) ────────────────────────────────────────────
    PRIMARY        = "bg-teal-400 text-white hover:bg-teal-500"
    PRIMARY_GHOST  = "text-teal-600 hover:bg-teal-50"
    PRIMARY_ACTIVE = "bg-teal-50 text-teal-700 font-medium"

    # Icon / avatar teal tints
    ICON_BG_TEAL   = "bg-teal-50 text-teal-500"
    LOGO_ICON      = "bg-teal-400 text-white"
    AVATAR         = "bg-teal-100 text-teal-700"

    # ── Surfaces ───────────────────────────────────────────────────────────
    CARD           = "bg-white rounded-xl border border-gray-100 shadow-sm"
    SIDEBAR        = "bg-white border-r border-gray-100"
    TOPBAR         = "bg-white border-b border-gray-100"

    # ── Navigation ─────────────────────────────────────────────────────────
    NAV_ITEM       = "text-gray-600 hover:bg-gray-50"
    NAV_ICON_ON    = "text-teal-600"
    NAV_ICON_OFF   = "text-gray-400"

    # ── Typography ─────────────────────────────────────────────────────────────
    PAGE_TITLE     = "text-lg font-semibold text-gray-900"
    PAGE_SUBTITLE  = "text-sm text-gray-500"
    SECTION_TITLE  = "text-sm font-semibold text-gray-700"
    LABEL          = "text-xs font-medium text-gray-500 uppercase tracking-wide"
    MUTED          = "text-sm text-gray-500"
    BODY           = "text-sm text-gray-700"
    HEADING        = "font-semibold text-gray-900"
    AUTH_TITLE     = "text-xl font-semibold text-gray-900"
    FORM_LABEL     = "block text-sm font-medium text-gray-700"
    FORM_HINT      = "text-xs text-gray-500"
    FORM_MUTED     = "text-xs text-gray-400"

    # ── Links ──────────────────────────────────────────────────────────────────
    LINK_PRIMARY   = "font-medium text-teal-600 hover:text-teal-700 transition-colors"
    LINK_MUTED     = "text-gray-400 hover:text-gray-600 transition-colors"

    # ── Table ──────────────────────────────────────────────────────────────
    TH = "text-xs font-medium text-gray-500 px-4 py-3 text-left select-none"
    TD = "text-sm text-gray-800 px-4 py-3"

    # ── Form controls ──────────────────────────────────────────────────────
    INPUT = "w-full rounded-lg border border-gray-200 px-3 py-2 text-sm " \
            "text-gray-900 placeholder:text-gray-400 " \
            "focus:outline-none focus:ring-2 focus:ring-teal-400"

    SEARCH_INPUT = "rounded-lg border border-gray-200 text-sm text-gray-900 " \
                   "placeholder:text-gray-400 focus:outline-none focus:ring-2 focus:ring-teal-400"

    BUTTON_PRIMARY = "inline-flex items-center gap-2 rounded-lg px-4 py-2 text-sm " \
                     "font-medium bg-teal-400 text-white hover:bg-teal-500 transition-colors"

    BUTTON_SECONDARY = "inline-flex items-center gap-2 rounded-lg border border-gray-200 " \
                       "px-4 py-2 text-sm font-medium text-gray-700 hover:bg-gray-50 transition-colors"

    ICON_BUTTON = "rounded-lg text-gray-400 hover:text-gray-600 hover:bg-gray-50 transition-colors"
    CHECKBOX    = "h-4 w-4 rounded border-gray-300 text-teal-500 focus:ring-teal-400"

    # ── Feedback ───────────────────────────────────────────────────────────────
    ERROR_BANNER = "p-3 bg-red-50 border border-red-200 rounded-lg"
    ERROR_ITEM   = "text-xs text-red-600 space-y-0.5 list-disc list-inside"

    # ── Status semantic colours (badge background + text) ──────────────────
    STATUS_SUCCESS = "bg-green-100 text-green-700"
    STATUS_FAILED  = "bg-red-100 text-red-600"
    STATUS_PENDING = "bg-violet-100 text-violet-700"
    STATUS_WARNING = "bg-amber-100 text-amber-700"
    STATUS_NEUTRAL = "bg-gray-100 text-gray-600"

    # ── Priority pills ─────────────────────────────────────────────────────
    PRIORITY_HIGH   = "bg-red-100 text-red-600"
    PRIORITY_MEDIUM = "bg-teal-100 text-teal-700"
    PRIORITY_LOW    = "bg-violet-100 text-violet-600"

    # ── Status dispatch ────────────────────────────────────────────────────
    STATUS_MAP = {
      "settled"          => STATUS_SUCCESS,
      "paid"             => STATUS_SUCCESS,
      "success"          => STATUS_SUCCESS,
      "completed"        => STATUS_SUCCESS,
      "approved"         => STATUS_SUCCESS,
      "active"           => STATUS_SUCCESS,
      "clean"            => STATUS_SUCCESS,
      "won"              => STATUS_SUCCESS,
      "collected"        => STATUS_SUCCESS,
      "failed"           => STATUS_FAILED,
      "rejected"         => STATUS_FAILED,
      "expired"          => STATUS_FAILED,
      "blocked"          => STATUS_FAILED,
      "lost"             => STATUS_FAILED,
      "true_match_blocked" => STATUS_FAILED,
      "processing"       => STATUS_PENDING,
      "pending"          => STATUS_PENDING,
      "under_review"     => STATUS_PENDING,
      "initiated"        => STATUS_PENDING,
      "invited"          => STATUS_PENDING,
      "confirmed_pep"    => STATUS_PENDING,
      "potential_match"  => STATUS_PENDING,
      "disputed"         => STATUS_WARNING,
      "refunded"         => STATUS_WARNING,
      "suspended"        => STATUS_WARNING,
      "overdue"          => STATUS_WARNING,
      "cleared"          => STATUS_WARNING
    }.freeze

    def self.status_classes(status)
      STATUS_MAP.fetch(status.to_s, STATUS_NEUTRAL)
    end
  end
end
