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
  { key: "disputes.submit_evidence",  resource: "disputes",        action: "submit_evidence",   description: "Prepare and save a draft evidence submission for an open dispute." },
  { key: "disputes.approve_evidence", resource: "disputes",        action: "approve_evidence",  description: "Review and approve drafted evidence before it is submitted to the network." },
  # payouts
  { key: "payouts.view",              resource: "payouts",         action: "view",              description: "View payout list and payout details." },
  { key: "payouts.request",           resource: "payouts",         action: "request",           description: "Submit an early payout request for ops review." },
  { key: "payouts.review_requests",   resource: "payouts",         action: "review_requests",   description: "Approve or reject merchant early payout requests." },
  # settlements
  { key: "settlements.view",             resource: "settlements", action: "view",             description: "View settlement runs and reconciliation break details." },
  { key: "settlements.approve_dispatch", resource: "settlements", action: "approve_dispatch", description: "Approve or reject a settlement batch before bank dispatch." },
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
  # reserves (Yagye ops only)
  { key: "reserves.manage",           resource: "reserves",         action: "manage",            description: "Create and approve reserve policies for merchants." },
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
    disputes.view disputes.submit_evidence disputes.approve_evidence
    payouts.view payouts.request
    settlements.view
    developers.view_api_keys developers.manage_api_keys developers.manage_webhooks
    team.view team.manage
  ],
  "merchant_finance" => %w[
    payments.view payments.export
    disputes.view disputes.submit_evidence
    payouts.view payouts.request
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
    payouts.view payouts.review_requests
    settlements.view settlements.approve_dispatch
    merchants.view merchants.approve merchants.suspend merchants.impersonate
    kyb.view
    reserves.manage
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
    u.password               = "Yagye2026!gh"
    u.first_name             = "Yagye"
    u.last_name              = "Admin"
    u.kind                   = "internal_staff"
    u.otp_required_for_login = false
  end

  UserRole.find_or_create_by!(user_id: admin.id, role_key: "ops_manager") do |ur|
    ur.granted_by = admin
    ur.granted_at = now
  end

  puts "Dev admin: admin@yagye.com / Yagye2026!gh (ops_manager)"

  # Compliance manager — separate user to preserve SoD in development.
  # KYB approvals require reviewed_by ≠ approved_by at the core record level;
  # giving a single user both roles would bypass that boundary in testing.
  compliance = User.find_or_create_by!(email: "compliance@yagye.com") do |u|
    u.password               = "Yagye2026!gh"
    u.first_name             = "Yagye"
    u.last_name              = "Compliance"
    u.kind                   = "internal_staff"
    u.otp_required_for_login = false
  end

  UserRole.find_or_create_by!(user_id: compliance.id, role_key: "compliance_manager") do |ur|
    ur.granted_by = admin
    ur.granted_at = now
  end

  puts "Dev compliance: compliance@yagye.com / Yagye2026!gh (compliance_manager)"

  # Ops analyst — second team manager for testing the maker/checker role change flow.
  # admin@yagye.com creates role change requests; ops@yagye.com approves them.
  ops = User.find_or_create_by!(email: "ops@yagye.com") do |u|
    u.password               = "Yagye2026!gh"
    u.first_name             = "Yagye"
    u.last_name              = "Ops"
    u.kind                   = "internal_staff"
    u.otp_required_for_login = false
  end

  UserRole.find_or_create_by!(user_id: ops.id, role_key: "ops_manager") do |ur|
    ur.granted_by = admin
    ur.granted_at = now
  end

  puts "Dev ops: ops@yagye.com / Yagye2026!gh (ops_manager)"

  # ── Merchant application — awaiting ops review ────────────────────────────
  # "Kofi Builds Ltd" has submitted their application. The real-world flow:
  #   1. Ops (admin@yagye.com) reviews → approves application in portal
  #   2. Ops invites the merchant owner → email sent → owner accepts → sets password
  #   3. Merchant owner fills KYB via /verify (profile → contact → documents → agreement)
  #   4. Compliance (compliance@yagye.com) reviews KYB → approves → email sent
  #   5. Ops grants sandbox mode via KYB Reviews page
  #   6. Merchant owner creates API keys in Developers page (portal → Core)
  #   7. Merchant uses keys to create checkout sessions and make real payments
  DEMO_MERCHANT_CODE = "MCH_DEMO_001"
  DEMO_MERCHANT_NAME = "Kofi Builds Ltd"
  DEMO_APP_CODE      = "APP_DEMO_001"

  PortalMerchantApplication.find_or_create_by!(application_code: DEMO_APP_CODE) do |a|
    a.merchant_code      = DEMO_MERCHANT_CODE
    a.status             = "submitted"
    a.legal_name         = DEMO_MERCHANT_NAME
    a.trading_name       = "KofiBuild"
    a.country            = "GH"
    a.industry           = "technology"
    a.employee_range     = "11-50"
    a.submitted_by_email = "owner@kofibuilds.com"
    a.last_applied_at    = 1.day.ago
    a.last_event_id      = "evt_app_demo_001"
    a.aggregate_version  = 1
  end

  puts "Merchant application: #{DEMO_APP_CODE} (submitted — ops must approve and invite the merchant owner)"
end
