defmodule YagyeCoreWeb.ErrorJSON do
  @moduledoc false

  def render("404.json", _assigns) do
    %{
      error: %{
        type: "invalid_request_error",
        code: "not_found",
        message: "The requested resource does not exist."
      }
    }
  end

  def render("405.json", _assigns) do
    %{
      error: %{
        type: "invalid_request_error",
        code: "method_not_allowed",
        message: "HTTP method not allowed for this endpoint."
      }
    }
  end

  def render("500.json", _assigns) do
    %{
      error: %{
        type: "api_error",
        code: "internal_error",
        message: "An unexpected error occurred."
      }
    }
  end

  def render(template, _assigns) do
    message = Phoenix.Controller.status_message_from_template(template)
    %{error: %{type: "api_error", code: "server_error", message: message}}
  end
end
