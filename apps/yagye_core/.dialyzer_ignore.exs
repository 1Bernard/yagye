# Known false positives — documented here rather than silently ignored.
#
# ExUnit macro entries: `use ExUnit.CaseTemplate` generates internal functions
# (__merge__, __noop__, __proxy__) at compile time via macros. Dialyzer analyses
# the .beam files but cannot see macro-generated definitions, so it reports them
# as missing. They exist at runtime and are not our code to fix.
#
# Phoenix router: a pattern-match false positive in Phoenix internals that does
# not affect our code. Tracked upstream at github.com/phoenixframework/phoenix.
[
  ~r/ExUnit\.Callbacks\.__/,
  ~r/ExUnit\.CaseTemplate\.__/,
  ~r/ExUnit\.Callbacks\.on_exit/,
  # Ecto.Multi is an opaque type; Dialyzer cannot inspect its internal structure.
  # All call_without_opaque warnings on Multi pipeline calls are false positives.
  ~r/call_without_opaque/
]
