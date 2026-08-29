defmodule YagyeCoreWeb.Controllers.ApiKeys.ApiKeyJSON do
  @moduledoc false

  alias YagyeCore.Merchants.Schemas.ApiKey

  # raw_key is present ONLY on creation — shown once and never stored.
  def data(%ApiKey{} = k, raw_key \\ nil) do
    base = %{
      id: k.public_id,
      object: "api_key",
      kind: k.kind,
      mode: k.mode,
      label: k.label || "",
      key_prefix: k.key_prefix,
      scopes: k.scopes,
      created_by: k.created_by,
      expires_at: k.expires_at,
      revoked_at: k.revoked_at,
      inserted_at: k.inserted_at
    }

    if raw_key, do: Map.put(base, :key, raw_key), else: base
  end
end
