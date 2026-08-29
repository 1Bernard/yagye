# frozen_string_literal: true

module Team
  # Filterable user list query. Receives a policy_scope(User) relation
  # so merchant vs. ops scoping is already applied.
  class UsersQuery
    def initialize(relation = User.all)
      @relation = relation
    end

    def call(filters = {})
      scoped = @relation
      if filters[:q].present?
        q      = "%#{ActiveRecord::Base.sanitize_sql_like(filters[:q])}%"
        scoped = scoped.where("first_name ILIKE ? OR last_name ILIKE ? OR email ILIKE ?", q, q, q)
      end
      if filters[:role].present?
        scoped = scoped.joins(:user_roles)
                       .where(user_roles: { role_key: filters[:role], revoked_at: nil })
      end
      scoped.order(:first_name, :last_name)
    end
  end
end
