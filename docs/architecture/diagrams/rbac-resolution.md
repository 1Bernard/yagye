# Portal RBAC: Permission Resolution

Last updated: 2026-10-18

```
PORTAL RBAC: PERMISSION RESOLUTION
=====================================
Last updated: 2026-10-18

PURPOSE: Show how a portal user's permissions are resolved,
         checked, and how the DB-backed dynamic RBAC differs
         from static code-based role checking.

──────────────────────────────────────────────────────────────────────────────

THE FOUR TABLES:

  ┌──────────────┐    ┌─────────────────────┐    ┌─────────────────┐
  │    roles      │    │   role_permissions   │    │   permissions   │
  ├──────────────┤    ├─────────────────────┤    ├─────────────────┤
  │ key (PK)     │◄──┐│ role_key (FK)        │┌──►│ key (PK)        │
  │ name         │   └│ permission_key (FK)  ├┘   │ name            │
  │ scope        │    │ PK: (role_key,        │    │ description     │
  │ description  │    │      permission_key)  │    └─────────────────┘
  │ system_role  │    └─────────────────────┘
  └──────────────┘
                                  ▲
  ┌─────────────────────────────────────────────────────────┐
  │  user_roles                                              │
  ├──────────────────────────────────────────────────────────┤
  │  user_id       uuid FK → users                           │
  │  role_key      text FK → roles                           │
  │  expires_at    timestamptz NULL   (time-boxed elevation) │
  │  revoked_at    timestamptz NULL   (soft revocation)      │
  │  granted_by_id uuid FK → users   (audit trail)          │
  └──────────────────────────────────────────────────────────┘

──────────────────────────────────────────────────────────────────────────────

PERMISSION RESOLUTION PER REQUEST:

  HTTP request arrives for portal user
       │
       ▼
  Current.user = fetched from session
       │
       ▼
  First permitted?() call in the request lifecycle:
       │
       ▼
  ┌──────────────────────────────────────────────────────────────┐
  │  SQL (runs ONCE per request, result memoized in Current):     │
  │                                                              │
  │  SELECT p.key FROM permissions p                             │
  │  JOIN role_permissions rp ON rp.permission_key = p.key       │
  │  JOIN user_roles ur ON ur.role_key = rp.role_key             │
  │  WHERE ur.user_id = $user_id                                 │
  │    AND ur.revoked_at IS NULL                                 │
  │    AND (ur.expires_at IS NULL OR ur.expires_at > NOW())      │
  └──────────────────────────────────────────────────────────────┘
       │
       ▼
  Current.permissions = Set { "payments.view",
                               "payments.refund",
                               "developers.view_api_keys",
                               ... }
       │
       ▼
  All subsequent permitted?("key") calls in this request:
    O(1) Set#include? lookup — no further SQL
       │
       ▼
  Pundit policy checks:

  class PaymentPolicy < ApplicationPolicy
    def refund?
      merchant_user? && permitted?("payments.refund") &&
      record.merchant_code == user.merchant_code
    end
  end

──────────────────────────────────────────────────────────────────────────────

ACTIVE ROLE SCOPE:

  A user role is ACTIVE if and only if:
    revoked_at IS NULL
    AND (expires_at IS NULL OR expires_at > NOW())

  Expired roles:
    Remain in the table as audit trail.
    NOT included in the permissions query (expires_at > NOW() check).
    No cron job needed to "expire" them — the condition is evaluated at query time.

  Revoked roles:
    revoked_at = NOW() is set explicitly.
    Immediately excluded from next request's permission query.
    Remain in table for audit.

──────────────────────────────────────────────────────────────────────────────

SEEDED ROLES (system_role = true — cannot be deleted via UI):

  ┌─────────────────────────┬──────────┬─────────────────────────────────────┐
  │ Role Key                │ Scope    │ Purpose                             │
  ├─────────────────────────┼──────────┼─────────────────────────────────────┤
  │ merchant_owner          │ merchant │ Full merchant control               │
  │ merchant_finance        │ merchant │ Payments, settlements, exports      │
  │ merchant_developer      │ merchant │ API keys, webhooks, integration     │
  │ merchant_support        │ merchant │ Payments + disputes read-only       │
  ├─────────────────────────┼──────────┼─────────────────────────────────────┤
  │ ops_analyst             │ internal │ Read-only across all merchants      │
  │ ops_manager             │ internal │ Write: KYB, routing, adjustments    │
  │ compliance_analyst      │ internal │ Screening, compliance reads         │
  │ compliance_manager      │ internal │ Compliance decisions, SoD approvals │
  └─────────────────────────┴──────────┴─────────────────────────────────────┘

──────────────────────────────────────────────────────────────────────────────

SCOPE ENFORCEMENT (DB CHECK):

  user_roles CHECK constraint:
    CHECK (
      (roles.scope = 'merchant' AND users.kind = 'merchant_user')
      OR
      (roles.scope = 'internal' AND users.kind = 'ops_user')
    )

  An ops user CANNOT be assigned a merchant-scope role.
  A merchant user CANNOT be assigned an internal-scope role.
  Enforced by the database — not bypassed by any Rails callback.

──────────────────────────────────────────────────────────────────────────────

TIME-BOXED ELEVATION (break-glass):

  Scenario: ops_analyst needs temporary ops_manager access for 4 hours.

  INSERT user_roles (
    user_id = alice.id,
    role_key = 'ops_manager',
    expires_at = 4.hours.from_now,
    granted_by_id = admin.id
  )

  During those 4 hours:  alice has ops_manager permissions
  After 4 hours:         expires_at < NOW() → ops_manager excluded
                         No cron, no manual revocation needed.
  Alice's audit trail:   user_roles row remains with expires_at timestamp.

──────────────────────────────────────────────────────────────────────────────

CI-ENFORCED PERMISSION COVERAGE:

  A CI test asserts that every permitted?("key") call in every Pundit
  policy references a permission key that exists in the permissions table.

  This prevents:
    Developer adds  permitted?("payments.export")
    Forgets to seed the "payments.export" permission row
    Runtime: permitted?() silently returns false (key not in set)
             No error raised — just silent denial

  The CI test catches this at build time, not at runtime.

──────────────────────────────────────────────────────────────────────────────

PERMISSION KEY TAXONOMY (dotted namespace):

  payments.*          → payments.view, payments.refund, payments.export
  disputes.*          → disputes.view, disputes.respond
  settlements.*       → settlements.view, settlements.export
  developers.*        → developers.view_api_keys, developers.manage_api_keys,
                        developers.manage_webhooks
  account.*           → account.manage_team, account.manage_billing
  compliance.*        → compliance.view, compliance.screening_review
  ops.*               → ops.kyb_review, ops.routing_manage, ops.merchant_view

  Total at P13: 21 permissions across 7 namespaces.
  New namespaces added as features are built — CI ensures coverage.
```
