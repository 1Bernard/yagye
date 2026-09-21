# Test script — end-to-end MTN MoMo sandbox test via MTNMomoAdapter.
#
# Usage (from apps/yagye_core/):
#   source ../../.env && mix run priv/scripts/test_mtn_sandbox.exs
#
# NOTE: MTN's generic sandbox environment only accepts EUR as currency.
# GHS is supported in the production environment. This script uses EUR for testing.

alias YagyeCore.Repo
alias YagyeCore.Providers.Schemas.{Provider, ProviderCredential}
alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}
alias YagyeCore.Payments.Adapters.MTNMomoAdapter
alias YagyeCore.Shared.Vault

IO.puts("\n=== MTN MoMo sandbox test ===\n")

# ── 1. Load credential ────────────────────────────────────────────────────────

provider = Repo.get_by!(Provider, code: "mtn_momo_gh")
credential_record = Repo.get_by!(ProviderCredential, provider_id: provider.id, mode: "simulation")
{:ok, decrypted} = Vault.decrypt_map(credential_record.encrypted_payload)
credential = Map.put(decrypted, "base_url", credential_record.base_url)

IO.puts("Credential loaded:")
IO.puts("  base_url           : #{credential["base_url"]}")
IO.puts("  target_environment : #{credential["target_environment"]}")
IO.puts("  api_user_id        : #{credential["api_user_id"]}")
IO.puts("")

# ── 2. Build test structs ─────────────────────────────────────────────────────

reference_id = Ecto.UUID.generate()

payment = %Payment{
  method: "mobile_money",
  amount: 100,
  currency: "EUR",  # MTN generic sandbox only accepts EUR; GHS is production-only
  metadata: %{
    "network"      => "MTN",
    "msisdn"       => "0241000001",
    "description"  => "Yagye MTN sandbox test",
    "account_name" => "Test Customer"
  }
}

attempt = %PaymentAttempt{idempotency_token: reference_id}

IO.puts("Charging:")
IO.puts("  Reference ID : #{reference_id}")
IO.puts("  Amount       : EUR #{payment.amount / 100}")
IO.puts("  MSISDN       : #{payment.metadata["msisdn"]}")
IO.puts("")

# ── 3. charge/3 ───────────────────────────────────────────────────────────────

IO.puts("→ POST /collection/v1_0/requesttopay")

case MTNMomoAdapter.charge(payment, attempt, credential) do
  {:pending, %{provider_reference: ref}} ->
    IO.puts("✓ {:pending} — reference: #{ref}")
    IO.puts("")
    IO.puts("Waiting 5 seconds before polling...")
    Process.sleep(5_000)

    # ── 4. query_charge/2 ─────────────────────────────────────────────────────
    poll_attempt = %PaymentAttempt{provider_reference: ref}

    IO.puts("→ GET /collection/v1_0/requesttopay/#{ref}")

    case MTNMomoAdapter.query_charge(poll_attempt, credential) do
      {:ok, result} ->
        IO.puts("✓ {:ok} SUCCESSFUL")
        IO.puts("  provider_reference : #{result.provider_reference}")
        IO.puts("  auth_code (fin_id) : #{result.auth_code}")

      {:error, %{response_code: "pending"}} ->
        IO.puts("⏳ Still PENDING — sandbox auto-approves eventually.")
        IO.puts("   This is normal; the async approval takes a moment.")

      {:error, err} ->
        IO.puts("✗ {:error} #{inspect(err)}")
    end

  {:error, err} ->
    IO.puts("✗ charge failed: #{inspect(err)}")
end

IO.puts("\n=== Done ===")
