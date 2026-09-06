# frozen_string_literal: true

module Team
  module Roles
    class FormView < ApplicationComponent
      include UI::Theme

      RESOURCE_LABELS = {
        "developers"       => "Developer access",
        "disputes"         => "Disputes",
        "kyb"              => "KYB & compliance",
        "merchants"        => "Merchants",
        "payments"         => "Payments",
        "payouts"          => "Payouts",
        "platform_finance" => "Platform finance",
        "settlements"      => "Settlements",
        "team"             => "Team management"
      }.freeze

      RESOURCE_ICON = {
        "developers"       => :key,
        "disputes"         => :flag,
        "kyb"              => :shield,
        "merchants"        => :building,
        "payments"         => :credit_card,
        "payouts"          => :wallet,
        "platform_finance" => :bank,
        "settlements"      => :trending_up,
        "team"             => :users
      }.freeze

      RESOURCE_COLOR = {
        "developers"       => "icon-brand",
        "disputes"         => "icon-amber",
        "kyb"              => "icon-teal",
        "merchants"        => "icon-purple",
        "payments"         => "icon-green",
        "payouts"          => "icon-green",
        "platform_finance" => "icon-amber",
        "settlements"      => "icon-teal",
        "team"             => "icon-brand"
      }.freeze

      # Which resource groups belong to each scope.
      SCOPE_RESOURCES = {
        "merchant" => %w[developers disputes payments payouts settlements team],
        "internal" => %w[disputes kyb merchants payments payouts platform_finance settlements team]
      }.freeze

      def initialize(role:, permissions:, mode:, errors: [])
        @role        = role
        @permissions = permissions
        @mode        = mode
        @errors      = errors
        @editing     = mode == :edit
        @locked      = @editing && @role.system_role?
      end

      def view_template
        turbo_frame_tag "drawer-frame" do
          perm_style
          drawer_header
          drawer_body
          drawer_footer
        end
      end

      private

      def form_action_url = @editing ? team_role_path(@role.key) : team_roles_path
      def form_method     = @editing ? "patch" : "post"
      def drawer_title    = @editing ? @role.name : "New role"

      # ── Scoped CSS ────────────────────────────────────────────────────────────

      def perm_style
        style do
          plain <<~CSS
            .perm-row { transition: background 0.1s; }
            .perm-row:hover { background: rgba(0,0,0,0.025); }
            .perm-row:has(input:checked) { background: rgba(61,71,245,0.04); }
            .perm-dot { display: none; }
            .perm-row:has(input:checked) .perm-dot { display: flex; }
            .perm-row:has(input:checked) .perm-ring { background:#3D47F5; border-color:#3D47F5; }
            .perm-row:has(input:checked) .perm-label { color:var(--ink); font-weight:600; }
          CSS
        end
      end

      # ── Header ────────────────────────────────────────────────────────────────

      def drawer_header
        div(class: DRAWER_HEAD) do
          div(class: "flex items-center gap-3 min-w-0") do
            div(class: "w-8 h-8 rounded-lg icon-brand flex items-center justify-center flex-shrink-0") do
              span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(:key, class: "w-full h-full") }
            end
            div(class: "min-w-0") do
              p(class: TYPE_MICRO) { plain @editing ? "Edit role" : "New role" }
              p(class: "text-[14px] font-semibold truncate", style: "color:var(--ink)") do
                plain drawer_title
              end
            end
          end
          button(type: "button", class: XBTN, data: { action: "click->drawer#close" }) do
            render UI::Icon.new(:x, class: ICON_SM)
          end
        end
      end

      # ── Body ─────────────────────────────────────────────────────────────────

      def drawer_body
        div(class: "flex-1 min-h-0 overflow-y-auto flex flex-col",
            **(@locked ? {} : { data: { controller: "role-scope" } })) do
          # Banners
          div(class: "px-6 pt-5 flex flex-col gap-3") do
            error_banner  if @errors.any?
            system_notice if @locked
          end

          # Form fields
          form(action: form_action_url, method: "post", id: "role-form",
               class: "px-6 py-5 flex flex-col gap-4 border-b border-gray-100") do
            input(type: "hidden", name: "_method",            value: form_method) if @editing
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            input(type: "hidden", name: "key",   value: @role.key)    if @locked
            input(type: "hidden", name: "scope",  value: @role.scope) if @locked

            div(class: "grid grid-cols-2 gap-4") do
              field("Role name", "name", @role.name, required: true, readonly: @locked)
              field("Key", "key", @role.key,
                    placeholder: "e.g. merchant_analyst",
                    required: !@editing, readonly: @locked || @editing,
                    hint: @editing ? nil : "Lowercase + underscores only. Fixed after creation.",
                    mono: true)
            end

            unless @locked
              div do
                label(class: "#{TEXT_LABEL} mb-1.5 block", for: "role_scope") { plain "Scope" }
                select(id: "role_scope", name: "scope", required: true, class: INPUT_FIELD,
                       data: { role_scope_target: "select", action: "change->role-scope#filter" }) do
                  option(value: "", selected: @role.scope.blank?) { plain "Choose scope…" }
                  option(value: "merchant", selected: @role.scope == "merchant") do
                    plain "Merchant — assigned to merchant users"
                  end
                  option(value: "internal", selected: @role.scope == "internal") do
                    plain "Internal — assigned to Yagye staff"
                  end
                end
              end
            end

            div do
              label(class: "#{TEXT_LABEL} mb-1.5 block", for: "role_description") { plain "Description" }
              textarea(id: "role_description", name: "description", rows: "2", required: true,
                       class: "#{INPUT_FIELD} resize-none leading-[1.5]") do
                plain @role.description.to_s
              end
            end
          end

          # Permissions
          permissions_section
        end
      end

      # ── Footer ────────────────────────────────────────────────────────────────

      def drawer_footer
        div(class: "sticky bottom-0 bg-white border-t border-gray-100 px-6 py-4 flex items-center gap-3") do
          render UI::Button.new(variant: :primary, type: "submit", form: "role-form") do
            render UI::Icon.new(@editing ? :check : :plus, class: ICON_SM)
            plain @editing ? "Save changes" : "Create role"
          end
          button(type: "button", class: "text-[12.5px] font-medium #{LINK_MUTED}",
                 data: { action: "click->drawer#close" }) do
            plain "Cancel"
          end
        end
      end

      # ── Banners ───────────────────────────────────────────────────────────────

      def error_banner
        render UI::Notice.new(variant: :error, title: "Please fix the following:") do
          div(class: "mt-1 flex flex-col gap-[2px]") do
            @errors.each { |e| p(class: "text-[11.5px]", style: "color:var(--muted-text)") { plain e } }
          end
        end
      end

      def system_notice
        render UI::Notice.new(
          variant:     :warning,
          title:       "System role — partially locked",
          body:        "The key, name, and scope are fixed. You can edit the description and adjust permissions.",
          dismissable: true
        )
      end

      # ── Form field helper ─────────────────────────────────────────────────────

      def field(label, name, value, required: false, readonly: false,
                placeholder: nil, hint: nil, mono: false)
        div do
          label(class: "#{TEXT_LABEL} mb-1.5 block", for: "role_#{name}") { plain label }
          input(id: "role_#{name}", name: name, type: "text", value: value,
                placeholder: placeholder, required: required, readonly: readonly,
                class: [ INPUT_FIELD,
                        mono ? "font-mono text-[12.5px]" : nil,
                        readonly ? "opacity-60 cursor-not-allowed" : nil ].compact.join(" "))
          p(class: "#{TYPE_CAPTION} mt-1.5") { plain hint } if hint
        end
      end

      # ── Permissions ───────────────────────────────────────────────────────────

      def permissions_section
        current_keys = @editing ? @role.permissions.map(&:key) : []
        grouped      = @permissions.group_by(&:resource)

        if @locked && @role.scope.present?
          allowed = SCOPE_RESOURCES.fetch(@role.scope, grouped.keys)
          grouped = grouped.select { |r, _| allowed.include?(r) }
        end

        total = grouped.values.sum(&:size)

        div do
          # Section heading
          div(class: "flex items-center justify-between px-6 py-4 border-b border-gray-100") do
            p(class: "text-[13px] font-semibold", style: "color:var(--ink)") { plain "Permissions" }
            span(class: "badge-gray text-[11px] font-semibold px-[10px] py-[3px] rounded-full",
                 **(@locked ? {} : { data: { role_scope_target: "permCount" } })) do
              plain "#{total} available"
            end
          end

          # Resource groups — single column, stacked
          grouped.each do |resource, perms|
            resource_group(resource, perms, current_keys)
          end
        end
      end

      def resource_group(resource, perms, current_keys)
        icon_name = RESOURCE_ICON.fetch(resource, :key)
        color_cls = RESOURCE_COLOR.fetch(resource, "icon-brand")
        label_str = RESOURCE_LABELS.fetch(resource, resource.gsub("_", " ").capitalize)

        group_data = @locked ? {} : {
          role_scope_target: "card",
          resource:          resource,
          perm_count:        perms.size.to_s
        }

        div(class: "border-b border-gray-100 last:border-0", data: group_data) do
          # Group header
          div(class: "flex items-center gap-3 px-6 py-[11px] bg-gray-50/70") do
            div(class: "w-6 h-6 rounded-md #{color_cls} flex items-center justify-center flex-shrink-0") do
              span(class: "flex w-[11px] h-[11px]") do
                render UI::Icon.new(icon_name, class: "w-full h-full")
              end
            end
            p(class: "flex-1 text-[12px] font-semibold", style: "color:var(--ink)") { plain label_str }
            span(class: "badge-gray text-[10px] font-semibold px-[7px] py-[2px] rounded-full") do
              plain "#{perms.size}"
            end
          end

          # Permission rows
          perms.each do |perm|
            checked = current_keys.include?(perm.key)
            label(class: "perm-row flex items-center gap-3 px-6 py-[10px] cursor-pointer " \
                         "border-t border-gray-100/60",
                  form: "role-form") do
              input(type: "checkbox", name: "permission_keys[]", value: perm.key,
                    checked: checked, class: "sr-only")
              div(class: "perm-ring flex-shrink-0 w-[16px] h-[16px] rounded-full border-2 " \
                         "border-gray-300 flex items-center justify-center transition-all") do
                span(class: "perm-dot w-[7px] h-[7px] text-white") do
                  render UI::Icon.new(:check, class: "w-full h-full")
                end
              end
              div(class: "flex-1 min-w-0") do
                p(class: "perm-label text-[12.5px] font-medium leading-tight",
                  style: "color:var(--body-text)") do
                  plain perm.action.gsub("_", " ").capitalize
                end
                p(class: "text-[11px] leading-[1.4] mt-[2px]", style: "color:var(--muted-text)") do
                  plain perm.description
                end
              end
            end
          end
        end
      end
    end
  end
end
