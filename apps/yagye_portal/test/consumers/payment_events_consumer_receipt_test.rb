# frozen_string_literal: true

require "test_helper"

class PaymentEventsConsumerReceiptTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  def base_payload(overrides = {})
    {
      "public_id"        => "pay_receipt_#{SecureRandom.hex(4)}",
      "merchant_code"    => "MCH-0001",
      "state"            => "succeeded",
      "amount"           => 10000,
      "currency"         => "GHS",
      "mode"             => "live",
      "provider"         => "mtn_momo",
      "method"           => "mobile_money",
      "metadata"         => {},
      "customer_msisdn"  => nil,
      "customer_email"   => nil
    }.merge(overrides)
  end

  def consume(payload)
    event = Acl::CorePaymentEvent.new(payload)
    PaymentEventsConsumer.new.send(:upsert_payment, event)
  end

  # ── SMS receipt ───────────────────────────────────────────────────────────────

  test "enqueues SmsNotifierJob when customer_msisdn is present on a paid event" do
    payload = base_payload("customer_msisdn" => "233241000001")
    assert_enqueued_with(job: SmsNotifierJob) do
      consume(payload)
    end
  end

  test "does not enqueue SmsNotifierJob when customer_msisdn is nil" do
    payload = base_payload("customer_msisdn" => nil)
    assert_no_enqueued_jobs(only: SmsNotifierJob) do
      consume(payload)
    end
  end

  test "does not enqueue SmsNotifierJob when customer_msisdn is blank string" do
    payload = base_payload("customer_msisdn" => "")
    assert_no_enqueued_jobs(only: SmsNotifierJob) do
      consume(payload)
    end
  end

  test "SMS content includes amount, ref and receipt URL" do
    public_id = "pay_receipt_abc123ef"
    payload   = base_payload("public_id" => public_id, "customer_msisdn" => "233241000001", "amount" => 5000)
    consume(payload)
    job = enqueued_jobs.find { |j| j[:job] == SmsNotifierJob }
    content = job[:args].first["content"]
    assert_includes content, "GH₵50.00"
    assert_includes content, public_id.last(8).upcase
    assert_includes content, "/r/#{public_id}"
  end

  # ── Email receipt ─────────────────────────────────────────────────────────────

  test "enqueues ReceiptMailer when customer_email is present on a paid event" do
    payload = base_payload("customer_email" => "customer@example.com")
    assert_enqueued_with(job: ActionMailer::MailDeliveryJob) do
      consume(payload)
    end
  end

  test "does not enqueue ReceiptMailer when customer_email is nil" do
    payload = base_payload("customer_email" => nil)
    assert_no_enqueued_jobs(only: ActionMailer::MailDeliveryJob) do
      consume(payload)
    end
  end

  # ── No receipt on non-paid states ────────────────────────────────────────────

  test "does not enqueue SMS receipt for a failed payment" do
    payload = base_payload("state" => "failed", "customer_msisdn" => "233241000001")
    assert_no_enqueued_jobs(only: SmsNotifierJob) do
      consume(payload)
    end
  end

  test "does not enqueue email receipt for a refunded payment" do
    payload = base_payload("state" => "refunded", "customer_email" => "customer@example.com")
    assert_no_enqueued_jobs(only: ActionMailer::MailDeliveryJob) do
      consume(payload)
    end
  end
end
