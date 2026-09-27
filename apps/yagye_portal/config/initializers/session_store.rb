# frozen_string_literal: true

# P17 — Redis-backed session store.
#
# Replaces the default CookieStore so sessions are server-side:
#   - Works correctly across N portal nodes (no per-node session state)
#   - Allows instant session invalidation (revoke the key server-side)
#   - No 4 KB cookie payload limit
#
# Falls back gracefully: if REDIS_URL is absent (bare `rails test` runs)
# the CookieStore is used instead so tests need no Redis.
if (redis_url = ENV["REDIS_URL"].presence)
  Rails.application.config.session_store(
    :redis_session_store,
    key:          "_yagye_portal_session",
    secure:       Rails.env.production?,
    httponly:     true,
    same_site:    :lax,
    expire_after: 12.hours,
    redis: {
      url:          redis_url,
      key_prefix:   "portal:session:",
      db:           0
    },
    on_redis_down: ->(e, _env, _sid) {
      Rails.logger.error("[Session] Redis unavailable: #{e.class} — #{e.message}")
      nil
    }
  )
else
  Rails.application.config.session_store(
    :cookie_store,
    key:      "_yagye_portal_session",
    secure:   Rails.env.production?,
    httponly: true,
    same_site: :lax
  )
end
