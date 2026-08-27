defmodule YagyeCore.Compliance.Adapters.StubScreeningAdapter do
  @moduledoc false
  @behaviour YagyeCore.Compliance.Adapters.ScreeningAdapter

  @impl true
  def screen(_subject) do
    {:ok,
     %{
       provider_search_ref: "stub-" <> Uniq.UUID.uuid7(),
       match_count: 0,
       hits: []
     }}
  end
end
