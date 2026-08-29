class PaymentsController < ApplicationController
  def index
    authorize Payment, :index?

    scope = policy_scope(Payment).recent
    scope = scope.by_status(params[:status]) if params[:status].present?
    scope = scope.search_ref(params[:q])     if params[:q].present?

    @pagy, @payments = pagy(scope, limit: 25)
    @can_view_pii    = policy(Payment).view_customer_pii?
    @can_export      = policy(Payment).export?
  end
end
