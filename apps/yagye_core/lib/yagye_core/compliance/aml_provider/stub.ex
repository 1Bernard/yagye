defmodule YagyeCore.Compliance.AmlProvider.Stub do
  @moduledoc "Stub AML provider — always returns clean. Used in dev and test."
  @behaviour YagyeCore.Compliance.AmlProvider

  @impl true
  def enrol(%{name: name} = _subject) do
    {:ok, %{provider_id: "stub_#{Uniq.UUID.uuid7()}", status: "clean", name: name}}
  end

  def enrol(subject), do: enrol(Map.put_new(subject, :name, "unknown"))

  @impl true
  def refresh(_provider_id) do
    {:ok, %{status: "clean", hits: []}}
  end

  @impl true
  def fetch_hit(provider_hit_id) do
    {:ok, %{id: provider_hit_id, status: "false_positive", detail: "stub"}}
  end
end
