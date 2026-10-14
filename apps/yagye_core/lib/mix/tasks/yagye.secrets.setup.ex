defmodule Mix.Tasks.Yagye.Secrets.Setup do
  @shortdoc "Seeds PSP credentials into Secrets Manager (Floci in dev, real AWS in prod)."
  @moduledoc """
  Creates or updates Secrets Manager secrets for Yagye PSP credentials.

      mix yagye.secrets.setup

  Safe to run multiple times — existing secrets are updated in place.

  In development this targets Floci (localhost:4566). In staging/production it
  targets real AWS using the credentials in the environment.

  ## Secret layout

  Each secret holds the JSON payload that would otherwise live in
  `provider_credentials.encrypted_payload`. The DB row stores only the
  secret name as a pointer.

  ## Environment variables (dev/sandbox values)

  MTN MoMo sandbox credentials are read from env vars so they are never
  checked into version control. Obtain these from momodeveloper.mtn.com:

      MTN_SANDBOX_SUBSCRIPTION_KEY=<key>
      MTN_SANDBOX_API_USER_ID=<uuid>
      MTN_SANDBOX_API_KEY=<key>
  """

  use Boundary, classify_to: YagyeCore
  use Mix.Task

  alias YagyeCore.Shared.SecretsManager

  @impl Mix.Task
  def run(_args) do
    Application.ensure_all_started(:ex_aws)
    Application.ensure_all_started(:hackney)

    Mix.shell().info("Setting up Secrets Manager secrets...")

    mtn_sandbox()

    Mix.shell().info("Done.")
  end

  defp mtn_sandbox do
    name = secret_name("mtn_momo_gh", "sandbox")

    payload = %{
      "subscription_key" => System.get_env("MTN_SANDBOX_SUBSCRIPTION_KEY", "REPLACE_ME"),
      "api_user_id" => System.get_env("MTN_SANDBOX_API_USER_ID", "REPLACE_ME"),
      "api_key" => System.get_env("MTN_SANDBOX_API_KEY", "REPLACE_ME"),
      "target_environment" => "sandbox"
    }

    case SecretsManager.put_secret(name, payload) do
      :ok -> Mix.shell().info("  [ok] #{name}")
      {:error, reason} -> Mix.shell().error("  [error] #{name}: #{inspect(reason)}")
    end
  end

  defp secret_name(provider_code, mode) do
    env = Application.get_env(:yagye_core, :env, Mix.env()) |> to_string()
    "yagye/#{env}/providers/#{provider_code}/#{mode}"
  end
end
