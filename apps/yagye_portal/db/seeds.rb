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
  { key: "compliance_manager", name: "Compliance Manager",   scope: "internal", description: "Full compliance access including hit dispositions and KYB approvals." },
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
  { key: "payments.view_customer_pii",resource: "payments",        action: "view_customer_pii",description: "View unmasked customer MSISDN and email on payment records." },
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
  { key: "developers.manage_api_keys",resource: "developers",      action: "manage_api_keys",   description: "Create and revoke API keys." },
  { key: "developers.manage_webhooks",resource: "developers",      action: "manage_webhooks",   description: "Create, update, and delete webhook endpoints." },
  # team
  { key: "team.view",                 resource: "team",            action: "view",              description: "View team member list and their roles." },
  { key: "team.manage",               resource: "team",            action: "manage",            description: "Invite new members, update roles, and remove members." },
  # platform finance (Yagye ops only)
  { key: "platform_finance.view",     resource: "platform_finance",action: "view",              description: "View Yagye P&L dashboard, provider costs, and fee invoices." },
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
  ],
}.freeze

GRANT_MATRIX.each do |role_key, permission_keys|
  permission_keys.each do |perm_key|
    RolePermission.find_or_create_by!(role_key: role_key, permission_key: perm_key) do |rp|
      rp.granted_at = now
    end
  end
end

puts "Seeded #{Role.count} roles, #{Permission.count} permissions, #{RolePermission.count} grants."
