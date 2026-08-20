defmodule YagyeCore.Providers do
  @moduledoc false

  alias YagyeCore.Providers.Schemas.Provider
  alias YagyeCore.Repo

  @simulator_code "simulator"

  def get_provider_for_mode("simulation") do
    case Repo.get_by(Provider, code: @simulator_code, active: true) do
      nil -> {:error, :no_provider}
      provider -> {:ok, provider}
    end
  end

  def get_provider_for_mode(mode) when mode in ["sandbox", "live"] do
    {:error, {:no_provider_for_mode, mode}}
  end
end
