# frozen_string_literal: true

class PayoutLedgerAuditPolicy < ApplicationPolicy
  def index? = internal_staff?
end
