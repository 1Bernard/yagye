defmodule YagyeCore.Compliance.Adapters.ScreeningAdapter do
  @moduledoc false

  @type subject :: map()
  @type result :: %{
          provider_search_ref: String.t(),
          match_count: non_neg_integer(),
          hits: list()
        }

  @callback screen(subject()) :: {:ok, result()} | {:error, term()}
end
