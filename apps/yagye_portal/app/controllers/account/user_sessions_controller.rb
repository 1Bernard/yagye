# frozen_string_literal: true

module Account
  class UserSessionsController < ApplicationController
    # DELETE /settings/sessions/:id — revoke a single session
    def revoke
      authorize :settings, :update?

      session_record = current_user.user_sessions.find_by(id: params[:id])

      if session_record && !current_session?(session_record)
        session_record.revoke!
        redirect_to settings_path(tab: "security"), notice: "Session revoked."
      else
        redirect_to settings_path(tab: "security"), alert: "Could not revoke session."
      end
    end

    # DELETE /settings/sessions — revoke all sessions except the current one
    def revoke_all
      authorize :settings, :update?

      raw_token = session[:user_session_token]
      current_digest = raw_token.present? ? Digest::SHA256.hexdigest(raw_token) : nil

      revoked = current_user.user_sessions
        .active
        .where.not(session_token_digest: current_digest)
        .each(&:revoke!)

      redirect_to settings_path(tab: "security"),
                  notice: "#{revoked.size} other session(s) signed out."
    end

    private

    def current_session?(session_record)
      raw_token = session[:user_session_token]
      return false unless raw_token.present?

      Digest::SHA256.hexdigest(raw_token) == session_record.session_token_digest
    end
  end
end
