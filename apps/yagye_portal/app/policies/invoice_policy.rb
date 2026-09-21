# frozen_string_literal: true

class InvoicePolicy < ApplicationPolicy
  def index?  = !user.internal_staff?
  def show?   = !user.internal_staff?
  def new?    = !user.internal_staff?
  def create? = !user.internal_staff?
  def update? = !user.internal_staff?
  def issue?  = !user.internal_staff?
  def void?   = !user.internal_staff?
end
