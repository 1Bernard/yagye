# frozen_string_literal: true

# Rack::Attack — rate limiting and IP throttling.
#
# Rules are intentionally generous for a PSP portal (legitimate users may have
# multiple admins behind a shared corporate NAT), but strict enough to slow
# credential-stuffing and brute-force attacks.

class Rack::Attack
  # ── Safelist ────────────────────────────────────────────────────────────────

  # Internal health-check probes bypass all rules.
  safelist("allow-health-check") { |req| req.path == "/up" }

  # ── Throttles ───────────────────────────────────────────────────────────────

  # Login: 10 attempts per 20 minutes per IP.
  throttle("logins/ip", limit: 10, period: 20.minutes) do |req|
    req.ip if req.path == "/users/sign_in" && req.post?
  end

  # Login: 5 attempts per 20 minutes per email (prevents targeted brute-force).
  throttle("logins/email", limit: 5, period: 20.minutes) do |req|
    if req.path == "/users/sign_in" && req.post?
      req.params.dig("user", "email").to_s.downcase.presence
    end
  end

  # Password reset: 5 per hour per IP.
  throttle("password-reset/ip", limit: 5, period: 1.hour) do |req|
    req.ip if req.path == "/users/password" && req.post?
  end

  # Invitation acceptance: 10 per hour per IP (covers shared office IPs).
  throttle("invitations/ip", limit: 10, period: 1.hour) do |req|
    req.ip if req.path.start_with?("/account/invitations") && req.post?
  end

  # TOTP verification: 5 per 10 minutes per IP (prevents 6-digit enumeration).
  throttle("totp/ip", limit: 5, period: 10.minutes) do |req|
    req.ip if req.path.include?("/two-factor") && req.post?
  end

  # General API: 200 requests per minute per IP.
  throttle("api/ip", limit: 200, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api/")
  end

  # ── Blocklist ───────────────────────────────────────────────────────────────

  # Block IPs that have been throttled on login more than 30 times in an hour.
  blocklist("brute-force/ip") do |req|
    Rack::Attack::Allow2Ban.filter(req.ip, maxretry: 30, findtime: 1.hour, bantime: 1.day) do
      req.path == "/users/sign_in" && req.post?
    end
  end

  # ── Response ────────────────────────────────────────────────────────────────

  self.throttled_responder = lambda do |env|
    [
      429,
      {
        "Content-Type"  => "application/json",
        "Retry-After"   => env["rack.attack.match_data"][:period].to_s
      },
      [ { error: "Too many requests. Please wait before trying again." }.to_json ]
    ]
  end
end
