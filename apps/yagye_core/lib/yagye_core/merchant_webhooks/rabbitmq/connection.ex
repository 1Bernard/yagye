defmodule YagyeCore.MerchantWebhooks.RabbitMQ.Connection do
  @moduledoc """
  Singleton AMQP connection shared across the webhook delivery subsystem.
  Supervised as a named GenServer; reconnects automatically on crash.
  """

  use GenServer

  require Logger

  alias YagyeCore.MerchantWebhooks.RabbitMQ.Topology

  @name __MODULE__

  # ── Public API ────────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @doc "Returns the open AMQP connection, or {:error, :not_connected}."
  def get do
    GenServer.call(@name, :get)
  end

  # ── GenServer ─────────────────────────────────────────────────────────────────

  @impl GenServer
  def init(_opts) do
    send(self(), :connect)
    {:ok, %{conn: nil}}
  end

  @impl GenServer
  def handle_call(:get, _from, %{conn: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call(:get, _from, %{conn: conn} = state) do
    {:reply, {:ok, conn}, state}
  end

  @impl GenServer
  def handle_info(:connect, state) do
    case AMQP.Connection.open(amqp_url()) do
      {:ok, conn} ->
        Process.monitor(conn.pid)
        Logger.info("RabbitMQ connected", url: sanitised_url())
        send(self(), :setup_topology)
        {:noreply, %{state | conn: conn}}

      {:error, reason} ->
        Logger.warning("RabbitMQ connection failed, retrying in 5s", reason: inspect(reason))
        Process.send_after(self(), :connect, 5_000)
        {:noreply, state}
    end
  end

  def handle_info(:setup_topology, state) do
    Topology.setup!()
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.warning("RabbitMQ connection dropped", reason: inspect(reason))
    Process.send_after(self(), :connect, 3_000)
    {:noreply, %{state | conn: nil}}
  end

  # ── Private ───────────────────────────────────────────────────────────────────

  defp amqp_url do
    Application.get_env(:yagye_core, :rabbitmq_url, "amqp://guest:guest@localhost:5672")
  end

  defp sanitised_url do
    amqp_url() |> String.replace(~r/:[^:@]+@/, ":***@")
  end
end
