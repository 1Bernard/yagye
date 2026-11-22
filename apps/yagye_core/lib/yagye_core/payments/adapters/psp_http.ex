defmodule YagyeCore.Payments.Adapters.PspHttp do
  @moduledoc false

  # Thin wrappers around Req that attach OpentelemetryReq so every outbound
  # PSP call becomes a child span in the active trace automatically.

  def post(url, opts \\ []) do
    Req.new(url: url) |> OpentelemetryReq.attach() |> Req.post(opts)
  end

  def get(url, opts \\ []) do
    Req.new(url: url) |> OpentelemetryReq.attach() |> Req.get(opts)
  end
end
