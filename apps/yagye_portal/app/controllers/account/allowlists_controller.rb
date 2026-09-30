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
      entry.soft_delete!
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
      entry.soft_delete!
      UserAuditEvents::Record.call(user: current_user, event_type: :msisdn_removed, request: request,
                                   metadata: { msisdn: msisdn })
      redirect_to settings_path(tab: "allowlists"), notice: "Phone number removed."
    end

    def create_msisdn_block
      entry = PortalMsisdnBlocklist.new(
        merchant_code: Current.user.merchant_code,
        msisdn:        params[:msisdn].to_s.strip,
        label:         params[:label].to_s.strip.presence,
        reason:        params[:reason].presence_in(PortalMsisdnBlocklist::REASONS),
        created_by:    Current.user.email
      )
      authorize entry, policy_class: PortalMsisdnBlocklistPolicy
      if entry.save
        UserAuditEvents::Record.call(user: current_user, event_type: :msisdn_blocked, request: request,
                                     metadata: { msisdn: entry.msisdn, reason: entry.reason })
        redirect_to settings_path(tab: "allowlists"), notice: "Phone number added to blocklist."
      else
        redirect_to settings_path(tab: "allowlists"), alert: entry.errors.full_messages.to_sentence
      end
    end

    def destroy_msisdn_block
      entry = decode_id(PortalMsisdnBlocklist)
      authorize entry, policy_class: PortalMsisdnBlocklistPolicy
      msisdn = entry.msisdn
      entry.soft_delete!
      UserAuditEvents::Record.call(user: current_user, event_type: :msisdn_unblocked, request: request,
                                   metadata: { msisdn: msisdn })
      redirect_to settings_path(tab: "allowlists"), notice: "Phone number removed from blocklist."
    end

    def create_ip_block
      entry = PortalIpBlocklist.new(
        merchant_code: Current.user.merchant_code,
        cidr:          params[:cidr].to_s.strip,
        label:         params[:label].to_s.strip.presence,
        reason:        params[:reason].presence_in(PortalIpBlocklist::REASONS),
        created_by:    Current.user.email
      )
      authorize entry, policy_class: PortalIpBlocklistPolicy
      if entry.save
        UserAuditEvents::Record.call(user: current_user, event_type: :ip_blocked, request: request,
                                     metadata: { cidr: entry.cidr, reason: entry.reason })
        redirect_to settings_path(tab: "allowlists"), notice: "IP address added to blocklist."
      else
        redirect_to settings_path(tab: "allowlists"), alert: entry.errors.full_messages.to_sentence
      end
    end

    def destroy_ip_block
      entry = decode_id(PortalIpBlocklist)
      authorize entry, policy_class: PortalIpBlocklistPolicy
      cidr = entry.cidr
      entry.soft_delete!
      UserAuditEvents::Record.call(user: current_user, event_type: :ip_unblocked, request: request,
                                   metadata: { cidr: cidr })
      redirect_to settings_path(tab: "allowlists"), notice: "IP address removed from blocklist."
    end

    def create_email_block
      entry = PortalEmailBlocklist.new(
        merchant_code: Current.user.merchant_code,
        email:         params[:email].to_s.strip.downcase,
        label:         params[:label].to_s.strip.presence,
        reason:        params[:reason].presence_in(PortalEmailBlocklist::REASONS),
        created_by:    Current.user.email
      )
      authorize entry, policy_class: PortalEmailBlocklistPolicy
      if entry.save
        UserAuditEvents::Record.call(user: current_user, event_type: :email_blocked, request: request,
                                     metadata: { email: entry.email, reason: entry.reason })
        redirect_to settings_path(tab: "allowlists"), notice: "Email address added to blocklist."
      else
        redirect_to settings_path(tab: "allowlists"), alert: entry.errors.full_messages.to_sentence
      end
    end

    def destroy_email_block
      entry = decode_id(PortalEmailBlocklist)
      authorize entry, policy_class: PortalEmailBlocklistPolicy
      email = entry.email
      entry.soft_delete!
      UserAuditEvents::Record.call(user: current_user, event_type: :email_unblocked, request: request,
                                   metadata: { email: email })
      redirect_to settings_path(tab: "allowlists"), notice: "Email address removed from blocklist."
    end
  end
end
