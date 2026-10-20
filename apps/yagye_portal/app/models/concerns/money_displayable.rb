# frozen_string_literal: true

module MoneyDisplayable
  private

  def format_minor_units(minor_units, currency_code = "GHS")
    return "—" if minor_units.nil?
    n = minor_units.to_f / 100
    whole, frac = sprintf("%.2f", n).split(".")
    "#{currency_code} #{whole.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse}.#{frac}"
  end
end
