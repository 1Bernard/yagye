class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "Yagye <noreply@yagye.com>")
  layout "mailer"
end
