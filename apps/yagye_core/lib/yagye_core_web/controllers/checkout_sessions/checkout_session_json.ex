defmodule YagyeCoreWeb.Controllers.CheckoutSessions.CheckoutSessionJSON do
  @moduledoc false

  alias YagyeCore.Checkout.Schemas.{CheckoutLineItem, CheckoutSession}

  @base_url Application.compile_env(:yagye_core, :checkout_base_url, "https://pay.yagye.com")

  def data(%CheckoutSession{} = session, url_token \\ nil) do
    %{
      id: session.public_id,
      object: "checkout_session",
      mode: session.mode,
      checkout_url: checkout_url(session, url_token),
      state: session.state,
      currency: session.currency,
      subtotal_amount: session.subtotal_amount,
      tax_amount: session.tax_amount,
      shipping_amount: session.shipping_amount,
      discount_amount: session.discount_amount,
      total_amount: session.total_amount,
      description: session.description,
      merchant_reference: session.merchant_reference,
      collect_email: session.collect_email,
      collect_phone: session.collect_phone,
      collect_name: session.collect_name,
      allowed_methods: session.allowed_methods,
      payment_link_id: session.payment_link_id,
      payment_id: session.payment_id,
      success_url: session.success_url,
      cancel_url: session.cancel_url,
      metadata: session.metadata,
      expires_at: session.expires_at,
      completed_at: session.completed_at,
      line_items: line_items(session),
      inserted_at: session.inserted_at
    }
  end

  defp checkout_url(session, nil), do: "#{@base_url}/s/#{session.public_id}"
  defp checkout_url(_session, token), do: "#{@base_url}/s/#{token}"

  defp line_items(%CheckoutSession{line_items: items}) when is_list(items) do
    Enum.map(items, &line_item/1)
  end

  defp line_items(_), do: []

  defp line_item(%CheckoutLineItem{} = item) do
    %{
      position: item.position,
      kind: item.kind,
      description: item.description,
      quantity: item.quantity,
      unit_amount: item.unit_amount,
      total_amount: item.total_amount,
      image_url: item.image_url
    }
  end
end
