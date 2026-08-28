# 0018 — UI::Theme as the single source of design tokens

Date: 2026-08-28
Status: Accepted

## Context

The portal design system is derived from a reference design (LunarDesk). The primary colour (teal-400), status semantic colours (green/red/violet/amber), typography scale, and surface definitions must be consistent across every component.

Without a constraint, individual components accumulate inline Tailwind strings that silently diverge from the standard. A change to the card radius requires grepping hundreds of component files.

## Decision

`app/components/ui/theme.rb` (`UI::Theme`) is the **only** place where colour, surface, and typographic tokens are defined. Rules:

1. **No raw colour class in a component**: `text-teal-600` may not appear in a component file. It must be referenced via `UI::Theme::PRIMARY_ACTIVE` or equivalent.
2. **Layout utilities are exempt**: spacing (`px-4`, `gap-3`), sizing (`w-8`), flexbox (`flex`, `items-center`), positioning (`sticky`, `z-10`) are structural, not semantic — they live inline.
3. **Theme constants are strings of Tailwind classes**: consumed by interpolation (`class: "#{UI::Theme::CARD} p-6"`). This keeps Tailwind's JIT scanner happy as long as the theme file is listed in the Tailwind content paths.
4. **Status colours** are dispatched through `UI::Theme.status_classes(status_string)` — a single hash lookup that maps a core state string to the correct badge classes.

The content path for Tailwind must include `app/components/**/*.rb`.

## Consequences

- **Positive**: A design token change (e.g. primary from teal-400 to indigo-400) is a single-line edit in `ui/theme.rb`.
- **Positive**: PR review for a new component can check theme compliance by searching for raw colour classes — a mechanical check.
- **Negative**: Developers must know which constants exist before writing a component. The theme file is the first file to read when building a new page.
- **Note**: Tailwind v4 scans Ruby files if the content glob covers them. Ensure `app/components/**/*.rb` is in `tailwind.config.js` (or the v4 equivalent CSS `@source` directive).
