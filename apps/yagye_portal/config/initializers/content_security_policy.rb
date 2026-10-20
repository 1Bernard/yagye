# frozen_string_literal: true

# Content Security Policy — enforced in all environments.
#
# External script sources:
#   cdnjs.cloudflare.com  — QR code library (checkout/payment_links)
#   cdn.jsdelivr.net      — Drawflow (developers/routing_graph)
#
# Inline scripts (Stimulus, Vite HMR in dev) use per-request nonces injected
# by Rails via content_security_policy_nonce_generator below.

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data, "https://fonts.gstatic.com"
    policy.img_src     :self, :https, :data, :blob
    policy.object_src  :none

    policy.script_src  :self,
                       "https://cdnjs.cloudflare.com",
                       "https://cdn.jsdelivr.net"

    policy.style_src   :self, :unsafe_inline,
                       "https://cdn.jsdelivr.net",
                       "https://fonts.googleapis.com"

    # ActionCable / SolidCable WebSocket connection.
    policy.connect_src :self,
                       "wss:",   # WebSocket (Solid Cable in production)
                       "ws:"     # WebSocket (development)

    # Turbo Drive prefetch and frame requests stay on the same origin.
    policy.frame_src   :none

    # Report-only in staging/development so we don't break pages silently.
    # Flip to enforcement by removing the report_only line in production.
    # policy.report_uri  "/csp-violation-report-endpoint"
  end

  # Per-request nonce injected into nonce-bearing directives.
  # session.id is stable for the life of a session and unique per user/device.
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]
end
