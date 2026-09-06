# frozen_string_literal: true

WebAuthn.configure do |config|
  origin = ENV.fetch("PORTAL_ORIGIN", "http://localhost:3000")
  config.allowed_origins = [ origin ]
  config.rp_id          = URI.parse(origin).host   # hostname only — no port; WebAuthn spec requirement
  config.rp_name        = "Yagye"
end
