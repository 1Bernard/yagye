# frozen_string_literal: true

class BankStatementsPolicy < ApplicationPolicy
  def index?  = user.internal_staff?
  def show?   = user.internal_staff?
  def new?    = user.internal_staff?
  def create? = user.internal_staff?
end
