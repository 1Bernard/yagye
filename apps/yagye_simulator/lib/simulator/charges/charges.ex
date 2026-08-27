defmodule Simulator.Charges do
  @moduledoc false

  import Ecto.Query

  alias Simulator.Charges.Schemas.{Charge, ChargeEvent, NameEnquiry, WalletPrompt}
  alias Simulator.OutcomeEngine
  alias Simulator.Repo
  alias Simulator.Scenarios
  alias Simulator.Webhooks.WebhookDeliveryWorker

  # ── Public API ───────────────────────────────────────────────────────────────

  def create_charge(account, attrs) do
    seed = attrs[:seed]
    scenario = resolve_scenario(account, attrs[:scenario_id])

    case attrs.instrument_type do
      "WALLET" -> create_wallet_charge(account, attrs, scenario, seed)
      _card_or_bank -> create_synchronous_charge(account, attrs, scenario, seed)
    end
  end

  def get_by_ref(charge_ref) do
    case Repo.get_by(Charge, charge_ref: charge_ref) do
      nil -> {:error, :not_found}
      charge -> {:ok, charge}
    end
  end

  def name_enquiry(account, attrs) do
    outcome = OutcomeEngine.name_enquiry_outcome(attrs.msisdn)
    account_name = if outcome == :found, do: "#{attrs.network} Subscriber", else: nil

    %NameEnquiry{}
    |> NameEnquiry.changeset(%{
      account_id: account.id,
      charge_id: attrs[:charge_id],
      network: attrs.network,
      msisdn: attrs.msisdn,
      outcome: Atom.to_string(outcome) |> String.upcase(),
      account_name: account_name,
      delay_ms: attrs[:delay_ms] || 200,
      queried_at: DateTime.utc_now()
    })
    |> Repo.insert()
    |> case do
      {:ok, enquiry} -> {:ok, enquiry}
      {:error, _} = err -> err
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp create_synchronous_charge(account, attrs, scenario, seed) do
    outcome = OutcomeEngine.card_outcome(scenario, seed)
    now = DateTime.utc_now()

    charge_attrs =
      base_charge_attrs(account, attrs, scenario, seed)
      |> Map.merge(outcome_fields(outcome, attrs.amount_minor, account, scenario, now))

    Repo.transaction(fn ->
      with {:ok, charge} <- insert_charge(charge_attrs),
           {:ok, _event} <- insert_charge_event(charge, "charge.created", nil, charge.state) do
        charge
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp create_wallet_charge(account, attrs, scenario, seed) do
    outcome =
      OutcomeEngine.msisdn_wallet_outcome(attrs[:msisdn]) ||
        OutcomeEngine.wallet_outcome(scenario, seed)
    now = DateTime.utc_now()
    delay_ms = attrs[:approval_delay_ms] || 3_000

    charge_attrs =
      base_charge_attrs(account, attrs, scenario, seed)
      |> Map.put(:state, "PENDING_AUTH")

    Repo.transaction(fn ->
      with {:ok, charge} <- insert_charge(charge_attrs),
           {:ok, _event} <- insert_charge_event(charge, "charge.created", nil, "PENDING_AUTH"),
           {:ok, _prompt} <- insert_wallet_prompt(charge, attrs, outcome, now),
           {:ok, _job} <-
             WebhookDeliveryWorker.new(
               %{account_id: account.id, charge_ref: charge.charge_ref},
               schedule_in: max(div(delay_ms, 1000), 1)
             )
             |> Oban.insert() do
        charge
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp base_charge_attrs(account, attrs, scenario, seed) do
    %{
      account_id: account.id,
      charge_ref: "gw_" <> Uniq.UUID.uuid7(),
      idempotency_key: attrs[:idempotency_key],
      amount_minor: attrs.amount_minor,
      currency: attrs.currency,
      instrument_type: attrs.instrument_type,
      scenario_id: scenario && scenario.id,
      seed: seed
    }
  end

  defp outcome_fields(:authorised, amount, account, scenario, now) do
    auth_hours = (scenario && scenario.auth_validity_hours) || 24
    arn = if arn_at_auth?(scenario), do: generate_arn(), else: nil

    %{
      state: "AUTHORISED",
      authorised_amount_minor: amount,
      captured_amount_minor: amount,
      auth_code: ("AUTH" <> :crypto.strong_rand_bytes(4)) |> Base.encode16(),
      rrn: generate_rrn(account),
      arn: arn,
      authorised_at: now,
      auth_expires_at: DateTime.add(now, auth_hours * 3_600, :second)
    }
  end

  defp outcome_fields(:declined, _amount, _account, _scenario, _now) do
    %{state: "DECLINED", decline_code: "INSUFFICIENT_FUNDS"}
  end

  defp outcome_fields(:timeout, _amount, _account, _scenario, _now) do
    %{state: "PENDING_AUTH"}
  end

  defp outcome_fields(:provider_error, _amount, _account, _scenario, _now) do
    %{state: "PENDING_AUTH"}
  end

  defp insert_charge(attrs) do
    %Charge{}
    |> Charge.changeset(attrs)
    |> Repo.insert()
  end

  defp insert_charge_event(charge, event_type, from_state, to_state) do
    next_seq =
      from(e in ChargeEvent, where: e.charge_id == ^charge.id, select: count())
      |> Repo.one()

    %ChargeEvent{}
    |> ChargeEvent.changeset(%{
      charge_id: charge.id,
      sequence: next_seq + 1,
      event_type: event_type,
      from_state: from_state,
      to_state: to_state,
      payload: %{}
    })
    |> Repo.insert()
  end

  defp insert_wallet_prompt(charge, attrs, outcome, now) do
    {prompt_state, decline_code} =
      case outcome do
        :approved -> {"APPROVED", nil}
        :declined -> {"DECLINED", "DECLINED_BY_CUSTOMER"}
        :expired -> {"EXPIRED", nil}
        :insufficient_funds -> {"DECLINED", "INSUFFICIENT_FUNDS"}
        :not_registered -> {"DECLINED", "NOT_REGISTERED"}
      end

    %WalletPrompt{}
    |> WalletPrompt.changeset(%{
      charge_id: charge.id,
      network: attrs[:network] || "MTN",
      msisdn: attrs[:msisdn] || "0240000001",
      prompt_state: prompt_state,
      decline_code: decline_code,
      approval_delay_ms: attrs[:approval_delay_ms] || 3_000,
      sent_at: now,
      resolved_at: now
    })
    |> Repo.insert()
  end

  defp resolve_scenario(account, nil) do
    case account.default_scenario do
      %Ecto.Association.NotLoaded{} ->
        loaded = Repo.preload(account, :default_scenario)
        loaded.default_scenario || Scenarios.get_default()

      nil ->
        Scenarios.get_default()

      scenario ->
        scenario
    end
  end

  defp resolve_scenario(_account, scenario_id) do
    case Scenarios.get(scenario_id) do
      {:ok, s} -> s
      _ -> nil
    end
  end

  defp arn_at_auth?(nil), do: true
  defp arn_at_auth?(scenario), do: scenario.arn_issued_at == "authorisation"

  defp generate_arn, do: "ARN" <> (:crypto.strong_rand_bytes(9) |> Base.encode16())
  defp generate_rrn(account), do: ("RRN" <> String.slice(account.id, 0, 8)) |> String.upcase()
end
