defmodule Mix.Tasks.Yagye.S3.Setup do
  @shortdoc "Creates required S3 buckets in Floci (local) or real AWS."
  @moduledoc """
  Ensures the S3 buckets Yagye needs exist.

      mix yagye.s3.setup

  Safe to run multiple times — existing buckets are left untouched.
  In development this targets Floci (localhost:4566). In production it
  targets real AWS using the credentials in the environment.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Application.ensure_all_started(:ex_aws)
    Application.ensure_all_started(:hackney)

    bucket =
      Application.get_env(:yagye_core, :document_store, [])
      |> Keyword.get(:bucket, "yagye-kyb-documents")

    buckets = [bucket]

    Mix.shell().info("Setting up S3 buckets...")

    region = Application.get_env(:ex_aws, :region, "us-east-1")

    Enum.each(buckets, fn bucket ->
      if bucket_exists?(bucket) do
        Mix.shell().info("  [exists] #{bucket}")
      else
        create_bucket(bucket, region)
      end
    end)

    Mix.shell().info("Done.")
  end

  defp bucket_exists?(bucket) do
    case ExAws.S3.head_bucket(bucket) |> ExAws.request() do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp create_bucket(bucket, region) do
    case ExAws.S3.put_bucket(bucket, region) |> ExAws.request() do
      {:ok, _} ->
        Mix.shell().info("  [created] #{bucket}")

      {:error, reason} ->
        Mix.shell().error("  [error] #{bucket}: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end
end
