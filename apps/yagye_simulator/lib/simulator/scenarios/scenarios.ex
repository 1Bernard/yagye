defmodule Simulator.Scenarios do
  @moduledoc false

  import Ecto.Query

  alias Simulator.Repo
  alias Simulator.Scenarios.Schemas.Scenario

  def get_default do
    Repo.one(from s in Scenario, where: s.is_default == true and s.active == true, limit: 1)
  end

  def get(id) do
    case Repo.get(Scenario, id) do
      nil -> {:error, :not_found}
      s -> {:ok, s}
    end
  end

  def create(attrs) do
    %Scenario{}
    |> Scenario.changeset(attrs)
    |> Repo.insert()
  end

  def list do
    Repo.all(from s in Scenario, order_by: [asc: s.name])
  end
end
