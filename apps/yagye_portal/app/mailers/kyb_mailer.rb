# frozen_string_literal: true

class KybMailer < ApplicationMailer
  def approved(application)
    @application = application
    @legal_name  = application.legal_name
    mail(
      to:      application.submitted_by_email,
      subject: "[Yagye] Your KYB application has been approved"
    )
  end

  def rejected(application, reason: nil)
    @application = application
    @legal_name  = application.legal_name
    @reason      = reason.presence || "No reason provided."
    mail(
      to:      application.submitted_by_email,
      subject: "[Yagye] Your KYB application requires attention"
    )
  end
end
