defmodule YagyeCoreWeb.Controllers.Settlement.SettlementJSON do
  @moduledoc false

  alias YagyeCore.Settlement.Schemas.{Settlement, SettlementBatch}

  def list(settlements) do
    %{object: "list", data: Enum.map(settlements, &data/1)}
  end

  def data(%Settlement{} = s) do
    %{
      id: s.public_id,
      object: "settlement",
      mode: s.mode,
      currency: s.currency,
      state: s.state,
      period_start: s.period_start,
      period_end: s.period_end,
      expected_gross: s.expected_gross,
      expected_net: s.expected_net,
      reported_net: s.reported_net,
      variance: s.variance,
      provider_settlement_reference: s.provider_settlement_reference,
      value_date: s.value_date,
      inserted_at: s.inserted_at
    }
  end

  def batch_list(batches) do
    %{object: "list", data: Enum.map(batches, &batch_data/1)}
  end

  def batch_data(%SettlementBatch{} = b) do
    %{
      id: b.id,
      object: "settlement_batch",
      mode: b.mode,
      currency: b.currency,
      state: b.state,
      period_start: b.period_start,
      period_end: b.period_end,
      payment_count: b.payment_count,
      gross_amount: b.gross_amount,
      settled_at: b.settled_at,
      inserted_at: b.inserted_at
    }
  end
end
