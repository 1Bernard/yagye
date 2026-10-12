defmodule YagyeCore.Shared.SecretsManager do
  @moduledoc false

  # Fetches secrets from AWS Secrets Manager (Floci in dev, real AWS in prod).
  # Secrets are cached in persistent_term for 5 minutes to avoid per-payment API calls.
  # Cache key: {__MODULE__, secret_name}

  @cache_ttl_ms 300_000

  def get_secret(name) do
    case cached(name) do
      {:ok, _} = hit -> hit
      :miss -> fetch_and_cache(name)
    end
  end

  # Creates the secret if it doesn't exist; updates its value if it does.
  # Used by the yagye.secrets.setup Mix task.
  def put_secret(name, payload) when is_map(payload) do
    with {:ok, json} <- Jason.encode(payload) do
      ExAws.SecretsManager.create_secret(name: name, secret_string: json)
      |> ExAws.request()
      |> case do
        {:ok, _} ->
          :ok

        {:error, {"ResourceExistsException", _}} ->
          update_secret(name, json)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def secret_exists?(name) do
    case ExAws.SecretsManager.get_secret_value(name) |> ExAws.request() do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp cached(name) do
    key = cache_key(name)

    case :persistent_term.get(key, nil) do
      nil ->
        :miss

      {value, expires_at} ->
        if System.monotonic_time(:millisecond) < expires_at do
          {:ok, value}
        else
          :persistent_term.erase(key)
          :miss
        end
    end
  end

  defp fetch_and_cache(name) do
    with {:ok, value} <- fetch_from_aws(name) do
      expires_at = System.monotonic_time(:millisecond) + @cache_ttl_ms
      :persistent_term.put(cache_key(name), {value, expires_at})
      {:ok, value}
    end
  end

  defp fetch_from_aws(name) do
    case ExAws.SecretsManager.get_secret_value(name) |> ExAws.request() do
      {:ok, %{"SecretString" => json}} -> Jason.decode(json)
      {:ok, _} -> {:error, :binary_secret_not_supported}
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_secret(name, json) do
    case ExAws.SecretsManager.put_secret_value(name, secret_string: json) |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp cache_key(name), do: {__MODULE__, name}
end
