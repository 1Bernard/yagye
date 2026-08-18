defmodule YagyeCoreWeb.ErrorJSONTest do
  use YagyeCoreWeb.ConnCase, async: true

  test "renders 404" do
    assert YagyeCoreWeb.ErrorJSON.render("404.json", %{}) == %{
             error: %{type: "invalid_request_error", code: "not_found", message: "The requested resource does not exist."}
           }
  end

  test "renders 500" do
    assert YagyeCoreWeb.ErrorJSON.render("500.json", %{}) == %{
             error: %{type: "api_error", code: "internal_error", message: "An unexpected error occurred."}
           }
  end
end
