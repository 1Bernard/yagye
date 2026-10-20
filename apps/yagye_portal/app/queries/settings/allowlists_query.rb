# frozen_string_literal: true

module Settings
  # Loads all allowlist/blocklist collections for a merchant's settings page.
  # Returns a hash with five keys: :ip_allowlists, :ip_blocklists,
  # :msisdn_allowlists, :msisdn_blocklists, :email_blocklists.
  class AllowlistsQuery
    def initialize(merchant_code)
      @merchant_code = merchant_code
    end

    def call
      mc = @merchant_code
      {
        ip_allowlists:     PortalIpAllowlist.kept.for_merchant(mc).order(:created_at),
        ip_blocklists:     PortalIpBlocklist.kept.for_merchant(mc).order(:created_at),
        msisdn_allowlists: PortalMsisdnAllowlist.kept.for_merchant(mc).order(:created_at),
        msisdn_blocklists: PortalMsisdnBlocklist.kept.for_merchant(mc).order(:created_at),
        email_blocklists:  PortalEmailBlocklist.kept.for_merchant(mc).order(:created_at)
      }
    end
  end
end
