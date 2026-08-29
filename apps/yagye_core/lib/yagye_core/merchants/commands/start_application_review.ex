defmodule YagyeCore.Merchants.Commands.StartApplicationReview do
  @moduledoc false
  @enforce_keys [:application_id, :reviewed_by]
  defstruct [:application_id, :reviewed_by, :review_notes]
end
