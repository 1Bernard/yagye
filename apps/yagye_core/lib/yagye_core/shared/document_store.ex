defmodule YagyeCore.Shared.DocumentStore do
  @moduledoc "S3-backed document storage with presigned URL generation."

  @doc """
  Generates a presigned S3 PUT URL for direct upload.

  When `KYB_KMS_KEY_ARN` is configured, the URL is signed with SSE-KMS headers.
  The caller must include `required_headers` in the PUT request; omitting them
  causes S3 to reject the upload with SignatureDoesNotMatch.

  Returns `{:ok, %{presigned_url: url, s3_key: key, expires_at: datetime, required_headers: []}}`.
  """
  def presign_upload(merchant_id, kind, document_id, _content_type \\ "application/octet-stream") do
    cfg = ex_aws_config()
    bucket = bucket()
    key = object_key(merchant_id, kind, document_id)
    expiry = upload_expiry()
    {sse_opts, sse_headers} = sse_kms_opts()

    case ExAws.S3.presigned_url(cfg, :put, bucket, key, [expires_in: expiry] ++ sse_opts) do
      {:ok, url} ->
        {:ok,
         %{
           presigned_url: rewrite_host(url),
           s3_key: key,
           expires_at: DateTime.utc_now() |> DateTime.add(expiry, :second),
           required_headers: sse_headers
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generates a presigned S3 PUT URL for a merchant invoice PDF.
  Returns `{:ok, %{presigned_url: url, s3_key: key}}`.
  """
  def presign_invoice_pdf(merchant_id, temp_id) do
    cfg = ex_aws_config()
    bucket = bucket()
    key = "invoices/#{merchant_id}/#{temp_id}.pdf"
    expiry = upload_expiry()

    case ExAws.S3.presigned_url(cfg, :put, bucket, key,
           expires_in: expiry,
           headers: [{"content-type", "application/pdf"}]
         ) do
      {:ok, url} -> {:ok, %{presigned_url: rewrite_host(url), s3_key: key}}
      {:error, reason} -> {:error, reason}
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

  # Returns {presigned_url_opts, required_client_headers} for SSE-KMS when configured.
  # Both must be used together: opts sign the headers into the URL; the client must
  # send the same headers or S3 rejects with SignatureDoesNotMatch.
  defp sse_kms_opts do
    case Application.get_env(:yagye_core, :document_store)[:kms_key_arn] do
      nil ->
        {[], []}

      arn ->
        headers = [
          {"x-amz-server-side-encryption", "aws:kms"},
          {"x-amz-server-side-encryption-aws-kms-key-id", arn}
        ]

        {[headers: headers], headers}
    end
  end

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
