defmodule YagyeCoreWeb.Controllers.Webhooks.ProviderWebhookController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Providers
  alias YagyeCore.Webhooks

  # ── Native rail / simulator webhooks ────────────────────────────────────────
  # Signed with an HMAC-SHA256 signature in "sha256={hex}" format.
  # The signing secret is a platform-level credential — no merchant context needed.

  def receive(conn, %{"provider_code" => provider_code} = params) do
    raw_body = conn.assigns[:raw_body] || ""
    signature = conn |> get_req_header("x-webhook-signature") |> List.first()
    event_id = params["event_id"] || conn |> get_req_header("x-webhook-event-id") |> List.first()
    event_type = params["event_type"]

    with {:ok, secret} <- Providers.get_webhook_secret(provider_code),
         :ok <- verify_sha256_hmac(raw_body, signature, secret),
         true <- is_binary(event_id) and is_binary(event_type) do
      case Webhooks.receive_webhook(provider_code, event_id, event_type, raw_body) do
        {:ok, _webhook} -> send_resp(conn, 200, "")
        {:error, :already_received} -> send_resp(conn, 200, "")
        {:error, _reason} -> send_resp(conn, 422, "")
      end
    else
      {:error, :invalid_signature} -> send_resp(conn, 401, "")
      {:error, _} -> send_resp(conn, 400, "")
      false -> send_resp(conn, 422, "")
    end
  end

  # ── External PSP webhooks (Model B) ─────────────────────────────────────────
  # Dispatched to a merchant-scoped URL because:
  #   1. Multiple merchants can each have their own Flutterwave / Paystack account
  #   2. Signature verification requires the MERCHANT'S credential, not a
  #      platform-level secret
  #   3. The merchant_id in the URL tells us which credential to fetch
  #
  # Each merchant configures their PSP's webhook URL to:
  #   https://api.yagye.com/provider-webhooks/flutterwave/merchant/{merchant_id}
  #   https://api.yagye.com/provider-webhooks/paystack/merchant/{merchant_id}

  def receive_external(conn, %{"provider_code" => "flutterwave", "merchant_id" => merchant_id}) do
    raw_body = conn.assigns[:raw_body] || ""
    verif_hash = conn |> get_req_header("verif-hash") |> List.first()

    with {:ok, payload} <- Jason.decode(raw_body),
         {:ok, credential} <-
           Providers.get_merchant_credential_for_psp("flutterwave", merchant_id),
         :ok <- verify_flutterwave_hash(verif_hash, credential),
         {:ok, event_id, event_type} <- extract_flutterwave_event(payload) do
      case Webhooks.receive_webhook("flutterwave", event_id, event_type, raw_body) do
        {:ok, _} -> send_resp(conn, 200, "")
        {:error, :already_received} -> send_resp(conn, 200, "")
        {:error, _} -> send_resp(conn, 422, "")
      end
    else
      {:error, :invalid_signature} -> send_resp(conn, 401, "")
      {:error, _} -> send_resp(conn, 400, "")
    end
  end

  def receive_external(conn, %{"provider_code" => "paystack", "merchant_id" => merchant_id}) do
    raw_body = conn.assigns[:raw_body] || ""
    signature = conn |> get_req_header("x-paystack-signature") |> List.first()

    with {:ok, payload} <- Jason.decode(raw_body),
         {:ok, credential} <- Providers.get_merchant_credential_for_psp("paystack", merchant_id),
         :ok <- verify_paystack_hmac(raw_body, signature, credential),
         {:ok, event_id, event_type} <- extract_paystack_event(payload) do
      case Webhooks.receive_webhook("paystack", event_id, event_type, raw_body) do
        {:ok, _} -> send_resp(conn, 200, "")
        {:error, :already_received} -> send_resp(conn, 200, "")
        {:error, _} -> send_resp(conn, 422, "")
      end
    else
      {:error, :invalid_signature} -> send_resp(conn, 401, "")
      {:error, _} -> send_resp(conn, 400, "")
    end
  end

  def receive_external(conn, _params), do: send_resp(conn, 404, "")

  # ── Signature verification ───────────────────────────────────────────────────

  # Simulator / native rail: HMAC-SHA256, "sha256={hex}" header format.
  defp verify_sha256_hmac(_raw_body, nil, _secret), do: {:error, :invalid_signature}

  defp verify_sha256_hmac(raw_body, "sha256=" <> hex, secret) do
    expected = :crypto.mac(:hmac, :sha256, secret, raw_body) |> Base.encode16(case: :lower)

    if Plug.Crypto.secure_compare(expected, hex),
      do: :ok,
      else: {:error, :invalid_signature}
  end

  defp verify_sha256_hmac(_raw_body, _sig, _secret), do: {:error, :invalid_signature}

  # Flutterwave: static hash comparison (NOT an HMAC of the body).
  # The merchant sets a "Secret Hash" string in their Flutterwave Dashboard →
  # Account Settings → Webhooks. Flutterwave sends that string verbatim in the
  # "verif-hash" header. We compare it to the value stored in the credential.
  defp verify_flutterwave_hash(nil, _credential), do: {:error, :invalid_signature}

  defp verify_flutterwave_hash(verif_hash, %{"webhook_hash" => stored_hash}) do
    if Plug.Crypto.secure_compare(stored_hash, verif_hash),
      do: :ok,
      else: {:error, :invalid_signature}
  end

  defp verify_flutterwave_hash(_verif_hash, _credential), do: {:error, :invalid_signature}

  # Paystack: HMAC-SHA512 of the raw request body, signed with the secret key.
  defp verify_paystack_hmac(_body, nil, _credential), do: {:error, :invalid_signature}

  defp verify_paystack_hmac(raw_body, signature, %{"secret_key" => secret_key}) do
    expected =
      :crypto.mac(:hmac, :sha512, secret_key, raw_body) |> Base.encode16(case: :lower)

    if Plug.Crypto.secure_compare(expected, signature),
      do: :ok,
      else: {:error, :invalid_signature}
  end

  defp verify_paystack_hmac(_body, _sig, _credential), do: {:error, :invalid_signature}

  # ── Event extraction ─────────────────────────────────────────────────────────

  # Flutterwave events use the numeric transaction id as the dedupe key.
  defp extract_flutterwave_event(%{"event" => event_type, "data" => %{"id" => id}}) do
    {:ok, "flw_#{id}", event_type}
  end

  defp extract_flutterwave_event(_), do: {:error, :malformed_webhook}

  # Paystack events use the transaction reference as the dedupe key.
  defp extract_paystack_event(%{"event" => event_type, "data" => %{"reference" => ref}}) do
    {:ok, "ps_#{ref}", event_type}
  end

  defp extract_paystack_event(_), do: {:error, :malformed_webhook}
end
