defmodule YagyeCore.ExAwsHttpStub do
  @moduledoc false
  # Lightweight HTTP stub for ExAws in the test environment.
  # Every request returns 200 with an empty XML body — enough for S3 put_object
  # and similar write operations to succeed without a real S3 endpoint.
  # Set via `config :ex_aws, :http_client, YagyeCore.ExAwsHttpStub` in test.exs.

  def request(_method, _url, _body, _headers, _opts) do
    {:ok, %{status_code: 200, headers: [], body: ""}}
  end
end
