defmodule YagyeCoreWeb.ApiSpec do
  @moduledoc false

  @behaviour OpenApiSpex.OpenApi

  alias OpenApiSpex.{Components, Info, OpenApi, Paths, SecurityScheme, Server}
  alias YagyeCoreWeb.{Endpoint, Router}

  @impl OpenApi
  def spec do
    %OpenApi{
      servers: [Server.from_endpoint(Endpoint)],
      info: %Info{
        title: "Yagye API",
        version: "2026-01-01",
        description: "Payment orchestration, settlement and reconciliation API"
      },
      components: %Components{
        securitySchemes: %{
          "bearer_auth" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            description: "API key — prefix with Bearer or use X-API-Key header"
          }
        }
      },
      security: [%{"bearer_auth" => []}],
      paths: Paths.from_router(Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
