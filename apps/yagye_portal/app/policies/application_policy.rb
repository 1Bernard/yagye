class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user   = user
    @record = record
  end

  def index?   = false
  def show?    = false
  def create?  = false
  def new?     = create?
  def update?  = false
  def edit?    = update?
  def destroy? = false

  class Scope
    def initialize(user, scope)
      @user  = user
      @scope = scope
    end

    def resolve
      raise NotImplementedError, "#{self.class}#resolve is not implemented"
    end

    private

    attr_reader :user, :scope
  end

  private

  # Dynamic permission gate — delegates to User#permitted? which queries
  # the role_permissions join. Results are cached per-request; no N+1.
  def permitted?(permission_key)
    user.present? && user.permitted?(permission_key)
  end

  def internal_staff?
    user&.internal_staff?
  end

  def merchant_user?
    user&.merchant_user?
  end
end
