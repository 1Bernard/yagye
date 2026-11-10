defmodule YagyeCoreWeb.Controllers.Internal.CheckoutTemplateController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.CheckoutTemplates
  alias YagyeCore.Merchants
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  # GET /internal/merchants/:merchant_code/checkout-template?mode=live
  def show(conn, %{"merchant_code" => merchant_code} = params) do
    mode = params["mode"] || "live"

    with {:ok, merchant} <- Merchants.get_merchant(merchant_code) do
      result =
        case CheckoutTemplates.get_or_create_draft(merchant.id, mode) do
          {:ok, template} -> template
          _ -> nil
        end

      Response.ok(conn, render_template(result))
    end
  end

  # PATCH /internal/merchants/:merchant_code/checkout-template
  # Body: { mode?, font_family?, brand_color?, methods? }
  def update(conn, %{"merchant_code" => merchant_code} = params) do
    mode = params["mode"] || "live"
    theme_attrs = extract_theme(params)

    with {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, published} <- CheckoutTemplates.upsert_and_publish(merchant.id, mode, theme_attrs) do
      Response.ok(conn, render_template(published))
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp extract_theme(params) do
    %{}
    |> maybe_put(:font_family, params["font_family"])
    |> maybe_put(:brand_color, params["brand_color"])
    |> maybe_put(:methods, params["methods"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp render_template(nil) do
    %{theme: %{}, components: []}
  end

  defp render_template(template) do
    %{
      id: template.public_id,
      status: template.status,
      mode: template.mode,
      theme: template.theme || %{},
      components: render_components(template.components)
    }
  end

  defp render_components(%Ecto.Association.NotLoaded{}), do: []

  defp render_components(components) when is_list(components) do
    components
    |> Enum.sort_by(& &1.position)
    |> Enum.map(fn c ->
      %{
        component_type: c.component_type,
        position: c.position,
        visible: c.visible,
        config: c.config || %{}
      }
    end)
  end
end
