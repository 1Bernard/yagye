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
          active_nav: :team_role_requests,
          title:      "Role change requests",
          breadcrumbs: [
            { label: "Team members", url: team_users_path },
            { label: "Role change requests" }
          ]
        ) do
          render UI::PageHeader.new(
            title:    "Role change requests",
            subtitle: "#{@requests.size} pending #{@requests.size == 1 ? 'request' : 'requests'} require a second approver"
          )
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

      def empty_state
        div(class: "#{SURFACE_CARD} px-8 py-14 flex flex-col items-center text-center gap-3") do
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

        div(class: "#{SURFACE_CARD} overflow-hidden") do
          div(class: "px-6 py-5 flex items-start justify-between gap-4") do
            div(class: "flex items-start gap-4 min-w-0 flex-1") do
              render UI::Avatar.new(initials_for(req.target_user), size: :md)
              div(class: "min-w-0 flex-1") do
                div(class: "flex items-center gap-2 flex-wrap mb-[3px]") do
                  p(class: "text-[14px] font-bold tracking-[-0.01em]", style: "color:var(--ink)") do
                    plain req.target_user.full_name
                  end
                  span(class: "badge-amber #{BADGE}") do
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
        role  = @roles_by_key[key]
        label = role&.name || key.humanize
        cls   = direction == :add ? "badge-green" : "badge-red"
        icon  = direction == :add ? :plus : :minus
        span(class: "#{cls} inline-flex items-center gap-[5px] #{BADGE}") do
          span(class: "flex w-[9px] h-[9px]") { render UI::Icon.new(icon, class: "w-full h-full") }
          plain label
        end
      end

      def action_buttons(req)
        div(class: "flex items-center gap-2 flex-shrink-0") do
          a(href: reject_modal_team_role_request_path(req),
            class: BTN_SECONDARY,
            data: { turbo_frame: "modal-frame" }) do
            render UI::Icon.new(:x, class: ICON_SM)
            plain "Reject"
          end
          a(href: approve_modal_team_role_request_path(req),
            class: BTN_PRIMARY,
            data: { turbo_frame: "modal-frame" }) do
            render UI::Icon.new(:check, class: ICON_SM)
            plain "Approve"
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
