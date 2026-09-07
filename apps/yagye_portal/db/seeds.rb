now = Time.current

# ── Roles ──────────────────────────────────────────────────────────────────────
ROLE_DEFS = [
  { key: "merchant_owner",     name: "Merchant Owner",       scope: "merchant", description: "Full access to the merchant account, including team management and API keys." },
  { key: "merchant_finance",   name: "Finance Manager",      scope: "merchant", description: "Payment, payout, and settlement visibility. Cannot manage API keys or team." },
  { key: "merchant_developer", name: "Developer",            scope: "merchant", description: "API keys, webhooks, and payment read access. No financial actions." },
  { key: "merchant_support",   name: "Support Agent",        scope: "merchant", description: "Read-only payment and dispute view for merchant support staff." },
  { key: "ops_analyst",        name: "Ops Analyst",          scope: "internal", description: "Yagye ops read access — view payments, merchants, KYB, and settlements." },
  { key: "ops_manager",        name: "Ops Manager",          scope: "internal", description: "Full ops access including merchant approvals, suspensions, and platform finance." },
  { key: "compliance_analyst", name: "Compliance Analyst",   scope: "internal", description: "AML screening review, KYB document review, merchant profile read access." },
  { key: "compliance_manager", name: "Compliance Manager",   scope: "internal", description: "Full compliance access including hit dispositions and KYB approvals." }
].freeze

ROLE_DEFS.each do |attrs|
  Role.find_or_create_by!(key: attrs[:key]) do |r|
    r.name        = attrs[:name]
    r.scope       = attrs[:scope]
    r.description = attrs[:description]
    r.system_role = true
  end
end

# ── Permissions ────────────────────────────────────────────────────────────────
PERMISSION_DEFS = [
  # payments
  { key: "payments.view",             resource: "payments",        action: "view",             description: "View payment list and individual payment details." },
  { key: "payments.view_customer_pii", resource: "payments",        action: "view_customer_pii", description: "View unmasked customer MSISDN and email on payment records." },
  { key: "payments.refund",           resource: "payments",        action: "refund",            description: "Initiate a refund on a completed payment." },
  { key: "payments.export",           resource: "payments",        action: "export",            description: "Export payment data as CSV." },
  # disputes
  { key: "disputes.view",             resource: "disputes",        action: "view",              description: "View dispute list and individual dispute details." },
  { key: "disputes.submit_evidence",  resource: "disputes",        action: "submit_evidence",   description: "Submit evidence for an open dispute before the deadline." },
  # payouts
  { key: "payouts.view",              resource: "payouts",         action: "view",              description: "View payout list and payout details." },
  # settlements
  { key: "settlements.view",          resource: "settlements",     action: "view",              description: "View settlement runs and reconciliation break details." },
  # merchants (ops)
  { key: "merchants.view",            resource: "merchants",       action: "view",              description: "View merchant list and merchant profile pages." },
  { key: "merchants.approve",         resource: "merchants",       action: "approve",           description: "Approve a merchant for live mode processing." },
  { key: "merchants.suspend",         resource: "merchants",       action: "suspend",           description: "Suspend or terminate a merchant account." },
  { key: "merchants.impersonate",     resource: "merchants",       action: "impersonate",       description: "View the portal as a merchant (read-only support impersonation)." },
  # KYB / compliance
  { key: "kyb.view",                  resource: "kyb",             action: "view",              description: "View KYB documents, beneficial owners, and screening subjects." },
  { key: "kyb.disposition",           resource: "kyb",             action: "disposition",       description: "Disposition a screening hit as false positive or true match." },
  { key: "kyb.approve_merchant",      resource: "kyb",             action: "approve_merchant",  description: "Approve a merchant's KYB application after review." },
  # developers
  { key: "developers.view_api_keys",  resource: "developers",      action: "view_api_keys",     description: "View API key list (prefix only, never the full key)." },
  { key: "developers.manage_api_keys", resource: "developers",      action: "manage_api_keys",   description: "Create and revoke API keys." },
  { key: "developers.manage_webhooks", resource: "developers",      action: "manage_webhooks",   description: "Create, update, and delete webhook endpoints." },
  # team
  { key: "team.view",                 resource: "team",            action: "view",              description: "View team member list and their roles." },
  { key: "team.manage",               resource: "team",            action: "manage",            description: "Invite new members, update roles, and remove members." },
  # platform finance (Yagye ops only)
  { key: "platform_finance.view",     resource: "platform_finance", action: "view",              description: "View Yagye P&L dashboard, provider costs, and fee invoices." }
].freeze

PERMISSION_DEFS.each do |attrs|
  Permission.find_or_create_by!(key: attrs[:key]) do |p|
    p.resource    = attrs[:resource]
    p.action      = attrs[:action]
    p.description = attrs[:description]
    p.created_at  = now
  end
end

# ── Grant matrix ───────────────────────────────────────────────────────────────
# Maps each role key to the permission keys it is granted.
# This is the single source of truth for the access control policy.
GRANT_MATRIX = {
  "merchant_owner" => %w[
    payments.view payments.view_customer_pii payments.refund payments.export
    disputes.view disputes.submit_evidence
    payouts.view
    settlements.view
    developers.view_api_keys developers.manage_api_keys developers.manage_webhooks
    team.view team.manage
  ],
  "merchant_finance" => %w[
    payments.view payments.export
    disputes.view
    payouts.view
    settlements.view
    team.view
  ],
  "merchant_developer" => %w[
    payments.view
    developers.view_api_keys developers.manage_api_keys developers.manage_webhooks
    team.view
  ],
  "merchant_support" => %w[
    payments.view payments.view_customer_pii
    disputes.view disputes.submit_evidence
    team.view
  ],
  "ops_analyst" => %w[
    payments.view payments.view_customer_pii payments.export
    disputes.view
    payouts.view
    settlements.view
    merchants.view
    kyb.view
  ],
  "ops_manager" => %w[
    payments.view payments.view_customer_pii payments.refund payments.export
    disputes.view
    payouts.view
    settlements.view
    merchants.view merchants.approve merchants.suspend merchants.impersonate
    kyb.view
    team.view team.manage
    platform_finance.view
  ],
  "compliance_analyst" => %w[
    payments.view
    merchants.view
    kyb.view
  ],
  "compliance_manager" => %w[
    payments.view payments.view_customer_pii
    merchants.view merchants.approve merchants.suspend
    kyb.view kyb.disposition kyb.approve_merchant
  ]
}.freeze

GRANT_MATRIX.each do |role_key, permission_keys|
  permission_keys.each do |perm_key|
    RolePermission.find_or_create_by!(role_key: role_key, permission_key: perm_key) do |rp|
      rp.granted_at = now
    end
  end
end

puts "Seeded #{Role.count} roles, #{Permission.count} permissions, #{RolePermission.count} grants."

# ── Development users ───────────────────────────────────────────────────────────
if Rails.env.development? || Rails.env.test?
  # Internal ops admin
  admin = User.find_or_create_by!(email: "admin@yagye.com") do |u|
    u.password               = "Yagye2026!"
    u.first_name             = "Yagye"
    u.last_name              = "Admin"
    u.kind                   = "internal_staff"
    u.otp_required_for_login = false
  end

  UserRole.find_or_create_by!(user_id: admin.id, role_key: "ops_manager") do |ur|
    ur.granted_by = admin
    ur.granted_at = now
  end

  puts "Dev admin: admin@yagye.com / Yagye2026! (ops_manager)"

  # Merchant owner — used to preview the Developers, Payments, Team pages
  DEMO_MERCHANT_CODE = "MCH_DEMO_001"
  DEMO_MERCHANT_NAME = "Kofi Builds Ltd"

  merchant_owner = User.find_or_create_by!(email: "owner@kofibuilds.com") do |u|
    u.password               = "Yagye2026!"
    u.first_name             = "Kofi"
    u.last_name              = "Mensah"
    u.kind                   = "merchant_user"
    u.otp_required_for_login = false
  end

  MerchantMembership.find_or_create_by!(user: merchant_owner, merchant_code: DEMO_MERCHANT_CODE) do |m|
    m.merchant_name = DEMO_MERCHANT_NAME
    m.state         = "active"
    m.accepted_at   = 14.days.ago
  end

  UserRole.find_or_create_by!(user_id: merchant_owner.id, role_key: "merchant_owner") do |ur|
    ur.granted_by = merchant_owner
    ur.granted_at = now
  end

  puts "Dev merchant: owner@kofibuilds.com / Yagye2026! (merchant_owner, #{DEMO_MERCHANT_CODE})"

  # ── Demo API keys ─────────────────────────────────────────────────────────────
  demo_keys = [
    {
      key_id:      "3e4f1a2b-0001-0000-0000-000000000001",
      label:       "Production server",
      key_prefix:  "sk_test_Kf8mN2",
      kind:        "secret",
      mode:        "test",
      scopes:      %w[payments:read payments:write refunds:write webhooks:write customers:read],
      created_by:  "owner@kofibuilds.com",
      created_at:  12.days.ago,
      last_used_at: 2.hours.ago,
      revoked_at:  nil
    },
    {
      key_id:      "3e4f1a2b-0002-0000-0000-000000000002",
      label:       "Mobile app",
      key_prefix:  "pk_test_Rx9wQ7",
      kind:        "publishable",
      mode:        "test",
      scopes:      %w[payments:read],
      created_by:  "owner@kofibuilds.com",
      created_at:  8.days.ago,
      last_used_at: 1.day.ago,
      revoked_at:  nil
    },
    {
      key_id:      "3e4f1a2b-0003-0000-0000-000000000003",
      label:       "Old CI key",
      key_prefix:  "sk_test_Jd3pL1",
      kind:        "secret",
      mode:        "test",
      scopes:      %w[payments:read payments:write],
      created_by:  "owner@kofibuilds.com",
      created_at:  30.days.ago,
      last_used_at: 15.days.ago,
      revoked_at:  10.days.ago
    }
  ]

  demo_keys.each do |attrs|
    PortalApiKey.find_or_initialize_by(key_id: attrs[:key_id]).tap do |k|
      k.merchant_code    = DEMO_MERCHANT_CODE
      k.label            = attrs[:label]
      k.key_prefix       = attrs[:key_prefix]
      k.kind             = attrs[:kind]
      k.mode             = attrs[:mode]
      k.scopes           = attrs[:scopes]
      k.created_by       = attrs[:created_by]
      k.created_at       = attrs[:created_at]
      k.last_used_at     = attrs[:last_used_at]
      k.revoked_at       = attrs[:revoked_at]
      k.last_event_id    = ""
      k.last_applied_at  = now
      k.save!
    end
  end

  puts "Seeded #{demo_keys.size} demo API keys for #{DEMO_MERCHANT_CODE}"

  # ── Demo webhook endpoints ────────────────────────────────────────────────────
  endpoint_1_id = "4a5b2c3d-0001-0000-0000-000000000001"
  endpoint_2_id = "4a5b2c3d-0002-0000-0000-000000000002"

  demo_endpoints = [
    {
      endpoint_id:          endpoint_1_id,
      url:                  "https://api.kofibuilds.com/webhooks/yagye",
      mode:                 "test",
      active:               true,
      subscribed_events:    %w[payment.paid payment.failed payment.refunded dispute.opened],
      consecutive_failures: 0,
      created_at:           10.days.ago
    },
    {
      endpoint_id:          endpoint_2_id,
      url:                  "https://staging.kofibuilds.com/hooks/payments",
      mode:                 "test",
      active:               false,
      subscribed_events:    %w[payment.paid payment.failed],
      consecutive_failures: 3,
      created_at:           20.days.ago,
      disabled_at:          5.days.ago
    }
  ]

  demo_endpoints.each do |attrs|
    PortalWebhookEndpoint.find_or_initialize_by(endpoint_id: attrs[:endpoint_id]).tap do |e|
      e.merchant_code        = DEMO_MERCHANT_CODE
      e.url                  = attrs[:url]
      e.mode                 = attrs[:mode]
      e.active               = attrs[:active]
      e.subscribed_events    = attrs[:subscribed_events]
      e.consecutive_failures = attrs[:consecutive_failures]
      e.created_at           = attrs[:created_at]
      e.disabled_at          = attrs[:disabled_at] if attrs[:disabled_at]
      e.last_event_id        = ""
      e.last_applied_at      = now
      e.save!
    end
  end

  puts "Seeded #{demo_endpoints.size} demo webhook endpoints for #{DEMO_MERCHANT_CODE}"

  # ── Demo webhook deliveries ───────────────────────────────────────────────────
  demo_deliveries = [
    { event_type: "payment.paid",     state: "delivered", response_status: 200, duration_ms: 143,  attempt: 1, delivered_at: 1.hour.ago,    last_applied_at: 1.hour.ago },
    { event_type: "payment.failed",   state: "delivered", response_status: 200, duration_ms: 98,   attempt: 1, delivered_at: 3.hours.ago,   last_applied_at: 3.hours.ago },
    { event_type: "payment.refunded", state: "failed",    response_status: 500, duration_ms: 2100, attempt: 3, delivered_at: 6.hours.ago,   last_applied_at: 6.hours.ago },
    { event_type: "dispute.opened",   state: "delivered", response_status: 200, duration_ms: 210,  attempt: 1, delivered_at: 1.day.ago,     last_applied_at: 1.day.ago },
    { event_type: "payment.paid",     state: "delivered", response_status: 201, duration_ms: 88,   attempt: 1, delivered_at: 2.days.ago,    last_applied_at: 2.days.ago },
    { event_type: "payment.paid",     state: "failed",    response_status: 503, duration_ms: 5000, attempt: 5, delivered_at: 3.days.ago,    last_applied_at: 3.days.ago },
    { event_type: "payment.failed",   state: "delivered", response_status: 200, duration_ms: 176,  attempt: 1, delivered_at: 4.days.ago,    last_applied_at: 4.days.ago },
    { event_type: "payment.paid",     state: "delivered", response_status: 200, duration_ms: 134,  attempt: 1, delivered_at: 5.days.ago,    last_applied_at: 5.days.ago }
  ]

  demo_deliveries.each_with_index do |attrs, i|
    delivery_id = "5c6d3e4f-%04d-0000-0000-000000000001" % (i + 1)
    PortalWebhookDelivery.find_or_initialize_by(delivery_id: delivery_id).tap do |d|
      d.merchant_code   = DEMO_MERCHANT_CODE
      d.endpoint_id     = endpoint_1_id
      d.event_type      = attrs[:event_type]
      d.event_id        = "evt_%05d" % (i + 1)
      d.state           = attrs[:state]
      d.response_status = attrs[:response_status]
      d.duration_ms     = attrs[:duration_ms]
      d.attempt         = attrs[:attempt]
      d.delivered_at    = attrs[:delivered_at]
      d.last_applied_at = attrs[:last_applied_at]
      d.request_body    = { amount: 10000, currency: "GHS", reference: "ref_#{i + 1}" }
      d.request_headers = { "Content-Type" => "application/json", "X-Yagye-Signature" => "sha256=abc#{i}" }
      d.response_body   = attrs[:state] == "delivered" ? '{"ok":true}' : '{"error":"Service Unavailable"}'
      d.save!
    end
  end

  puts "Seeded #{demo_deliveries.size} demo webhook deliveries for #{DEMO_MERCHANT_CODE}"
end
