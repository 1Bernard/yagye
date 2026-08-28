# 0016 — Portal view layer: Phlex components, no ERB application views

Date: 2026-08-28
Status: Accepted

## Context

yagye_portal is a Rails 8 app serving three audiences: standard merchants, large-enterprise merchants (entitlement-gated), and Yagye ops (internal_staff only). The portal renders Tailwind-styled HTML with Turbo Drive navigation and Turbo Stream real-time updates.

Rails' default ERB templates make design-system enforcement difficult: there is no compile-time check that a colour class came from `UI::Theme`, and partial composition with `render` is loose (any string filename resolves). PhlexUI was evaluated but rejected — it ships its own component set that conflicts with the custom LunarDesk-inspired design system adopted for this project.

## Decision

All application views (every page rendered after login) are written as Phlex components inheriting from `ApplicationComponent < Phlex::HTML`. ERB is used **only** for the root application layout (`app/views/layouts/application.html.erb`) and Devise auth views (sign-in, password reset). Everything else is a Phlex component.

`ApplicationComponent` includes:
- `Phlex::Rails::Helpers::Routes` — named route helpers
- `Phlex::Rails::Helpers::T` — I18n with auto-scoped keys
- Pundit helpers — `can?(action, subject)` bridge
- `svg(content)` — trusted SVG injection via `raw safe(content)`

SVGs are inlined (no external requests — blocked by the artifact CSP). The `safe()` + `raw()` pair is the Phlex 2.4 API for trusted markup; `unsafe_raw` does not exist in this version.

## Consequences

- **Positive**: `UI::Theme` constants are the only way to express colours — a component that hardcodes `text-teal-400` instead of `UI::Theme::PRIMARY_ACTIVE` is immediately visible in review.
- **Positive**: Components are plain Ruby classes — testable without a view context.
- **Positive**: Namespace enforced by Zeitwerk: `Layout::Shell`, `UI::StatCard`, etc. A missing constant is a boot-time error, not a silent nil.
- **Negative**: Developers unfamiliar with Phlex need onboarding. The `view_template` method replaces the ERB body; `yield` inside it passes a block, not a Rails content slot.
- **Note**: Phlex 2.4 changed `raw` to require a `Phlex::SGML::SafeObject`. Wrap SVG strings with `safe()` before passing to `raw()`.
