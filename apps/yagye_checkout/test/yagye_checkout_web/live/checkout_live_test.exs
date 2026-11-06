defmodule YagyeCheckoutWeb.Live.CheckoutLiveTest do
  use ExUnit.Case, async: true

  alias YagyeCheckoutWeb.Live.CheckoutLive

  describe "sanitize_hex_color/1 and build_dynamic_style/2 (XSS / CSS injection prevention)" do
    test "accepts valid 6-digit hex colors" do
      assert CheckoutLive.sanitize_hex_color("#10B981") == "#10B981"
      assert CheckoutLive.sanitize_hex_color(" #abcdef ") == "#abcdef"
    end

    test "rejects CSS/XSS injection payloads in brand_color" do
      malicious = "#000000; } </style><script>alert(1)</script><style>:root {"
      assert CheckoutLive.sanitize_hex_color(malicious) == nil
      assert CheckoutLive.build_dynamic_style(malicious, nil) == ""
      refute CheckoutLive.build_dynamic_style(malicious, "Inter") =~ "<script>"
    end

    test "renders valid CSS variables for safe hex color" do
      style = CheckoutLive.build_dynamic_style("#10B981", "Inter")
      assert style =~ "--brand: #10B981;"
      assert style =~ "--co-font:"
    end
  end

  describe "external_url?/1" do
    test "rejects javascript: and data: URIs" do
      refute CheckoutLive.external_url?("javascript:alert(1)")
      refute CheckoutLive.external_url?("data:text/html,<script>alert(1)</script>")
      refute CheckoutLive.external_url?("vbscript:msgbox(1)")
    end

    test "rejects internal checkout hosts and accepts valid external merchant http/https URLs" do
      refute CheckoutLive.external_url?("https://pay.yagye.com")
      refute CheckoutLive.external_url?("http://localhost:4002")
      assert CheckoutLive.external_url?("https://merchant.example.com/thank-you")
      assert CheckoutLive.external_url?("http://store.ghana.shop/order/123")
    end
  end
end
