defmodule YagyeCheckoutWeb.ErrorHTML do
  use Phoenix.Component

  def render("404.html", assigns) do
    ~H"""
    <main style="font-family:system-ui;text-align:center;padding:4rem;color:#1a1a2e">
      <h1>Not Found</h1>
      <p>This page could not be found.</p>
    </main>
    """
  end

  def render("500.html", assigns) do
    ~H"""
    <main style="font-family:system-ui;text-align:center;padding:4rem;color:#1a1a2e">
      <h1>Internal Server Error</h1>
      <p>Something went wrong. Please try again.</p>
    </main>
    """
  end
end
