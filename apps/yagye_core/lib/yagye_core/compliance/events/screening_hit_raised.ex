defmodule YagyeCore.Compliance.Events.ScreeningHitRaised do
  @moduledoc false
  @enforce_keys [
    :screening_hit_id,
    :merchant_id,
    :subject_type,
    :subject_id,
    :list_type,
    :match_score,
    :occurred_at
  ]
  defstruct [
    :screening_hit_id,
    :merchant_id,
    :subject_type,
    :subject_id,
    :list_type,
    :list_source,
    :matched_name,
    :match_score,
    :occurred_at
  ]
end
