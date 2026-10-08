# frozen_string_literal: true

module Onboarding
  class VerifyController < ApplicationController
    before_action :ensure_merchant_user

    VALID_STEPS = %w[profile contact settlement documents agreement].freeze

    def index
      authorize :onboarding, :index?
      redirect_to verify_step_path(kyb_progress.current_step.key)
    end

    def show
      authorize :onboarding, :show?
      step = params[:step]
      return redirect_to verify_path unless VALID_STEPS.include?(step)

      render Onboarding::VerifyView.new(step: step, progress: kyb_progress)
    end

    def update_profile
      authorize :onboarding, :update?
      result = CoreApiClient.new.update_kyb_profile(
        merchant_code,
        {
          business_type:     params[:business_type].presence,
          registration_type: params[:registration_type].presence,
          category:          params[:category].presence,
          tin:               params[:tin].presence
        }.compact
      )
      handle_step_result(result, current_step: "profile", next_step: "contact")
    end

    def update_contact
      authorize :onboarding, :update?
      result = CoreApiClient.new.upsert_merchant_contact(merchant_code, contact_params)
      if result.success? && address_params.any?
        CoreApiClient.new.upsert_merchant_address(merchant_code, "office", address_params)
      end
      handle_step_result(result, current_step: "contact", next_step: "settlement")
    end

    def update_settlement
      authorize :onboarding, :update?
      result = CoreApiClient.new.update_settlement_destination(
        merchant_code,
        {
          settlement_msisdn:          params[:settlement_msisdn].presence,
          settlement_bank_code:       params[:settlement_bank_code].presence,
          settlement_account_number:  params[:settlement_account_number].presence,
          settlement_account_name:    params[:settlement_account_name].presence
        }.compact
      )
      handle_step_result(result, current_step: "settlement", next_step: "documents")
    end

    def upload_document
      authorize :onboarding, :create?

      file = params[:document]
      unless file.is_a?(ActionDispatch::Http::UploadedFile)
        return redirect_to verify_step_path("documents"), alert: "Please select a file to upload."
      end

      if file.size > 10.megabytes
        return redirect_to verify_step_path("documents"), alert: "File must be under 10 MB."
      end

      allowed_types = %w[application/pdf image/jpeg image/png image/webp]
      unless allowed_types.include?(file.content_type)
        return redirect_to verify_step_path("documents"),
                           alert: "Unsupported file type. Upload PDF, JPEG, PNG, or WebP."
      end

      # Step 1: request presigned upload URL from Core
      intent = CoreApiClient.new.request_document_upload_intent(
        merchant_code,
        kind:         params[:kind].presence || "id",
        filename:     file.original_filename,
        content_type: file.content_type,
        size_bytes:   file.size,
        uploaded_by:  "merchant:#{current_user.id}",
        label:        params[:label].presence
      )

      unless intent.success?
        return redirect_to verify_step_path("documents"),
                           alert: "Could not initiate upload. Please try again."
      end

      presigned_url = intent.body["presigned_url"]
      document_id   = intent.body["document_id"]

      # Step 2: read file, compute checksum, upload to S3 via presigned PUT URL
      file_content = file.read
      checksum     = Digest::SHA256.hexdigest(file_content)

      begin
        require "net/http"
        require "uri"

        uri  = URI.parse(presigned_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl       = uri.scheme == "https"
        http.read_timeout  = 30
        http.open_timeout  = 10

        req = Net::HTTP::Put.new(uri.request_uri)
        req["Content-Type"]   = file.content_type
        req["Content-Length"] = file_content.bytesize.to_s
        req.body = file_content

        response = http.request(req)

        unless response.is_a?(Net::HTTPSuccess)
          Rails.logger.error("S3 PUT failed: #{response.code} #{response.message}")
          return redirect_to verify_step_path("documents"), alert: "Upload failed. Please try again."
        end
      rescue => e
        Rails.logger.error("S3 upload error: #{e.class} — #{e.message}")
        return redirect_to verify_step_path("documents"), alert: "Upload failed. Please try again."
      end

      # Step 3: confirm upload with Core
      result = CoreApiClient.new.confirm_document_upload(document_id, checksum: checksum)
      handle_step_result(result, current_step: "documents", next_step: "documents")
    end

    def destroy_document
      authorize :onboarding, :create?
      result = CoreApiClient.new.delete_kyb_document(merchant_code, params[:document_id])
      if result.success?
        redirect_to verify_step_path("documents"), notice: "Document removed."
      else
        redirect_to verify_step_path("documents"),
                    alert: result.error_message || "Could not remove document."
      end
    end

    def submit_agreement
      authorize :onboarding, :create?
      result = CoreApiClient.new.accept_service_agreement(
        merchant_code,
        {
          agreement_version:  "v1.0",
          signatory_name:     params[:signatory_name].presence,
          signatory_email:    params[:signatory_email].presence,
          signatory_phone:    params[:signatory_phone].presence,
          signatory_job_title: params[:signatory_job_title].presence,
          ip_address:         request.remote_ip,
          user_agent:         request.user_agent
        }.compact
      )
      if result.success?
        redirect_to verify_step_path("agreement"),
                    notice: "Agreement accepted. Your account is under review — we'll be in touch within 1–3 business days."
      else
        redirect_to verify_step_path("agreement"),
                    alert: result.error_message || "Could not submit agreement."
      end
    end

    # GET /onboarding/kyb-banner — lazy-loaded Turbo Frame from Layout::Shell
    def banner
      skip_authorization
      return head(:no_content) unless current_user&.merchant_user?

      result   = CoreApiClient.new.get_kyb_status(merchant_code)
      progress = KybProgress.new(result.success? ? result.body : {})
      return head(:no_content) if progress.all_complete?

      render Shared::KybBanner.new(progress: progress)
    end

    private

    def kyb_progress
      @kyb_progress ||= begin
        result = CoreApiClient.new.get_kyb_status(merchant_code)
        KybProgress.new(result.success? ? result.body : {})
      end
    end

    def merchant_code = current_user.merchant_code

    def ensure_merchant_user
      redirect_to authenticated_root_path unless current_user&.merchant_user?
    end

    def contact_params
      {
        general_email:     params[:general_email].presence,
        support_email:     params[:support_email].presence,
        disputes_email:    params[:disputes_email].presence,
        phone_number:      params[:phone_number].presence,
        whatsapp_number:   params[:whatsapp_number].presence,
        website_url:       params[:website_url].presence,
        twitter_handle:    params[:twitter_handle].presence,
        facebook_username: params[:facebook_username].presence,
        instagram_handle:  params[:instagram_handle].presence
      }.compact
    end

    def address_params
      {
        country:        params[:country].presence,
        region:         params[:region].presence,
        city:           params[:city].presence,
        street_address: params[:street_address].presence,
        gps_address:    params[:gps_address].presence
      }.compact
    end

    def handle_step_result(result, current_step:, next_step:)
      if result.success?
        redirect_to verify_step_path(next_step), notice: "Saved successfully."
      else
        redirect_to verify_step_path(current_step),
                    alert: result.error_message || "Could not save. Please try again."
      end
    end
  end
end
