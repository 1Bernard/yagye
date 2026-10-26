# frozen_string_literal: true

module PricingPlans
  class PricingPlansController < ApplicationController
    def index
      authorize :pricing_plans, :index?
      result    = CoreApiClient.new.list_pricing_plans
      all_plans = result.success? ? (result.body["data"] || []) : []

      stats = {
        total:    all_plans.size,
        active:   all_plans.count { |p| p["status"] == "active" },
        draft:    all_plans.count { |p| p["status"] == "draft" || p["status"].nil? },
        archived: all_plans.count { |p| p["status"] == "archived" }
      }

      tab   = params[:tab].presence_in(%w[all draft active archived]) || "all"
      query = params[:q].presence

      plans = tab == "all" ? all_plans : all_plans.select { |p| (p["status"] || "draft") == tab }
      plans = plans.select { |p| p["name"]&.downcase&.include?(query.downcase) } if query

      render PricingPlans::IndexView.new(plans: plans, tab: tab, query: query, stats: stats)
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

      plan = result.body
      plan["created_by"]   = resolve_user_display(plan["created_by"])
      plan["activated_by"] = resolve_user_display(plan["activated_by"])
      render PricingPlans::ShowView.new(plan: plan)
    end

    def create_rule
      authorize :pricing_plans, :update?
      plan_id = params[:id]
      attrs   = rule_params

      pct   = attrs[:percentage_bps].to_i
      fixed = attrs[:fixed_amount].to_i
      unless pct > 0 || fixed > 0
        return redirect_to pricing_plan_path(plan_id),
                            alert: "A rule needs at least a percentage rate or a fixed fee."
      end

      result = CoreApiClient.new.create_pricing_rule(plan_id, attrs)
      if result.success?
        redirect_to pricing_plan_path(plan_id), notice: "Rule added."
      else
        redirect_to pricing_plan_path(plan_id), alert: rule_error_message(result)
      end
    end

    def activate
      authorize :pricing_plans, :update?
      plan_id = params[:id]

      result = CoreApiClient.new.activate_pricing_plan(plan_id)
      if result.success?
        redirect_to pricing_plan_path(plan_id), notice: "Plan activated."
      else
        details = result.body&.dig("details") || {}
        msg = details.values.flatten.first || "Could not activate plan."
        redirect_to pricing_plan_path(plan_id), alert: msg
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

    def resolve_user_display(user_code)
      return nil if user_code.blank?
      User.find_by(user_code: user_code)&.full_name || user_code
    end

    def rule_error_message(result)
      details = result.body&.dig("details")
      return "Could not add rule." unless details

      details.flat_map { |field, msgs| msgs.map { |m| "#{field.humanize}: #{m}" } }.first || "Could not add rule."
    end
  end
end
