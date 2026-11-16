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

  # Returns {symbol, number_string} for hero display with separate styling.
  def format_amount_parts(amount, currency) when is_integer(amount) do
    {currency_symbol(currency), :erlang.float_to_binary(amount / 100.0, decimals: 2)}
  end

  def format_amount_parts(_, _), do: {"", "—"}

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

  # Renders a simple SVG barcode from the hex chars in a public_id.
  def barcode_svg(public_id) do
    hex = String.replace(public_id, ~r/[^0-9a-fA-F]/, "")
    chars = String.slice(hex, 0, 32)

    {rects, total_w} =
      chars
      |> String.graphemes()
      |> Enum.reduce({[], 0}, fn c, {rects, x} ->
        n =
          case Integer.parse(c, 16) do
            {v, _} -> v
            :error -> 7
          end

        bar = Integer.mod(n, 4) + 1
        gap = Integer.mod(n, 3) + 1
        rect = ~s(<rect x="#{x}" y="0" width="#{bar}" height="60"/>)
        {[rect | rects], x + bar + gap}
      end)

    bars = rects |> Enum.reverse() |> Enum.join()
    vw = max(total_w, 1)

    Phoenix.HTML.raw("""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{vw} 60"
         preserveAspectRatio="none" style="width:240px;height:48px;fill:#111827;display:block">
      #{bars}
    </svg>
    """)
  end

  defp currency_symbol("GHS"), do: "GH₵"
  defp currency_symbol("USD"), do: "$"
  defp currency_symbol("EUR"), do: "€"
  defp currency_symbol("GBP"), do: "£"
  defp currency_symbol(c), do: "#{c} "
end
