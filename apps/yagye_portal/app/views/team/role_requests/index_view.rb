# frozen_string_literal: true

module Team
  module RoleRequests
    class IndexView < ApplicationComponent
      include UI::Theme

      ROLE_META = (Portal::RoleMetadata::MERCHANT + Portal::RoleMetadata::INTERNAL)
                    .index_by { |r| r[:key] }.freeze

      def initialize(requests:, roles_by_key:)
        @requests     = requests
        @roles_by_key = roles_by_key
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :team_users,
          title:      "Role change requests",
          breadcrumbs: [
            { label: "Team members", url: team_users_path },
            { label: "Role change requests" }
          ]
        ) do
          page_header
          if @requests.empty?
            empty_state
          else
            div(class: "flex flex-col gap-3") do
              @requests.each { |req| request_card(req) }
            end
          end
        end
      end

      private

      def page_header
        div(class: "flex items-center justify-between mb-6") do
          div do
            h1(class: "text-[20px] font-bold tracking-[-0.02em]", style: "color:var(--ink)") do
              plain "Role change requests"
            end
            p(class: TYPE_CAPTION) do
              plain "#{@requests.size} pending #{@requests.size == 1 ? 'request' : 'requests'} require a second approver"
            end
          end
        end
      end

      def empty_state
        div(class: "bg-white border border-gray-100 rounded-2xl px-8 py-14 flex flex-col items-center text-center gap-3") do
          div(class: "w-12 h-12 rounded-2xl icon-brand flex items-center justify-center mb-1") do
            span(class: "flex w-6 h-6") { render UI::Icon.new(:check_circle, class: "w-full h-full") }
          end
          p(class: "text-[15px] font-semibold", style: "color:var(--ink)") { plain "No pending requests" }
          p(class: TYPE_CAPTION) { plain "All role change requests have been reviewed." }
        end
      end

      def request_card(req)
        added   = req.added_keys
        removed = req.removed_keys

        div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
          div(class: "px-6 py-5 flex items-start justify-between gap-4") do
            div(class: "flex items-start gap-4 min-w-0 flex-1") do
              render UI::Avatar.new(initials_for(req.target_user), size: :md)
              div(class: "min-w-0 flex-1") do
                div(class: "flex items-center gap-2 flex-wrap mb-[3px]") do
                  p(class: "text-[14px] font-bold tracking-[-0.01em]", style: "color:var(--ink)") do
                    plain req.target_user.full_name
                  end
                  span(class: "badge-amber text-[10.5px] font-semibold px-2 py-[2px] rounded-full") do
                    plain "Pending approval"
                  end
                end
                p(class: TYPE_CAPTION) do
                  plain "Requested by #{req.requested_by.full_name} · #{time_ago(req.created_at)}"
                end
                div(class: "flex flex-wrap gap-[6px] mt-3") do
                  added.each   { |k| role_diff_pill(k, :add) }
                  removed.each { |k| role_diff_pill(k, :remove) }
                  if added.empty? && removed.empty?
                    span(class: "text-[11.5px]", style: "color:var(--muted-text)") { plain "No role changes" }
                  end
                end
              end
            end
            action_buttons(req)
          end
        end
      end

      def role_diff_pill(key, direction)
        role   = @roles_by_key[key]
        label  = role&.name || key.humanize
        if direction == :add
          span(class: "inline-flex items-center gap-[5px] text-[11px] font-semibold px-[9px] py-[3px] rounded-full",
               style: "background:rgba(34,197,94,0.1);color:#16a34a;border:1px solid rgba(34,197,94,0.25)") do
            span(class: "flex w-[9px] h-[9px]") { render UI::Icon.new(:plus, class: "w-full h-full") }
            plain label
          end
        else
          span(class: "inline-flex items-center gap-[5px] text-[11px] font-semibold px-[9px] py-[3px] rounded-full",
               style: "background:rgba(220,38,38,0.06);color:#dc2626;border:1px solid rgba(220,38,38,0.18)") do
            span(class: "flex w-[9px] h-[9px]") { render UI::Icon.new(:minus, class: "w-full h-full") }
            plain label
          end
        end
      end

      def action_buttons(req)
        div(class: "flex items-center gap-2 flex-shrink-0") do
          form(action: reject_team_role_request_path(req), method: "post",
               data: { turbo_confirm: "Reject this role change request for #{req.target_user.full_name}?" }) do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            render UI::Button.new(variant: :secondary, type: "submit") do
              render UI::Icon.new(:x, class: ICON_SM)
              plain "Reject"
            end
          end
          form(action: approve_team_role_request_path(req), method: "post",
               data: { turbo_confirm: "Approve role change for #{req.target_user.full_name}? Access will update immediately." }) do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            render UI::Button.new(variant: :primary, type: "submit") do
              render UI::Icon.new(:check, class: ICON_SM)
              plain "Approve"
            end
          end
        end
      end

      def initials_for(user)
        user.full_name.split.map { |w| w[0] }.first(2).join.upcase
      end

      def time_ago(time)
        diff = Time.current - time
        case diff
        when 0..59      then "just now"
        when 60..3599   then "#{(diff / 60).to_i}m ago"
        when 3600..86399 then "#{(diff / 3600).to_i}h ago"
        else                 time.strftime("%d %b")
        end
      end
    end
  end
end
