# frozen_string_literal: true

require "test_helper"

class DisputeEventsConsumerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def base_payload(overrides = {})
    {
      "dispute_id"        => "disp_#{SecureRandom.hex(4)}",
      "merchant_code"     => "MCH-0001",
      "reference"         => "DSP-#{SecureRandom.hex(4).upcase}",
      "payment_id"        => "pay_000001",
      "payment_reference" => "PAY-REF-001",
      "amount"            => 5_000,
      "currency"          => "GHS",
      "reason"            => "fraud",
      "status"            => "submitted",
      "customer_msisdn"   => "0241000001",
      "network_deadline"  => 5.days.from_now.iso8601,
      "opened_at"         => Time.current.iso8601,
      "event_id"          => SecureRandom.uuid
    }.merge(overrides)
  end

  def consume(payload)
    event = Acl::CoreDisputeEvent.new(payload)
    DisputeEventsConsumer.new.tap { |c| c.send(:upsert_dispute, event) }
  end

  # Captures what Notifications::DeliveryService.schedule was called with,
  # without touching ActiveJob serialization. Restores the original method even
  # if the block raises, so no test leaks a patched singleton.
  def capture_notification
    captured = nil
    original = Notifications::DeliveryService.method(:schedule)
    Notifications::DeliveryService.define_singleton_method(:schedule) { |**kwargs| captured = kwargs }
    yield
    captured
  ensure
    Notifications::DeliveryService.define_singleton_method(:schedule, original)
  end

  # ── Creates a new record ──────────────────────────────────────────────────

  test "creates a Dispute record when none exists" do
    payload = base_payload
    assert_difference "Dispute.count", 1 do
      consume(payload)
    end
    d = Dispute.find_by!(core_dispute_id: payload["dispute_id"])
    assert_equal "MCH-0001",    d.merchant_code
    assert_equal "fraud",       d.reason
    assert_equal "submitted",   d.status
    assert_equal 5_000,         d.amount
    assert_equal "GHS",         d.currency
    assert_equal "pay_000001",  d.core_payment_id
    assert_equal "0241000001",  d.customer_msisdn
  end

  # ── Updates an existing record ────────────────────────────────────────────

  test "updates existing Dispute without creating a duplicate" do
    dispute = create(:dispute, core_dispute_id: "disp_exist", status: "submitted")
    payload = base_payload("dispute_id" => "disp_exist", "status" => "under_review",
                           "event_id"   => SecureRandom.uuid)

    assert_no_difference "Dispute.count" do
      consume(payload)
    end
    assert_equal "under_review", dispute.reload.status
  end

  # ── Invalid payload ───────────────────────────────────────────────────────

  test "CoreDisputeEvent is invalid when dispute_id is missing" do
    event = Acl::CoreDisputeEvent.new(base_payload.except("dispute_id"))
    refute event.valid?
  end

  test "CoreDisputeEvent is invalid when dispute_id is blank" do
    event = Acl::CoreDisputeEvent.new(base_payload("dispute_id" => ""))
    refute event.valid?
  end

  # ── Field defaults ────────────────────────────────────────────────────────

  test "currency defaults to GHS when blank" do
    payload = base_payload("currency" => "")
    consume(payload)
    assert_equal "GHS", Dispute.find_by!(core_dispute_id: payload["dispute_id"]).currency
  end

  test "currency defaults to GHS when key is absent" do
    payload = base_payload.except("currency")
    consume(payload)
    assert_equal "GHS", Dispute.find_by!(core_dispute_id: payload["dispute_id"]).currency
  end

  test "resolved_at is persisted when present" do
    payload = base_payload("status" => "won", "resolved_at" => 1.hour.ago.iso8601)
    consume(payload)
    assert_not_nil Dispute.find_by!(core_dispute_id: payload["dispute_id"]).resolved_at
  end

  test "resolved_at remains nil when absent" do
    payload = base_payload
    consume(payload)
    assert_nil Dispute.find_by!(core_dispute_id: payload["dispute_id"]).resolved_at
  end

  # ── Notifications — dispute_opened ───────────────────────────────────────

  test "schedules dispute_opened notification when status is open" do
    notif = capture_notification { consume(base_payload("status" => "open")) }
    assert_equal "dispute_opened", notif[:event_type]
  end

  test "dispute_opened notification urgency is critical" do
    notif = capture_notification { consume(base_payload("status" => "open")) }
    assert_equal "critical", notif[:urgency]
  end

  test "dispute_opened notification carries the correct merchant_code" do
    notif = capture_notification do
      consume(base_payload("status" => "open", "merchant_code" => "MCH-NOTIF"))
    end
    assert_equal "MCH-NOTIF", notif[:merchant_code]
  end

  test "dispute_opened body includes formatted amount and reference" do
    notif = capture_notification do
      consume(base_payload("status"    => "open",
                           "amount"    => 5_000,
                           "currency"  => "GHS",
                           "reference" => "DSP-BODY-TEST"))
    end
    assert_match "GHS 50.00",     notif[:body]
    assert_match "DSP-BODY-TEST", notif[:body]
  end

  test "dispute_opened source_event_id is scoped to the event" do
    event_id = "evt-open-#{SecureRandom.hex(4)}"
    notif = capture_notification do
      consume(base_payload("status" => "open", "event_id" => event_id))
    end
    assert_equal "#{event_id}:dispute_opened", notif[:source_event_id]
  end

  # ── Notifications — dispute_resolved ─────────────────────────────────────

  test "schedules dispute_resolved notification when status is resolved" do
    notif = capture_notification do
      consume(base_payload("status" => "resolved", "resolved_at" => Time.current.iso8601))
    end
    assert_equal "dispute_resolved", notif[:event_type]
  end

  test "schedules dispute_resolved notification when status is won" do
    notif = capture_notification do
      consume(base_payload("status" => "won", "resolved_at" => Time.current.iso8601))
    end
    assert_equal "dispute_resolved", notif[:event_type]
  end

  test "schedules dispute_resolved notification when status is lost" do
    notif = capture_notification do
      consume(base_payload("status" => "lost", "resolved_at" => Time.current.iso8601))
    end
    assert_equal "dispute_resolved", notif[:event_type]
  end

  test "dispute_resolved notification urgency is info" do
    notif = capture_notification do
      consume(base_payload("status" => "won", "resolved_at" => Time.current.iso8601))
    end
    assert_equal "info", notif[:urgency]
  end

  test "dispute_resolved body includes reference and status" do
    notif = capture_notification do
      consume(base_payload("status"     => "won",
                           "reference"  => "DSP-RESOLVED",
                           "resolved_at" => Time.current.iso8601))
    end
    assert_match "DSP-RESOLVED", notif[:body]
    assert_match "won",          notif[:body]
  end

  test "dispute_resolved source_event_id is scoped to the event" do
    event_id = "evt-res-#{SecureRandom.hex(4)}"
    notif = capture_notification do
      consume(base_payload("status" => "won", "event_id" => event_id,
                           "resolved_at" => Time.current.iso8601))
    end
    assert_equal "#{event_id}:dispute_resolved", notif[:source_event_id]
  end

  # ── Notifications — statuses that produce no notification ─────────────────

  test "no notification is scheduled for submitted status" do
    notif = capture_notification { consume(base_payload("status" => "submitted")) }
    assert_nil notif
  end

  test "no notification is scheduled for under_review status" do
    notif = capture_notification { consume(base_payload("status" => "under_review")) }
    assert_nil notif
  end

  test "no notification is scheduled for closed status" do
    notif = capture_notification { consume(base_payload("status" => "closed")) }
    assert_nil notif
  end
end
