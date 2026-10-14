# frozen_string_literal: true

module PricingPlans
  class PricingPlansController < ApplicationController
    def index
      authorize :pricing_plans, :index?
      result = CoreApiClient.new.list_pricing_plans
      plans  = result.success? ? (result.body["data"] || []) : []
      render PricingPlans::IndexView.new(plans: plans)
    end

    def new
      authorize :pricing_plans, :create?
      render PricingPlans::NewView.new
    end

    def create
      authorize :pricing_plans, :create?
      attrs = plan_params

      result = CoreApiClient.new.create_pricing_plan(attrs)
      if result.success?
        redirect_to pricing_plan_path(result.body["id"]), notice: "Pricing plan created."
      else
        errors = result.body&.dig("details") || {}
        render PricingPlans::NewView.new(errors: errors, params: attrs), status: :unprocessable_entity
      end
    end

    def show
      authorize :pricing_plans, :show?
      result = CoreApiClient.new.get_pricing_plan(params[:id])
      return redirect_to pricing_plans_path, alert: "Plan not found." unless result.success?

      render PricingPlans::ShowView.new(plan: result.body)
    end

    def create_rule
      authorize :pricing_plans, :update?
      plan_id = params[:id]
      attrs   = rule_params

      result = CoreApiClient.new.create_pricing_rule(plan_id, attrs)
      if result.success?
        redirect_to pricing_plan_path(plan_id), notice: "Rule added."
      else
        redirect_to pricing_plan_path(plan_id), alert: rule_error_message(result)
      end
    end

    private

    def plan_params
      {
        name:           params[:name].to_s.strip,
        version:        params[:version].to_s.strip,
        currency:       params[:currency].to_s.strip.upcase,
        fee_mode:       params[:fee_mode].to_s.strip,
        monthly_fee:    params[:monthly_fee].presence&.to_i || 0,
        effective_from: params[:effective_from].presence
      }.compact
    end

    def rule_params
      pct_str = params[:percentage_pct].to_s.strip
      pct_bps = pct_str.blank? ? nil : (pct_str.to_f * 100).round

      {
        method:         params[:method].presence,
        provider_code:  params[:provider_code].presence,
        percentage_bps: pct_bps,
        fixed_amount:   params[:fixed_amount].presence&.then { |v| (v.to_f * 100).round },
        minimum_fee:    params[:minimum_fee].presence&.then { |v| (v.to_f * 100).round },
        maximum_fee:    params[:maximum_fee].presence&.then { |v| (v.to_f * 100).round }
      }.compact
    end

    def rule_error_message(result)
      details = result.body&.dig("details")
      return "Could not add rule." unless details

      details.flat_map { |field, msgs| msgs.map { |m| "#{field.humanize}: #{m}" } }.first || "Could not add rule."
    end
  end
end
