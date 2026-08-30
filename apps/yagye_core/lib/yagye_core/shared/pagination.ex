defmodule YagyeCore.Shared.Pagination do
  @moduledoc false

  # Cursor-based (keyset) pagination for merchant-facing list endpoints.
  #
  # Cursors are the public_id (or internal id) of a record — opaque to the
  # client. UUID v7 ids are time-ordered so lexicographic comparison is correct.
  #
  # starting_after=X → page of records older than X  (forward traversal)
  # ending_before=X  → page of records newer than X  (backward traversal)
  # neither          → most-recent page
  #
  # Returns %{data: list, has_more: boolean}. Callers wrap in {:ok, ...}.

  import Ecto.Query

  alias YagyeCore.Repo

  @default_limit 25
  @max_limit 100

  @spec paginate(Ecto.Query.t(), atom(), keyword()) :: %{data: list(), has_more: boolean()}
  def paginate(base_query, cursor_field, opts) do
    limit = min(Keyword.get(opts, :limit, @default_limit), @max_limit)
    starting_after = Keyword.get(opts, :starting_after)
    ending_before = Keyword.get(opts, :ending_before)

    {data, has_more} =
      cond do
        starting_after ->
          records =
            base_query
            |> where([r], field(r, ^cursor_field) < ^starting_after)
            |> order_by([r], desc: field(r, ^cursor_field))
            |> limit(^(limit + 1))
            |> Repo.all()

          {Enum.take(records, limit), length(records) > limit}

        ending_before ->
          # Fetch in ASC order (toward newer records), then reverse so the
          # caller always receives records newest-first.
          records =
            base_query
            |> where([r], field(r, ^cursor_field) > ^ending_before)
            |> order_by([r], asc: field(r, ^cursor_field))
            |> limit(^(limit + 1))
            |> Repo.all()

          has_more = length(records) > limit
          data = records |> Enum.take(limit) |> Enum.reverse()
          {data, has_more}

        true ->
          records =
            base_query
            |> order_by([r], desc: field(r, ^cursor_field))
            |> limit(^(limit + 1))
            |> Repo.all()

          {Enum.take(records, limit), length(records) > limit}
      end

    %{data: data, has_more: has_more}
  end
end
