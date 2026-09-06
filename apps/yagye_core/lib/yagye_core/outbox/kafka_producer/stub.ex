defmodule YagyeCore.Outbox.KafkaProducer.Stub do
  @moduledoc false

  def publish(_envelope), do: :ok
end
