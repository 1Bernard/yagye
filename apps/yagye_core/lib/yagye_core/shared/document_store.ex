defmodule YagyeCore.Shared.DocumentStore do
  @moduledoc "S3-backed document storage with presigned URL generation."

  @doc """
  Generates a presigned S3 PUT URL for direct upload.
  Returns `{:ok, %{presigned_url: url, s3_key: key, expires_at: datetime}}`.
  """
  def presign_upload(merchant_id, kind, document_id, _content_type \\ "application/octet-stream") do
    cfg = ex_aws_config()
    bucket = bucket()
    key = object_key(merchant_id, kind, document_id)
    expiry = upload_expiry()

    case ExAws.S3.presigned_url(cfg, :put, bucket, key, expires_in: expiry) do
      {:ok, url} ->
        {:ok,
         %{
           presigned_url: rewrite_host(url),
           s3_key: key,
           expires_at: DateTime.utc_now() |> DateTime.add(expiry, :second)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Generates a presigned S3 GET URL for document download."
  def presign_download(s3_key) do
    cfg = ex_aws_config()
    bucket = bucket()
    expiry = download_expiry()

    case ExAws.S3.presigned_url(cfg, :get, bucket, s3_key, expires_in: expiry) do
      {:ok, url} -> {:ok, rewrite_host(url)}
      {:error, reason} -> {:error, reason}
    end
  end

  # ── Private ─────────────────────────────────────────────────────────────────

  defp object_key(merchant_id, kind, document_id),
    do: "kyb/#{merchant_id}/#{kind}/#{document_id}"

  defp bucket,
    do: Application.fetch_env!(:yagye_core, :document_store)[:bucket]

  defp upload_expiry,
    do: Application.fetch_env!(:yagye_core, :document_store)[:upload_expiry_seconds]

  defp download_expiry,
    do: Application.fetch_env!(:yagye_core, :document_store)[:download_expiry_seconds]

  defp ex_aws_config, do: ExAws.Config.new(:s3)

  # Rewrites the host (and port) in a presigned URL when KYB_PRESIGNED_HOST is set.
  # Needed when Core talks to S3 via a Docker-internal hostname (e.g. "floci") but
  # the presigned URL must be reachable by an external client (e.g. "localhost:4566").
  defp rewrite_host(url) do
    case Application.get_env(:yagye_core, :document_store)[:presigned_host_override] do
      nil ->
        url

      override ->
        uri = URI.parse(url)

        {host, port} =
          case String.split(override, ":") do
            [h, p] -> {h, String.to_integer(p)}
            [h] -> {h, uri.port}
          end

        %{uri | host: host, port: port} |> URI.to_string()
    end
  end
end
