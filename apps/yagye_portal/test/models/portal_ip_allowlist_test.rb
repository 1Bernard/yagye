# frozen_string_literal: true

require "test_helper"

class PortalIpAllowlistTest < ActiveSupport::TestCase
  # ── scope: kept ─────────────────────────────────────────────────────────────

  test "kept scope includes active entries" do
    entry = create(:portal_ip_allowlist, deleted_at: nil)
    assert_includes PortalIpAllowlist.kept, entry
  end

  test "kept scope excludes soft-deleted entries" do
    entry = create(:portal_ip_allowlist, deleted_at: 1.hour.ago)
    refute_includes PortalIpAllowlist.kept, entry
  end

  # ── scope: for_merchant ─────────────────────────────────────────────────────

  test "for_merchant returns only entries for that merchant" do
    mine  = create(:portal_ip_allowlist, merchant_code: "MCH-A")
    other = create(:portal_ip_allowlist, merchant_code: "MCH-B")
    assert_includes     PortalIpAllowlist.for_merchant("MCH-A"), mine
    refute_includes     PortalIpAllowlist.for_merchant("MCH-A"), other
  end

  # ── soft_delete! ────────────────────────────────────────────────────────────

  test "soft_delete! sets deleted_at and retains the row" do
    entry = create(:portal_ip_allowlist)
    assert_nil entry.deleted_at

    entry.soft_delete!

    assert_not_nil entry.reload.deleted_at
    # Row is still in the database — only excluded from kept scope
    assert PortalIpAllowlist.exists?(entry.id)
    refute_includes PortalIpAllowlist.kept, entry
  end

  test "soft_delete! is idempotent — calling twice does not raise" do
    entry = create(:portal_ip_allowlist)
    entry.soft_delete!
    assert_nothing_raised { entry.soft_delete! }
  end

  # ── uniqueness: active entries only ─────────────────────────────────────────

  test "duplicate CIDR within the same merchant is invalid" do
    create(:portal_ip_allowlist, merchant_code: "MCH-A", cidr: "192.168.1.1")
    duplicate = build(:portal_ip_allowlist, merchant_code: "MCH-A", cidr: "192.168.1.1")
    refute duplicate.valid?
    assert_includes duplicate.errors[:cidr], "is already in your IP allowlist"
  end

  test "same CIDR is valid for a different merchant" do
    create(:portal_ip_allowlist, merchant_code: "MCH-A", cidr: "192.168.1.1")
    other = build(:portal_ip_allowlist, merchant_code: "MCH-B", cidr: "192.168.1.1")
    assert other.valid?
  end

  test "re-adding a soft-deleted CIDR creates a new active entry" do
    original = create(:portal_ip_allowlist, merchant_code: "MCH-A", cidr: "10.0.0.1")
    original.soft_delete!

    # Original is gone from the kept scope
    refute_includes PortalIpAllowlist.kept.for_merchant("MCH-A"), original

    # New entry with the same CIDR is valid — uniqueness only checks active rows
    readded = build(:portal_ip_allowlist, merchant_code: "MCH-A", cidr: "10.0.0.1")
    assert readded.valid?
    readded.save!

    active = PortalIpAllowlist.kept.for_merchant("MCH-A").where(cidr: "10.0.0.1")
    assert_equal 1, active.count
  end

  test "soft-deleted entry is excluded from uniqueness check — original DB row persists" do
    original = create(:portal_ip_allowlist, merchant_code: "MCH-A", cidr: "10.0.0.1")
    original.soft_delete!
    create(:portal_ip_allowlist, merchant_code: "MCH-A", cidr: "10.0.0.1")

    # Two rows in the table: one soft-deleted, one active
    all = PortalIpAllowlist.where(merchant_code: "MCH-A", cidr: "10.0.0.1")
    assert_equal 2, all.count
    assert_equal 1, all.kept.count
  end

  # ── CIDR format validation ───────────────────────────────────────────────────

  test "accepts a bare IPv4 address" do
    entry = build(:portal_ip_allowlist, cidr: "203.0.113.4")
    assert entry.valid?
  end

  test "accepts a CIDR range" do
    entry = build(:portal_ip_allowlist, cidr: "10.0.0.0/24")
    assert entry.valid?
  end

  test "rejects a non-IP string" do
    entry = build(:portal_ip_allowlist, cidr: "not-an-ip")
    refute entry.valid?
    assert entry.errors[:cidr].any?
  end
end
