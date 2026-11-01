# frozen_string_literal: true

module Account
  class SplitRulesController < ApplicationController
    def index
      authorize :split_rules, :index?
      result = core.list_split_rules(merchant_code: current_user.merchant_code)
      rules  = result.success? ? Array(result.body["data"]) : []
      render Account::SplitRules::IndexView.new(rules: rules)
    end

    def new
      authorize :split_rules, :create?
      render Account::SplitRules::FormView.new(mode: Current.mode)
    end

    def create
      authorize :split_rules, :create?

      legs = parse_legs
      if legs.empty?
        return render Account::SplitRules::FormView.new(
          mode: Current.mode, errors: [ "Add at least one leg." ]
        ), status: :unprocessable_entity
      end

      result = core.create_split_rule(
        merchant_code: current_user.merchant_code,
        name:          params[:name].to_s.strip,
        legs:          legs
      )

      if result.success?
        redirect_to split_rules_path, notice: "Split rule created."
      else
        render Account::SplitRules::FormView.new(
          mode: Current.mode, errors: [ result.error_message || "Could not create split rule." ]
        ), status: :unprocessable_entity
      end
    end

    def show
      authorize :split_rules, :index?
      result = core.get_split_rule(params[:id])
      return redirect_to split_rules_path, alert: "Split rule not found." unless result.success?

      render Account::SplitRules::ShowView.new(rule: result.body)
    end

    def deactivate
      authorize :split_rules, :deactivate?
      result = core.deactivate_split_rule(params[:id])
      if result.success?
        redirect_to split_rule_path(params[:id]), notice: "Split rule deactivated."
      else
        redirect_to split_rule_path(params[:id]), alert: result.error_message || "Could not deactivate."
      end
    end

    private

    def parse_legs
      raw = params[:legs]
      return [] unless raw.is_a?(Array) || raw.is_a?(ActionController::Parameters)

      Array(raw).filter_map do |leg|
        recipient  = leg[:recipient_merchant_code].to_s.strip
        split_type = leg[:split_type].presence_in(%w[percentage flat])
        value_raw  = leg[:value].to_s.strip
        next if recipient.blank? || split_type.nil? || value_raw.blank?

        value = split_type == "percentage" ? (value_raw.to_f * 100).round : (value_raw.to_f * 100).round
        { recipient_merchant_code: recipient, split_type: split_type, value: value }
      end
    end

    def core
      @core ||= CoreApiClient.new
    end
  end
end
