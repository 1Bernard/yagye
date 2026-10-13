# frozen_string_literal: true

module Team
  module RoleRequests
    class IndexView < ApplicationComponent
      include UI::Theme

      ROLE_META      = (Portal::RoleMetadata::MERCHANT + Portal::RoleMetadata::INTERNAL)
                         .index_by { |r| r[:key] }.freeze
      SLA_WARNING_H  = 24
      SLA_BREACH_H   = 48

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
            subtitle: "#{@requests.size} pending #{@requests.size == 1 ? 'request' : 'requests'} · oldest first"
          )
          if @requests.empty?
            empty_state
          else
            backlog_banner
            div(class: "flex flex-col gap-3") do
              @requests.each { |req| request_card(req) }
            end
          end
        end
      end

      private

      # ── SLA helpers ─────────────────────────────────────────────────────────

      def age_hours(time)
        (Time.current - time) / 3600.0
      end

      def age_category(time)
        h = age_hours(time)
        return :breach  if h >= SLA_BREACH_H
        return :warning if h >= SLA_WARNING_H
        :ok
      end

      def time_ago(time)
        diff = Time.current - time
        case diff
        when 0..59      then "just now"
        when 60..3599   then "#{(diff / 60).to_i}m ago"
        when 3600..86399 then "#{(diff / 3600).to_i}h ago"
        else
          days  = (diff / 86400).to_i
          hours = ((diff % 86400) / 3600).to_i
          hours > 0 ? "#{days}d #{hours}h ago" : "#{days}d ago"
        end
      end

      # ── Backlog banner ───────────────────────────────────────────────────────

      def backlog_banner
        breach_count  = @requests.count { |r| age_category(r.created_at) == :breach }
        warning_count = @requests.count { |r| age_category(r.created_at) == :warning }

        if breach_count > 0
          oldest = @requests.min_by(&:created_at)
          n      = breach_count
          msg    = "#{n} #{n == 1 ? 'request has' : 'requests have'} been pending over 48 hours — " \
                   "SLA breach. Oldest: #{time_ago(oldest.created_at)}."
          alert_banner(:breach, msg)
        elsif warning_count > 0
          n   = warning_count
          msg = "#{n} #{n == 1 ? 'request is' : 'requests are'} approaching the 48-hour SLA limit."
          alert_banner(:warning, msg)
        end
      end

      def alert_banner(level, msg)
        bg, border, icon_cls, text_cls, icon =
          if level == :breach
            [ "bg-red-50", "border-red-200", "text-red-500", "text-red-800", :alert_circle ]
          else
            [ "bg-amber-50", "border-amber-200", "text-amber-500", "text-amber-800", :clock ]
          end

        div(class: "mb-4 flex items-center gap-3 px-4 py-3 #{bg} border #{border} rounded-xl") do
          span(class: "flex-shrink-0 w-4 h-4 #{icon_cls}") do
            render UI::Icon.new(icon, class: "w-full h-full")
          end
          p(class: "text-[13px] #{text_cls}") { plain msg }
        end
      end

      # ── Cards ────────────────────────────────────────────────────────────────

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
        cat     = age_category(req.created_at)

        div(class: "#{SURFACE_CARD} overflow-hidden") do
          div(class: "px-6 py-5 flex items-start justify-between gap-4") do
            div(class: "flex items-start gap-4 min-w-0 flex-1") do
              render UI::Avatar.new(initials_for(req.target_user), size: :md)
              div(class: "min-w-0 flex-1") do
                div(class: "flex items-center gap-2 flex-wrap mb-[3px]") do
                  p(class: "text-[14px] font-bold tracking-[-0.01em]", style: "color:var(--ink)") do
                    plain req.target_user.full_name
                  end
                  span(class: "badge-amber #{BADGE}") { plain "Pending approval" }
                  if cat == :breach
                    span(class: "badge-red #{BADGE}") { plain "SLA breach" }
                  end
                end
                age_row(req, cat)
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

      def age_row(req, cat)
        time_cls = case cat
        when :breach  then "text-red-600 font-medium"
        when :warning then "text-amber-600 font-medium"
        else               ""
        end

        p(class: TYPE_CAPTION) do
          plain "Requested by #{req.requested_by.full_name} · "
          span(class: time_cls) { plain time_ago(req.created_at) }
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
        if req.requested_by_id == current_user.id
          div(class: "flex items-center gap-2 flex-shrink-0") do
            span(class: "text-[11.5px] text-gray-400 italic") { plain "Awaiting another approver" }
          end
        else
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
      end

      def initials_for(user)
        user.full_name.split.map { |w| w[0] }.first(2).join.upcase
      end
    end
  end
end
