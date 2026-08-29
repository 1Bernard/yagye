class PaymentPolicy < ApplicationPolicy
  def index?
    permitted?("payments.view")
  end

  def show?
    permitted?("payments.view")
  end

  def refund?
    permitted?("payments.refund")
  end

  def export?
    permitted?("payments.export")
  end

  def view_customer_pii?
    permitted?("payments.view_customer_pii")
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.internal_staff?

      scope.for_merchant(user.merchant_code)
    end
  end
end
