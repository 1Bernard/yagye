defmodule YagyeCoreWeb.Controllers.PaymentLinks.PaymentLinkJSON do
  @moduledoc false

  alias YagyeCore.PaymentLinks.Schemas.PaymentLink

  @base_url Application.compile_env(:yagye_core, :checkout_base_url, "https://pay.yagye.com")

  def data(%PaymentLink{} = link) do
    %{
      id: link.public_id,
      object: "payment_link",
      mode: link.mode,
      url_slug: link.url_slug,
      checkout_url: "#{@base_url}/#{link.url_slug}",
      kind: link.kind,
      amount: link.amount,
      currency: link.currency,
      description: link.description,
      image_url: link.image_url,
      allowed_methods: link.allowed_methods,
      collect_email: link.collect_email,
      collect_phone: link.collect_phone,
      collect_name: link.collect_name,
      reusable: link.reusable,
      max_uses: link.max_uses,
      use_count: link.use_count,
      active: link.active,
      expires_at: link.expires_at,
      metadata: link.metadata,
      checkout_layout: link.checkout_layout,
      inserted_at: link.inserted_at
    }
  end

  def list(%{data: links, has_more: has_more}) do
    %{object: "list", data: Enum.map(links, &data/1), has_more: has_more}
  end
end
