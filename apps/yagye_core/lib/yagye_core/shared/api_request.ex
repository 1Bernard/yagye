defmodule YagyeCore.Shared.ApiRequest do
  @moduledoc false
  use YagyeCore.Shared.Schema
  import Ecto.Changeset

  # Append-only audit log for every inbound API call including failures.
  # merchant_id and api_key_id are nullable — unauthenticated requests still logged.
  schema "api_requests" do
    field :merchant_id, Uniq.UUID
    field :api_key_id, Uniq.UUID
    field :mode, YagyeCore.Shared.Types.YagyeMode
    field :method, :string
    field :path, :string
    field :api_version, :string
    field :status, :integer
    field :duration_ms, :integer
    field :correlation_id, :string
    field :trace_id, :string
    field :idempotency_key, :string
    field :request_body_sha256, :string
    field :error_code, :string

    timestamps(updated_at: false)
  end

  @required ~w[method path status duration_ms correlation_id]a
  @optional ~w[merchant_id api_key_id mode api_version trace_id idempotency_key request_body_sha256 error_code]a

  def changeset(request, attrs) do
    request
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
  end

  def log(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> YagyeCore.Repo.insert(returning: false)
  end
end
