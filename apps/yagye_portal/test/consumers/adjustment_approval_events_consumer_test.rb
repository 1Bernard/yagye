# frozen_string_literal: true

require "test_helper"

class AdjustmentApprovalEventsConsumerTest < ActiveSupport::TestCase
  def base_payload(overrides = {})
    {
      "break_id"       => SecureRandom.uuid,
      "proposed_by"    => "analyst@yagye.com",
      "proposed_at"    => 1.hour.ago.iso8601,
      "proposed_action" => { "action" => "write_off", "amount" => 500 },
      "event_id"       => SecureRandom.uuid
    }.merge(overrides)
  end

  def consume(payload)
    AdjustmentApprovalEventsConsumer.new.send(:upsert, payload)
  end

  # ── Creates a new record ──────────────────────────────────────────────────

  test "creates a PortalAdjustmentApproval when none exists" do
    payload = base_payload
    assert_difference "PortalAdjustmentApproval.count", 1 do
      consume(payload)
    end
    a = PortalAdjustmentApproval.find_by!(core_break_id: payload["break_id"])
    assert_equal "analyst@yagye.com",               a.proposed_by
    assert_equal "pending",                         a.state
    assert_equal({ "action" => "write_off", "amount" => 500 }, a.proposed_action)
  end

  # ── Updates an existing record ────────────────────────────────────────────

  test "updates existing PortalAdjustmentApproval without creating a duplicate" do
    break_id = SecureRandom.uuid
    approval = create(:portal_adjustment_approval, core_break_id: break_id, state: "pending")
    payload = base_payload("break_id"    => break_id,
                           "approved_by" => "manager@yagye.com",
                           "approved_at" => Time.current.iso8601,
                           "event_id"    => SecureRandom.uuid)

    assert_no_difference "PortalAdjustmentApproval.count" do
      consume(payload)
    end
    assert_equal "approved",          approval.reload.state
    assert_equal "manager@yagye.com", approval.approved_by
  end

  # ── Invalid payload ───────────────────────────────────────────────────────

  test "skips processing when break_id is missing" do
    assert_no_difference "PortalAdjustmentApproval.count" do
      consume(base_payload.except("break_id"))
    end
  end

  test "skips processing when break_id is blank" do
    assert_no_difference "PortalAdjustmentApproval.count" do
      consume(base_payload("break_id" => ""))
    end
  end

  # ── Stale event deduplication ─────────────────────────────────────────────

  test "skips a duplicate event with the same event_id" do
    event_id = SecureRandom.uuid
    break_id = SecureRandom.uuid
    approval = create(:portal_adjustment_approval, core_break_id: break_id,
                      state: "pending", last_event_id: event_id)
    consume(base_payload("break_id"    => break_id,
                         "approved_by" => "manager@yagye.com",
                         "event_id"    => event_id))
    assert_equal "pending", approval.reload.state
  end

  # ── State derivation ──────────────────────────────────────────────────────

  test "state is pending when neither approved_by nor rejected_reason is present" do
    payload = base_payload
    consume(payload)
    a = PortalAdjustmentApproval.find_by!(core_break_id: payload["break_id"])
    assert_equal "pending", a.state
  end

  test "state is approved when approved_by is present" do
    payload = base_payload("approved_by" => "manager@yagye.com",
                           "approved_at" => Time.current.iso8601)
    consume(payload)
    a = PortalAdjustmentApproval.find_by!(core_break_id: payload["break_id"])
    assert_equal "approved", a.state
    assert_equal "manager@yagye.com", a.approved_by
  end

  test "state is rejected when rejected_reason is present and approved_by is absent" do
    payload = base_payload("rejected_reason" => "Amount not verified")
    consume(payload)
    a = PortalAdjustmentApproval.find_by!(core_break_id: payload["break_id"])
    assert_equal "rejected",              a.state
    assert_equal "Amount not verified",   a.rejected_reason
  end

  test "approved takes precedence over rejected_reason when both are present" do
    # Defensive: Core should never send both, but the ACL prefers approved_by.
    payload = base_payload("approved_by"     => "manager@yagye.com",
                           "rejected_reason" => "Should not matter")
    consume(payload)
    a = PortalAdjustmentApproval.find_by!(core_break_id: payload["break_id"])
    assert_equal "approved", a.state
  end

  # ── proposed_action defaults ──────────────────────────────────────────────

  test "proposed_action defaults to empty hash when absent" do
    payload = base_payload.except("proposed_action")
    consume(payload)
    a = PortalAdjustmentApproval.find_by!(core_break_id: payload["break_id"])
    assert_equal({}, a.proposed_action)
  end

  # ── Full lifecycle: pending → approved ────────────────────────────────────

  test "full lifecycle: record created as pending then updated to approved" do
    break_id    = SecureRandom.uuid
    pending_evt = base_payload("break_id" => break_id)
    consume(pending_evt)
    assert_equal "pending", PortalAdjustmentApproval.find_by!(core_break_id: break_id).state

    approved_evt = base_payload("break_id"    => break_id,
                                "approved_by" => "manager@yagye.com",
                                "approved_at" => Time.current.iso8601,
                                "event_id"    => SecureRandom.uuid)
    consume(approved_evt)
    assert_equal "approved", PortalAdjustmentApproval.find_by!(core_break_id: break_id).state
  end

  # ── Full lifecycle: pending → rejected ────────────────────────────────────

  test "full lifecycle: record created as pending then updated to rejected" do
    break_id    = SecureRandom.uuid
    consume(base_payload("break_id" => break_id))

    rejected_evt = base_payload("break_id"        => break_id,
                                "rejected_reason"  => "Insufficient documentation",
                                "event_id"         => SecureRandom.uuid)
    consume(rejected_evt)
    a = PortalAdjustmentApproval.find_by!(core_break_id: break_id)
    assert_equal "rejected",                    a.state
    assert_equal "Insufficient documentation",  a.rejected_reason
  end
end
