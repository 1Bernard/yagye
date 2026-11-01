defmodule YagyeCoreWeb.Controllers.Public.ReceiptHTML do
  @moduledoc false

  use Phoenix.Component

  embed_templates "receipt_html/*"

  def format_amount(amount, currency) when is_integer(amount) do
    symbol = currency_symbol(currency)
    value = amount / 100.0
    "#{symbol}#{:erlang.float_to_binary(value, decimals: 2)}"
  end

  def format_amount(_, _), do: "—"

  def format_method("mobile_money"), do: "Mobile Money"
  def format_method("card"), do: "Card"
  def format_method("bank_transfer"), do: "Bank Transfer"
  def format_method(m) when is_binary(m), do: String.replace(m, "_", " ") |> String.capitalize()
  def format_method(_), do: "—"

  def format_network(nil), do: nil
  def format_network(n), do: String.upcase(n)

  def format_datetime(nil), do: "—"

  def format_datetime(dt) when is_binary(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, parsed, _} -> format_datetime(parsed)
      _ -> dt
    end
  end

  def format_datetime(%DateTime{} = dt) do
    Calendar.strftime(dt, "%d %b %Y, %I:%M %p UTC")
  end

  def show_powered_by?(settings) do
    Map.get(settings, "show_powered_by", true) != false
  end

  defp currency_symbol("GHS"), do: "GH₵"
  defp currency_symbol("USD"), do: "$"
  defp currency_symbol("EUR"), do: "€"
  defp currency_symbol("GBP"), do: "£"
  defp currency_symbol(c), do: "#{c} "
end
