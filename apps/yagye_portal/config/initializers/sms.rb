# frozen_string_literal: true

Rails.application.config.after_initialize do
  Rails.application.config.sms_adapter =
    Rails.env.test? ? Sms::StubAdapter : Sms::BrevoAdapter
end
