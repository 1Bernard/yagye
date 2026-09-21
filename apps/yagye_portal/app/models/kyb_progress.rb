# frozen_string_literal: true

# Plain Ruby object — wraps the JSON blob from Core's GET /kyb-status endpoint
# and answers step-completion questions without any additional API calls.
class KybProgress
  STEPS = %w[profile contact settlement documents agreement].freeze

  Step = Struct.new(:key, :label, :description, :icon, :complete, keyword_init: true) do
    def incomplete? = !complete
  end

  def initialize(data)
    @data = data.is_a?(Hash) ? data : {}
  end

  def steps
    @steps ||= [
      Step.new(key: "profile",    label: "Business Profile",   description: "Type, category, and TIN",               icon: :building, complete: profile_complete?),
      Step.new(key: "contact",    label: "Contact Details",    description: "Emails, phone, and address",            icon: :mail,     complete: contact_complete?),
      Step.new(key: "settlement", label: "Settlement Account", description: "MoMo number or bank account",           icon: :bank,     complete: settlement_complete?),
      Step.new(key: "documents",  label: "Documents",          description: "Upload required business documents",    icon: :file,     complete: documents_complete?),
      Step.new(key: "agreement",  label: "Service Agreement",  description: "Review and accept the merchant terms",  icon: :check,    complete: agreement_complete?)
    ]
  end

  def current_step   = steps.find(&:incomplete?) || steps.last
  def completed_count = steps.count(&:complete)
  def total_count     = steps.size
  def all_complete?   = steps.all?(&:complete)
  def percent         = (completed_count * 100.0 / total_count).round

  def merchant         = @data["merchant"] || {}
  def contact          = @data["contact"]
  def addresses        = @data["addresses"] || {}
  def office_address   = addresses["office"]
  def registered_address = addresses["registered"]
  def documents        = @data["documents"] || []
  def settlement       = @data["settlement_controls"]
  def agreements       = @data["service_agreements"] || []
  def latest_agreement = agreements.first

  def step_data_for(key)
    case key
    when "profile"    then merchant
    when "contact"    then { "contact" => contact, "office" => office_address, "registered" => registered_address }
    when "settlement" then settlement || {}
    when "documents"  then documents
    when "agreement"  then latest_agreement || {}
    end
  end

  private

  def profile_complete?   = merchant["business_type"].present?
  def contact_complete?   = contact&.dig("general_email").present? || contact&.dig("phone_number").present?
  def settlement_complete? = settlement&.dig("settlement_msisdn").present? || settlement&.dig("settlement_account_number").present?
  def documents_complete? = documents.any? { |d| %w[uploaded approved].include?(d["status"]) }
  def agreement_complete? = agreements.any?
end
