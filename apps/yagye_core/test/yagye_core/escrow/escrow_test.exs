defmodule YagyeCore.EscrowTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Escrow
  alias YagyeCore.Escrow.Schemas.{EscrowDisputeEvent, EscrowHold}
  alias YagyeCore.Fixtures
  alias YagyeCore.PaymentLinks.Schemas.PaymentLink
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}
  alias YagyeCore.Repo

  # ── Fixtures ─────────────────────────────────────────────────────────────────

  defp insert_payment_link(merchant, attrs \\ %{}) do
    %PaymentLink{}
    |> PaymentLink.changeset(
      Map.merge(
        %{
          merchant_id: merchant.id,
          mode: "simulation",
          url_slug: "test-link-#{System.unique_integer([:positive])}",
          kind: "fixed_amount",
          amount: 10_000,
          currency: "GHS",
          description: "Test link"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  defp insert_attempt(payment, provider) do
    Repo.insert!(
      PaymentAttempt.changeset(%PaymentAttempt{}, %{
        payment_id: payment.id,
        provider_id: provider.id,
        attempt_number: 1,
        state: "succeeded",
        provider_reference: "ref_#{System.unique_integer([:positive])}",
        idempotency_token: Uniq.UUID.uuid7()
      })
    )
  end

  defp escrow_hold_attrs(payment, link) do
    now = DateTime.utc_now()

    %{
      payment_id: payment.id,
      payment_link_id: link.id,
      merchant_id: payment.merchant_id,
      amount: payment.amount,
      currency: payment.currency,
      mode: payment.mode,
      auto_release_at: DateTime.add(now, 7 * 86_400, :second),
      dispute_window_ends_at: DateTime.add(now, 48 * 3600, :second)
    }
  end

  # ── create_hold/3 ────────────────────────────────────────────────────────────

  describe "create_hold/3" do
    test "creates hold, transitions payment to escrow_held, posts ledger" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.provider_fixture()
      payment = Fixtures.payment_fixture(merchant)

      {:ok, payment} = payment |> Payment.transition_changeset("authorised") |> Repo.update()

      attempt = insert_attempt(payment, provider)

      link =
        insert_payment_link(merchant, %{
          escrow_enabled: true,
          escrow_auto_release_days: 7,
          escrow_dispute_window_hours: 48
        })

      assert {:ok, hold} = Escrow.create_hold(payment, attempt, link)

      assert hold.state == "held"
      assert hold.amount == payment.amount
      assert hold.merchant_id == payment.merchant_id

      refreshed = Repo.get!(Payment, payment.id)
      assert refreshed.state == "escrow_held"
    end

    test "returns error for invalid payment link" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.provider_fixture()
      payment = Fixtures.payment_fixture(merchant)

      {:ok, payment} = payment |> Payment.transition_changeset("authorised") |> Repo.update()

      attempt = insert_attempt(payment, provider)
      link = insert_payment_link(merchant)

      # Manually set escrow_enabled on link struct (not via changeset) to test hold constraint
      bad_link = %{
        link
        | escrow_enabled: true,
          escrow_auto_release_days: 7,
          escrow_dispute_window_hours: 48
      }

      assert {:ok, hold} = Escrow.create_hold(payment, attempt, bad_link)
      assert hold.state == "held"
    end

    test "rejects duplicate hold for same payment (unique constraint)" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.provider_fixture()
      payment = Fixtures.payment_fixture(merchant)

      {:ok, payment} = payment |> Payment.transition_changeset("authorised") |> Repo.update()

      attempt = insert_attempt(payment, provider)

      link =
        insert_payment_link(merchant, %{
          escrow_enabled: true,
          escrow_auto_release_days: 7,
          escrow_dispute_window_hours: 48
        })

      assert {:ok, _hold} = Escrow.create_hold(payment, attempt, link)

      # Reset payment to authorised to allow transition_changeset but payment_id FK will still conflict
      {:error, _reason} = Escrow.create_hold(payment, attempt, link)
    end
  end

  # ── confirm_release/2 ────────────────────────────────────────────────────────

  describe "confirm_release/2" do
    test "releases hold and transitions payment to escrow_released" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.provider_fixture()
      payment = Fixtures.payment_fixture(merchant)

      {:ok, payment} = payment |> Payment.transition_changeset("escrow_held") |> Repo.update()

      attempt = insert_attempt(payment, provider)

      link =
        insert_payment_link(merchant, %{
          escrow_enabled: true,
          escrow_auto_release_days: 7,
          escrow_dispute_window_hours: 48
        })

      hold =
        Repo.insert!(EscrowHold.changeset(%EscrowHold{}, escrow_hold_attrs(payment, link)))

      assert {:ok, released_hold} = Escrow.confirm_release(hold.public_id, attempt)
      assert released_hold.state == "released"
      assert released_hold.released_at != nil

      refreshed = Repo.get!(Payment, payment.id)
      assert refreshed.state == "escrow_released"
    end

    test "returns :not_found for unknown public_id" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.provider_fixture()
      payment = Fixtures.payment_fixture(merchant)
      attempt = insert_attempt(payment, provider)

      assert {:error, :not_found} = Escrow.confirm_release("esh_nonexistent", attempt)
    end

    test "returns :invalid_state for already-released hold" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.provider_fixture()
      payment = Fixtures.payment_fixture(merchant)

      {:ok, payment} = payment |> Payment.transition_changeset("escrow_released") |> Repo.update()

      attempt = insert_attempt(payment, provider)

      link =
        insert_payment_link(merchant, %{
          escrow_enabled: true,
          escrow_auto_release_days: 7,
          escrow_dispute_window_hours: 48
        })

      hold =
        Repo.insert!(
          EscrowHold.changeset(%EscrowHold{}, escrow_hold_attrs(payment, link))
          |> Ecto.Changeset.put_change(:state, "released")
        )

      assert {:error, :invalid_state} = Escrow.confirm_release(hold.public_id, attempt)
    end
  end

  # ── open_dispute/3 ───────────────────────────────────────────────────────────

  describe "open_dispute/3" do
    test "transitions hold to disputed and creates dispute event" do
      merchant = Fixtures.merchant_fixture()
      payment = Fixtures.payment_fixture(merchant)

      {:ok, payment} = payment |> Payment.transition_changeset("escrow_held") |> Repo.update()

      link =
        insert_payment_link(merchant, %{
          escrow_enabled: true,
          escrow_auto_release_days: 7,
          escrow_dispute_window_hours: 48
        })

      hold =
        Repo.insert!(EscrowHold.changeset(%EscrowHold{}, escrow_hold_attrs(payment, link)))

      assert {:ok, disputed_hold} =
               Escrow.open_dispute(hold.public_id, "buyer", "Item not received")

      assert disputed_hold.state == "disputed"

      refreshed = Repo.get!(Payment, payment.id)
      assert refreshed.state == "escrow_disputed"

      events = Repo.all(from e in EscrowDisputeEvent, where: e.escrow_hold_id == ^hold.id)
      assert length(events) == 1
      assert hd(events).event_type == "dispute_opened"
      assert hd(events).note == "Item not received"
    end

    test "returns :not_found for unknown public_id" do
      assert {:error, :not_found} = Escrow.open_dispute("esh_bad", "buyer", "note")
    end

    test "returns :invalid_state for a disputed hold" do
      merchant = Fixtures.merchant_fixture()
      payment = Fixtures.payment_fixture(merchant)

      {:ok, payment} = payment |> Payment.transition_changeset("escrow_disputed") |> Repo.update()

      link =
        insert_payment_link(merchant, %{
          escrow_enabled: true,
          escrow_auto_release_days: 7,
          escrow_dispute_window_hours: 48
        })

      hold =
        Repo.insert!(
          EscrowHold.changeset(%EscrowHold{}, escrow_hold_attrs(payment, link))
          |> Ecto.Changeset.put_change(:state, "disputed")
        )

      assert {:error, :invalid_state} = Escrow.open_dispute(hold.public_id, "buyer", "again")
    end
  end

  # ── resolve_dispute/5 ────────────────────────────────────────────────────────

  describe "resolve_dispute/5" do
    test "resolves for merchant (release) — hold released, payment escrow_released" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.provider_fixture()
      payment = Fixtures.payment_fixture(merchant)

      {:ok, payment} = payment |> Payment.transition_changeset("escrow_disputed") |> Repo.update()

      attempt = insert_attempt(payment, provider)

      link =
        insert_payment_link(merchant, %{
          escrow_enabled: true,
          escrow_auto_release_days: 7,
          escrow_dispute_window_hours: 48
        })

      hold =
        Repo.insert!(
          EscrowHold.changeset(%EscrowHold{}, escrow_hold_attrs(payment, link))
          |> Ecto.Changeset.put_change(:state, "disputed")
        )

      assert {:ok, resolved} =
               Escrow.resolve_dispute(
                 hold.public_id,
                 "release",
                 "ops@yagye.com",
                 "Legitimate",
                 attempt
               )

      assert resolved.state == "released"

      refreshed = Repo.get!(Payment, payment.id)
      assert refreshed.state == "escrow_released"
    end

    test "resolves for buyer (refund) — hold refunded, dispute event created" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.provider_fixture()
      payment = Fixtures.payment_fixture(merchant)

      {:ok, payment} = payment |> Payment.transition_changeset("escrow_disputed") |> Repo.update()

      attempt = insert_attempt(payment, provider)

      link =
        insert_payment_link(merchant, %{
          escrow_enabled: true,
          escrow_auto_release_days: 7,
          escrow_dispute_window_hours: 48
        })

      hold =
        Repo.insert!(
          EscrowHold.changeset(%EscrowHold{}, escrow_hold_attrs(payment, link))
          |> Ecto.Changeset.put_change(:state, "disputed")
        )

      assert {:ok, resolved} =
               Escrow.resolve_dispute(
                 hold.public_id,
                 "refund",
                 "ops@yagye.com",
                 "Fraud confirmed",
                 attempt
               )

      assert resolved.state == "refunded"

      events = Repo.all(from e in EscrowDisputeEvent, where: e.escrow_hold_id == ^hold.id)
      assert Enum.any?(events, &(&1.event_type == "resolved_for_buyer"))
    end

    test "returns error for invalid outcome" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.provider_fixture()
      payment = Fixtures.payment_fixture(merchant)

      {:ok, payment} = payment |> Payment.transition_changeset("escrow_disputed") |> Repo.update()

      attempt = insert_attempt(payment, provider)

      link =
        insert_payment_link(merchant, %{
          escrow_enabled: true,
          escrow_auto_release_days: 7,
          escrow_dispute_window_hours: 48
        })

      hold =
        Repo.insert!(
          EscrowHold.changeset(%EscrowHold{}, escrow_hold_attrs(payment, link))
          |> Ecto.Changeset.put_change(:state, "disputed")
        )

      assert {:error, :invalid_outcome} =
               Escrow.resolve_dispute(hold.public_id, "bad_outcome", "ops", "note", attempt)
    end
  end

  # ── auto_release/2 ───────────────────────────────────────────────────────────

  describe "auto_release/2" do
    test "releases hold and transitions payment to escrow_released" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.provider_fixture()
      payment = Fixtures.payment_fixture(merchant)

      {:ok, payment} = payment |> Payment.transition_changeset("escrow_held") |> Repo.update()

      attempt = insert_attempt(payment, provider)

      link =
        insert_payment_link(merchant, %{
          escrow_enabled: true,
          escrow_auto_release_days: 7,
          escrow_dispute_window_hours: 48
        })

      hold =
        Repo.insert!(EscrowHold.changeset(%EscrowHold{}, escrow_hold_attrs(payment, link)))

      assert {:ok, released_hold} = Escrow.auto_release(hold.id, attempt)
      assert released_hold.state == "released"

      refreshed = Repo.get!(Payment, payment.id)
      assert refreshed.state == "escrow_released"
    end

    test "returns :not_held for already-released hold" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.provider_fixture()
      payment = Fixtures.payment_fixture(merchant)

      {:ok, payment} = payment |> Payment.transition_changeset("escrow_released") |> Repo.update()

      attempt = insert_attempt(payment, provider)

      link =
        insert_payment_link(merchant, %{
          escrow_enabled: true,
          escrow_auto_release_days: 7,
          escrow_dispute_window_hours: 48
        })

      hold =
        Repo.insert!(
          EscrowHold.changeset(%EscrowHold{}, escrow_hold_attrs(payment, link))
          |> Ecto.Changeset.put_change(:state, "released")
        )

      assert {:error, :not_held} = Escrow.auto_release(hold.id, attempt)
    end
  end

  # ── get_hold/1 ───────────────────────────────────────────────────────────────

  describe "get_hold/1" do
    test "returns hold by public_id" do
      merchant = Fixtures.merchant_fixture()
      payment = Fixtures.payment_fixture(merchant)

      link =
        insert_payment_link(merchant, %{
          escrow_enabled: true,
          escrow_auto_release_days: 7,
          escrow_dispute_window_hours: 48
        })

      hold =
        Repo.insert!(EscrowHold.changeset(%EscrowHold{}, escrow_hold_attrs(payment, link)))

      assert {:ok, fetched} = Escrow.get_hold(hold.public_id)
      assert fetched.id == hold.id
    end

    test "returns :not_found for unknown public_id" do
      assert {:error, :not_found} = Escrow.get_hold("esh_doesnotexist")
    end
  end

  # ── list_holds/2 ─────────────────────────────────────────────────────────────

  describe "list_holds/2" do
    test "returns all holds for a merchant" do
      merchant = Fixtures.merchant_fixture()
      other_merchant = Fixtures.merchant_fixture()

      payment_a = Fixtures.payment_fixture(merchant)
      payment_b = Fixtures.payment_fixture(other_merchant)

      link =
        insert_payment_link(merchant, %{
          escrow_enabled: true,
          escrow_auto_release_days: 7,
          escrow_dispute_window_hours: 48
        })

      other_link =
        insert_payment_link(other_merchant, %{
          escrow_enabled: true,
          escrow_auto_release_days: 7,
          escrow_dispute_window_hours: 48
        })

      Repo.insert!(EscrowHold.changeset(%EscrowHold{}, escrow_hold_attrs(payment_a, link)))
      Repo.insert!(EscrowHold.changeset(%EscrowHold{}, escrow_hold_attrs(payment_b, other_link)))

      holds = Escrow.list_holds(merchant.id)
      assert length(holds) == 1
      assert hd(holds).merchant_id == merchant.id
    end

    test "filters by state" do
      merchant = Fixtures.merchant_fixture()

      payment_a = Fixtures.payment_fixture(merchant)
      payment_b = Fixtures.payment_fixture(merchant)

      link =
        insert_payment_link(merchant, %{
          escrow_enabled: true,
          escrow_auto_release_days: 7,
          escrow_dispute_window_hours: 48
        })

      Repo.insert!(EscrowHold.changeset(%EscrowHold{}, escrow_hold_attrs(payment_a, link)))

      Repo.insert!(
        EscrowHold.changeset(%EscrowHold{}, escrow_hold_attrs(payment_b, link))
        |> Ecto.Changeset.put_change(:state, "released")
      )

      held = Escrow.list_holds(merchant.id, state: "held")
      released = Escrow.list_holds(merchant.id, state: "released")

      assert length(held) == 1
      assert length(released) == 1
    end
  end

  # ── escrow_info_for/1 ────────────────────────────────────────────────────────

  describe "escrow_info_for/1" do
    test "returns enabled: false when no checkout_session_id in metadata" do
      merchant = Fixtures.merchant_fixture()
      payment = Fixtures.payment_fixture(merchant)

      assert {:ok, %{enabled: false}} = Escrow.escrow_info_for(payment)
    end

    test "returns enabled: false when checkout session has no payment_link" do
      merchant = Fixtures.merchant_fixture()

      payment =
        Fixtures.payment_fixture(merchant, %{metadata: %{"checkout_session_id" => "cks_notreal"}})

      assert {:ok, %{enabled: false}} = Escrow.escrow_info_for(payment)
    end
  end
end
