defmodule YagyeCoreWeb.Controllers.Internal.SplitRulesController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Merchants
  alias YagyeCore.Splits
  alias YagyeCore.Splits.Schemas.{SplitRule, SplitRuleLeg}
  alias YagyeCoreWeb.Response

  action_fallback(YagyeCoreWeb.FallbackController)

  # GET /internal/split-rules?merchant_code=MCH_xxx
  def index(conn, %{"merchant_code" => merchant_code}) do
    with {:ok, merchant} <- Merchants.get_merchant(merchant_code) do
      rules = Splits.list_rules(merchant.id)
      Response.ok(conn, Enum.map(rules, &rule_data/1))
    end
  end

  def index(conn, _params) do
    Response.unprocessable(conn, "missing_param", "merchant_code required")
  end

  # POST /internal/split-rules
  def create(conn, params) do
    with {:ok, merchant_code} <- require_param(params["merchant_code"], "merchant_code"),
         {:ok, name} <- require_param(params["name"], "name"),
         {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, legs} <- parse_legs(params["legs"]),
         {:ok, rule} <-
           Splits.create_rule(
             %{
               merchant_id: merchant.id,
               name: name,
               description: params["description"],
               mode: params["mode"] || "live"
             },
             legs
           ) do
      rule_with_legs = %{rule | legs: Enum.map(legs, &to_leg_struct(&1, rule))}
      Response.created(conn, rule_data(rule_with_legs))
    end
  end

  # GET /internal/split-rules/:id
  def show(conn, %{"id" => public_id}) do
    with {:ok, rule} <- Splits.get_rule(public_id) do
      Response.ok(conn, rule_data(rule))
    end
  end

  # POST /internal/split-rules/:id/deactivate
  def deactivate(conn, %{"id" => public_id}) do
    with {:ok, rule} <- Splits.deactivate_rule(public_id) do
      Response.ok(conn, rule_data(rule))
    end
  end

  # ── Private ───────────────────────────────────────────────────────────────

  defp parse_legs(nil), do: {:error, {:missing_param, "legs"}}
  defp parse_legs([]), do: {:error, :legs_required}

  defp parse_legs(legs) when is_list(legs) do
    parsed =
      Enum.map(legs, fn leg ->
        %{
          split_type: leg["split_type"] || leg[:split_type],
          value: parse_integer(leg["value"] || leg[:value]),
          recipient_merchant_id: leg["recipient_merchant_id"] || leg[:recipient_merchant_id]
        }
      end)

    {:ok, parsed}
  end

  defp parse_legs(_), do: {:error, {:invalid_param, "legs must be an array"}}

  defp parse_integer(nil), do: nil
  defp parse_integer(v) when is_integer(v), do: v
  defp parse_integer(v) when is_binary(v), do: String.to_integer(v)

  defp require_param(nil, name), do: {:error, {:missing_param, name}}
  defp require_param("", name), do: {:error, {:missing_param, name}}
  defp require_param(v, _name), do: {:ok, v}

  defp to_leg_struct(attrs, rule) do
    %SplitRuleLeg{
      split_rule_id: rule.id,
      split_type: attrs[:split_type],
      value: attrs[:value],
      merchant_id: rule.merchant_id
    }
  end

  defp rule_data(%SplitRule{} = r) do
    %{
      public_id: r.public_id,
      name: r.name,
      description: r.description,
      mode: r.mode,
      active: r.active,
      legs: leg_list(r),
      inserted_at: r.inserted_at,
      updated_at: Map.get(r, :updated_at)
    }
  end

  defp leg_list(%SplitRule{legs: legs}) when is_list(legs) do
    Enum.map(legs, &leg_data/1)
  end

  defp leg_list(_), do: []

  defp leg_data(%SplitRuleLeg{} = l) do
    %{
      id: l.id,
      split_type: l.split_type,
      value: l.value,
      recipient_merchant_id: l.merchant_id
    }
  end
end
