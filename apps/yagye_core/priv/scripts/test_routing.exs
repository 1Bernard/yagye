# Tests that a sandbox mobile_money payment routes to mtn_momo_gh via the
# platform routing rule and resolves the correct sandbox credential.

alias YagyeCore.Repo
alias YagyeCore.Merchants.Schemas.Merchant
alias YagyeCore.Payments.Schemas.Payment
alias YagyeCore.Providers

IO.puts("\n=== Routing path test ===\n")

dev_merchant = Repo.get_by!(Merchant, legal_name: "Dev Merchant")

fake_payment = %Payment{
  mode: "sandbox",
  method: "mobile_money",
  currency: "GHS",
  amount: 10_000,
  merchant_id: dev_merchant.id
}

case Providers.get_provider_for_payment(fake_payment, []) do
  {:ok, {provider, credential, meta}} ->
    IO.puts("✓ Provider resolved: #{provider.code}")
    IO.puts("  kind               : #{provider.kind}")
    IO.puts("  adapter_module     : #{provider.adapter_module}")
    IO.puts("  routing source     : #{meta.source}")
    if meta[:rule_id], do: IO.puts("  rule_id            : #{meta.rule_id}")
    IO.puts("  credential base_url: #{credential["base_url"]}")
    IO.puts("  target_environment : #{credential["target_environment"]}")

  {:error, reason} ->
    IO.puts("✗ Routing failed: #{inspect(reason)}")
end

IO.puts("\n=== Done ===")
