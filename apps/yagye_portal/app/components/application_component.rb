class ApplicationComponent < Phlex::HTML
  include Phlex::Rails::Helpers::Routes
  include Phlex::Rails::Helpers::Translate
  include Phlex::Rails::Helpers::T
  include Phlex::Rails::Helpers::LinkTo
  include Phlex::Rails::Helpers::ContentFor
  include Phlex::Rails::Helpers::TurboFrameTag
  include Phlex::Rails::Helpers::TurboStreamFrom
  include Pundit::Authorization

  private

  def can?(action, subject)
    policy = Pundit.policy(Current.user, subject)
    policy.public_send(:"#{action}?")
  rescue Pundit::NotDefinedError
    false
  end

  def vanish = nil

  # Output a trusted SVG string without HTML-escaping.
  # Use only with literals or known-safe strings — never with user input.
  def svg(content)
    raw safe(content.to_s)
  end
end
