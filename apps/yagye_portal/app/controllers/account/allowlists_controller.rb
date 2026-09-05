# frozen_string_literal: true

module Account
  class AllowlistsController < ApplicationController
    def create_ip
      entry = PortalIpAllowlist.new(
        merchant_code: Current.user.merchant_code,
        cidr:          params[:cidr].to_s.strip,
        label:         params[:label].to_s.strip.presence,
        created_by:    Current.user.email
      )
      authorize entry, policy_class: PortalIpAllowlistPolicy
      if entry.save
        UserAuditEvents::Record.call(user: current_user, event_type: :ip_allowlisted, request: request,
                                     metadata: { cidr: entry.cidr })
        redirect_to settings_path(tab: "allowlists"), notice: "IP address added to allowlist."
      else
        redirect_to settings_path(tab: "allowlists"), alert: entry.errors.full_messages.to_sentence
      end
    end

    def destroy_ip
      entry = decode_id(PortalIpAllowlist)
      authorize entry, policy_class: PortalIpAllowlistPolicy
      cidr = entry.cidr
      entry.destroy
      UserAuditEvents::Record.call(user: current_user, event_type: :ip_removed, request: request,
                                   metadata: { cidr: cidr })
      redirect_to settings_path(tab: "allowlists"), notice: "IP address removed."
    end

    def create_msisdn
      entry = PortalMsisdnAllowlist.new(
        merchant_code: Current.user.merchant_code,
        msisdn:        params[:msisdn].to_s.strip,
        label:         params[:label].to_s.strip.presence,
        created_by:    Current.user.email
      )
      authorize entry, policy_class: PortalMsisdnAllowlistPolicy
      if entry.save
        UserAuditEvents::Record.call(user: current_user, event_type: :msisdn_allowlisted, request: request,
                                     metadata: { msisdn: entry.msisdn })
        redirect_to settings_path(tab: "allowlists"), notice: "Phone number added to allowlist."
      else
        redirect_to settings_path(tab: "allowlists"), alert: entry.errors.full_messages.to_sentence
      end
    end

    def destroy_msisdn
      entry = decode_id(PortalMsisdnAllowlist)
      authorize entry, policy_class: PortalMsisdnAllowlistPolicy
      msisdn = entry.msisdn
      entry.destroy
      UserAuditEvents::Record.call(user: current_user, event_type: :msisdn_removed, request: request,
                                   metadata: { msisdn: msisdn })
      redirect_to settings_path(tab: "allowlists"), notice: "Phone number removed."
    end
  end
end
