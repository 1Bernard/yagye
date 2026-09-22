# frozen_string_literal: true

require "test_helper"

class PortalMsisdnAllowlistTest < ActiveSupport::TestCase
  # ── scope: kept ─────────────────────────────────────────────────────────────

  test "kept scope includes active entries" do
    entry = create(:portal_msisdn_allowlist, deleted_at: nil)
    assert_includes PortalMsisdnAllowlist.kept, entry
  end

  test "kept scope excludes soft-deleted entries" do
    entry = create(:portal_msisdn_allowlist, deleted_at: 1.hour.ago)
    refute_includes PortalMsisdnAllowlist.kept, entry
  end

  # ── scope: for_merchant ─────────────────────────────────────────────────────

  test "for_merchant returns only entries for that merchant" do
    mine  = create(:portal_msisdn_allowlist, merchant_code: "MCH-A")
    other = create(:portal_msisdn_allowlist, merchant_code: "MCH-B")
    assert_includes     PortalMsisdnAllowlist.for_merchant("MCH-A"), mine
    refute_includes     PortalMsisdnAllowlist.for_merchant("MCH-A"), other
  end

  # ── soft_delete! ────────────────────────────────────────────────────────────

  test "soft_delete! sets deleted_at and retains the row" do
    entry = create(:portal_msisdn_allowlist)
    assert_nil entry.deleted_at

    entry.soft_delete!

    assert_not_nil entry.reload.deleted_at
    assert PortalMsisdnAllowlist.exists?(entry.id)
    refute_includes PortalMsisdnAllowlist.kept, entry
  end

  test "soft_delete! is idempotent — calling twice does not raise" do
    entry = create(:portal_msisdn_allowlist)
    entry.soft_delete!
    assert_nothing_raised { entry.soft_delete! }
  end

  # ── uniqueness: active entries only ─────────────────────────────────────────

  test "duplicate MSISDN within the same merchant is invalid" do
    create(:portal_msisdn_allowlist, merchant_code: "MCH-A", msisdn: "233241000001")
    duplicate = build(:portal_msisdn_allowlist, merchant_code: "MCH-A", msisdn: "233241000001")
    refute duplicate.valid?
    assert_includes duplicate.errors[:msisdn], "is already in your MSISDN allowlist"
  end

  test "same MSISDN is valid for a different merchant" do
    create(:portal_msisdn_allowlist, merchant_code: "MCH-A", msisdn: "233241000001")
    other = build(:portal_msisdn_allowlist, merchant_code: "MCH-B", msisdn: "233241000001")
    assert other.valid?
  end

  test "re-adding a soft-deleted MSISDN creates a new active entry" do
    original = create(:portal_msisdn_allowlist, merchant_code: "MCH-A", msisdn: "233241000001")
    original.soft_delete!

    refute_includes PortalMsisdnAllowlist.kept.for_merchant("MCH-A"), original

    readded = build(:portal_msisdn_allowlist, merchant_code: "MCH-A", msisdn: "233241000001")
    assert readded.valid?
    readded.save!

    active = PortalMsisdnAllowlist.kept.for_merchant("MCH-A").where(msisdn: "233241000001")
    assert_equal 1, active.count
  end

  test "soft-deleted entry is excluded from uniqueness check — original DB row persists" do
    original = create(:portal_msisdn_allowlist, merchant_code: "MCH-A", msisdn: "233241000001")
    original.soft_delete!
    create(:portal_msisdn_allowlist, merchant_code: "MCH-A", msisdn: "233241000001")

    all = PortalMsisdnAllowlist.where(merchant_code: "MCH-A", msisdn: "233241000001")
    assert_equal 2, all.count
    assert_equal 1, all.kept.count
  end

  # ── MSISDN format validation ─────────────────────────────────────────────────

  test "accepts a local format number" do
    entry = build(:portal_msisdn_allowlist, msisdn: "0241000001")
    assert entry.valid?
  end

  test "accepts an E.164 number with plus prefix" do
    entry = build(:portal_msisdn_allowlist, msisdn: "+233241000001")
    assert entry.valid?
  end

  test "rejects a non-numeric string" do
    entry = build(:portal_msisdn_allowlist, msisdn: "not-a-number")
    refute entry.valid?
    assert entry.errors[:msisdn].any?
  end

  test "rejects a number shorter than 7 digits" do
    entry = build(:portal_msisdn_allowlist, msisdn: "12345")
    refute entry.valid?
    assert entry.errors[:msisdn].any?
  end
end
