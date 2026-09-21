defmodule YagyeCore.Invoices.Workers.InvoiceReconciliationWorker do
  @moduledoc false

  # Triggered by checkout_session.completed outbox events.
  # When the session's payment link is of kind "invoice", updates the invoice
  # state (open → partially_paid or paid) and enriches the customer record with
  # contact info collected during checkout.

  use Oban.Worker, queue: :events, max_attempts: 3

  require Logger

  alias YagyeCore.CheckoutSessions
  alias YagyeCore.Customers
  alias YagyeCore.Invoices
  alias YagyeCore.Invoices.Schemas.Invoice
  alias YagyeCore.Outbox.EventEnvelope
  alias YagyeCore.PaymentLinks.Schemas.PaymentLink
  alias YagyeCore.Payments
  alias YagyeCore.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"envelope" => envelope_map}}) do
    envelope = EventEnvelope.from_map(envelope_map)
    payload = envelope.payload

    session_id = payload["session_id"]
    payment_id = payload["payment_id"]
    amount = payload["total_amount"]

    with {:ok, session} <- CheckoutSessions.get_session_by_public_id(session_id),
         {:ok, link} <- load_invoice_link(session.payment_link_id),
         {:ok, invoice} <- load_invoice_for_link(link.id) do
      result = Invoices.apply_payment(invoice, amount)

      case result do
        {:ok, updated_invoice} ->
          Logger.info(
            "[invoice_reconciliation] invoice #{invoice.public_id} → #{updated_invoice.state}",
            invoice_id: invoice.public_id,
            session_id: session_id
          )

          maybe_enrich_customer(invoice.customer_id, payment_id)
          :ok

        {:error, reason} ->
          Logger.warning("[invoice_reconciliation] failed to apply payment",
            invoice_id: invoice.public_id,
            session_id: session_id,
            reason: inspect(reason)
          )

          {:error, reason}
      end
    else
      {:skip, reason} ->
        Logger.debug("[invoice_reconciliation] skipping session #{session_id}: #{reason}")
        :ok

      {:error, reason} ->
        Logger.warning("[invoice_reconciliation] lookup error for session #{session_id}",
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp load_invoice_link(nil), do: {:skip, "no payment_link_id on session"}

  defp load_invoice_link(payment_link_id) do
    case Repo.get(PaymentLink, payment_link_id) do
      %PaymentLink{kind: "invoice"} = link -> {:ok, link}
      %PaymentLink{} -> {:skip, "payment link is not invoice kind"}
      nil -> {:skip, "payment link not found"}
    end
  end

  defp load_invoice_for_link(payment_link_id) do
    case Repo.get_by(Invoice, payment_link_id: payment_link_id) do
      nil -> {:error, :invoice_not_found}
      invoice -> {:ok, invoice}
    end
  end

  defp maybe_enrich_customer(customer_id, payment_id) do
    with {:ok, payment} <- Payments.get_payment(payment_id),
         %{} = meta <- payment.metadata,
         {:ok, customer} <- Customers.get_customer(customer_id) do
      contact =
        %{}
        |> maybe_add_contact(:email, meta["customer_email"])
        |> maybe_add_contact(:phone, meta["customer_phone"])
        |> maybe_add_contact(:name, meta["customer_name"])

      if contact != %{}, do: maybe_update_contact(customer, customer_id, contact)
    else
      _ -> :ok
    end
  end

  defp maybe_update_contact(customer, customer_id, contact) do
    case Customers.update_contact_info(customer, contact) do
      {:ok, _} ->
        Logger.debug("[invoice_reconciliation] customer #{customer_id} contact enriched")

      {:error, reason} ->
        Logger.warning("[invoice_reconciliation] customer enrichment failed",
          customer_id: customer_id,
          reason: inspect(reason)
        )
    end
  end

  defp maybe_add_contact(map, _key, nil), do: map
  defp maybe_add_contact(map, _key, ""), do: map
  defp maybe_add_contact(map, key, val), do: Map.put(map, key, val)
end
