# frozen_string_literal: true

class ReservePolicyMailer < ApplicationMailer
  def merchant_notification(merchant_email:, merchant_name:, policy:, auto_activates_at:)
    @merchant_name     = merchant_name
    @policy            = policy
    @auto_activates_at = auto_activates_at
    @kind_label        = kind_label(policy["kind"])
    @rate_display      = rate_display(policy)
    @hold_days         = policy["hold_days"] || 90
    @portal_url        = ENV.fetch("PORTAL_BASE_URL", "http://localhost:3000")

    mail(
      to:      merchant_email,
      subject: "Important: A reserve policy has been applied to your Yagye account"
    )
  end

  private

  def kind_label(kind)
    case kind
    when "rolling" then "Rolling reserve"
    when "fixed"   then "Fixed reserve"
    when "ad_hoc"  then "Ad hoc reserve"
    else kind.to_s.humanize
    end
  end

  def rate_display(policy)
    if policy["kind"] == "rolling"
      "#{(policy["percentage_bps"].to_f / 100).round(2)}% of each settlement"
    elsif policy["kind"] == "fixed"
      "#{policy["currency"]} #{sprintf('%.2f', policy["fixed_amount"].to_f / 100)} per payment"
    else
      "As specified by Yagye"
    end
  end
end
