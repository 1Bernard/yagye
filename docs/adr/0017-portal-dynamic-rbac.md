# 0017 — Portal RBAC: DB-backed roles and permissions, no hardcoded role checks

Date: 2026-08-28
Status: Accepted

## Context

The portal serves eight distinct roles across two scopes (merchant / internal). An earlier sketch hardcoded role checks inline (`if role == "ops_admin"`). This fails in three ways:

1. Adding a new role requires code changes in every policy that needs to grant it access.
2. Narrowing a role's permissions requires a deploy.
3. There is no audit trail of who changed which role's access.

## Decision

RBAC is fully DB-backed:

```
roles            (key PK, name, scope: merchant|internal, system_role)
permissions      (key PK, resource, action, description)
role_permissions (role_key FK, permission_key FK, granted_at)
user_roles       (id, user_id FK, role_key FK, merchant_code nullable,
                  granted_by FK, granted_at, expires_at, revoked_at)
```

`user_roles` allows time-boxed elevation (`expires_at`) and is the audit trail. A `User` never holds a `role` string column — access is always resolved through the join:

```ruby
# ApplicationPolicy helper
def permitted?(permission_key)
  @user.user_roles.active.joins(role: :role_permissions)
    .exists?(role_permissions: { permission_key: permission_key.to_s })
end
```

Pundit policies call `permitted?(:payments_refund)` rather than `user.role == "ops_manager"`.

The grant matrix is seeded from `db/seeds.rb` under version control. CI asserts that every permission referenced by a policy exists in the seed file.

**Scope enforcement**: a merchant role can never be granted to an `internal_staff` user and vice versa — enforced by a DB CHECK constraint and validated in `UserRole#create`.

**Caching**: `permitted?` results are cached per-request in `Current.permissions` (a `Set` populated on first call and cleared between requests). DB hits = 1 per request, not 1 per `permitted?` call.

## Consequences

- **Positive**: An ops admin can adjust what `merchant_finance` can see from the portal UI without a deploy.
- **Positive**: Time-boxed elevation (`expires_at`) is first-class — an ops manager can be elevated for an incident window and automatically de-elevated.
- **Positive**: Adding a new permission requires seeding it and referencing it in the policy — no policy code changes elsewhere.
- **Negative**: Two DB tables to seed and maintain. The seed file is the single source of truth; a permission removed from seeds without removing the policy reference fails CI.
- **Note**: `system_role: true` roles cannot be edited or deleted from the portal UI — only code changes can mutate them.
