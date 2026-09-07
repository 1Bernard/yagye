defmodule YagyeCore.CheckoutSessions do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias YagyeCore.Checkout.Schemas.{CheckoutEvent, CheckoutLineItem, CheckoutSession}
  alias YagyeCore.Outbox
  alias YagyeCore.PaymentLinks
  alias YagyeCore.PaymentLinks.Schemas.PaymentLink
  alias YagyeCore.Repo

  @token_bytes 32
  # Sessions expire after 30 minutes by default; links can set their own expiry.
  @default_ttl_seconds 1_800

  # ── Public API ───────────────────────────────────────────────────────────────

  @doc """
  Creates a CheckoutSession from a PaymentLink slug.
  Validates the link is active and not expired/exhausted before creating.
  Returns {:ok, {session, url_token}} — the raw url_token is returned ONCE
  for embedding in the hosted checkout URL; only its hash is stored.
  """
  def create_from_link(slug, attrs \\ %{}) do
    with {:ok, link} <- PaymentLinks.get_link_by_slug(slug),
         :ok <- validate_link_usable(link) do
      {url_token, url_token_hash} = generate_token_pair()
      line_items = attrs[:line_items] || []
      session_attrs = build_link_session_attrs(link, attrs, url_token_hash)

      Multi.new()
      |> Multi.insert(:session, CheckoutSession.changeset(%CheckoutSession{}, session_attrs))
      |> Multi.run(:line_items, fn _repo, %{session: session} ->
        insert_line_items(session, line_items)
      end)
      |> Multi.insert(:created_event, fn %{session: session} ->
        event_changeset(session, "viewed", %{source: "payment_link"})
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{session: session}} ->
          {:ok, {Repo.preload(session, :line_items), url_token}}

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Creates a CheckoutSession directly (API-first, not from a payment link).
  Intended for server-side checkout where the merchant builds the session.
  Returns {:ok, {session, url_token}}.
  """
  def create_session(merchant_id, attrs) do
    {url_token, url_token_hash} = generate_token_pair()
    expires_at = DateTime.add(DateTime.utc_now(), @default_ttl_seconds, :second)

    session_attrs =
      attrs
      |> Map.put(:merchant_id, merchant_id)
      |> Map.put(:url_token_hash, url_token_hash)
      |> Map.put_new(:expires_at, expires_at)
      |> Map.put_new(:merchant_reference, generate_reference())

    line_items = Map.pop(session_attrs, :line_items) |> elem(0) || []
    session_attrs = Map.delete(session_attrs, :line_items)

    Multi.new()
    |> Multi.insert(:session, CheckoutSession.changeset(%CheckoutSession{}, session_attrs))
    |> Multi.run(:line_items, fn _repo, %{session: session} ->
      insert_line_items(session, line_items)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{session: session}} ->
        {:ok, {Repo.preload(session, :line_items), url_token}}

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  @doc """
  Looks up a session by its url_token (hashed for comparison).
  Used by the LiveView checkout page on every load.
  """
  def get_session_by_token(url_token) do
    hash = hash_token(url_token)

    case Repo.get_by(CheckoutSession, url_token_hash: hash) do
      nil -> {:error, :not_found}
      session -> {:ok, Repo.preload(session, :line_items)}
    end
  end

  def get_session(public_id, merchant_id) do
    case Repo.get_by(CheckoutSession, public_id: public_id, merchant_id: merchant_id) do
      nil -> {:error, :not_found}
      session -> {:ok, session}
    end
  end

  def list_sessions(merchant_id, opts \\ []) do
    state = Keyword.get(opts, :state)
    payment_link_id = Keyword.get(opts, :payment_link_id)

    base =
      from(cs in CheckoutSession,
        where: cs.merchant_id == ^merchant_id,
        order_by: [desc: cs.inserted_at]
      )

    base = if state, do: where(base, [cs], cs.state == ^state), else: base

    base =
      if payment_link_id,
        do: where(base, [cs], cs.payment_link_id == ^payment_link_id),
        else: base

    {:ok, Repo.all(base)}
  end

  # ── State transitions ────────────────────────────────────────────────────────

  def record_method_selected(%CheckoutSession{} = session, method) do
    Multi.new()
    |> Multi.insert(:event, event_changeset(session, "method_selected", %{method: method}))
    |> Repo.transaction()
    |> case do
      {:ok, _} -> {:ok, session}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  def begin_processing(%CheckoutSession{} = session, payment_id) do
    Multi.new()
    |> Multi.update(:session, CheckoutSession.state_changeset(session, "processing"))
    |> Multi.insert(:event, fn %{session: s} ->
      event_changeset(s, "submitted", %{payment_id: payment_id})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{session: s}} -> {:ok, s}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  def complete_session(%CheckoutSession{} = session, payment_id) do
    now = DateTime.utc_now()

    Multi.new()
    |> Multi.update(
      :session,
      CheckoutSession.state_changeset(session, "completed", %{
        payment_id: payment_id,
        completed_at: now
      })
    )
    |> Multi.insert(:outbox, fn %{session: s} ->
      Outbox.build_changeset(s, "checkout_session.completed", %{
        session_id: s.public_id,
        merchant_id: s.merchant_id,
        payment_id: payment_id,
        total_amount: s.total_amount,
        currency: s.currency,
        mode: s.mode
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{session: s}} -> {:ok, s}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  def expire_session(%CheckoutSession{} = session) do
    Multi.new()
    |> Multi.update(:session, CheckoutSession.state_changeset(session, "expired"))
    |> Multi.insert(:event, fn %{session: s} ->
      event_changeset(s, "abandoned", %{})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{session: s}} -> {:ok, s}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  def cancel_session(%CheckoutSession{} = session) do
    Multi.new()
    |> Multi.update(:session, CheckoutSession.state_changeset(session, "cancelled"))
    |> Repo.transaction()
    |> case do
      {:ok, %{session: s}} -> {:ok, s}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  @doc "Append a raw checkout event (e.g. validation_failed, redirected_3ds, returned)."
  def record_event(%CheckoutSession{} = session, event_type, payload \\ %{}) do
    changeset = event_changeset(session, event_type, payload)

    case Repo.insert(changeset) do
      {:ok, event} -> {:ok, event}
      {:error, cs} -> {:error, cs}
    end
  end

  # ── Expiry sweep ─────────────────────────────────────────────────────────────

  @doc "Marks all open/processing sessions past their expiry as expired. Called by a worker."
  def expire_stale_sessions do
    now = DateTime.utc_now()

    {count, _} =
      Repo.update_all(
        from(cs in CheckoutSession,
          where: cs.state in ["open", "processing"],
          where: cs.expires_at <= ^now
        ),
        set: [state: "expired"]
      )

    {:ok, count}
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp build_link_session_attrs(link, attrs, url_token_hash) do
    %{
      merchant_id: link.merchant_id,
      mode: link.mode,
      url_token_hash: url_token_hash,
      subtotal_amount: link.amount || attrs[:subtotal_amount] || 0,
      tax_amount: attrs[:tax_amount] || 0,
      shipping_amount: attrs[:shipping_amount] || 0,
      discount_amount: attrs[:discount_amount] || 0,
      total_amount: link.amount || attrs[:total_amount] || 0,
      currency: link.currency,
      description: link.description,
      merchant_reference: attrs[:merchant_reference] || generate_reference(),
      collect_email: link.collect_email,
      collect_phone: link.collect_phone,
      collect_name: link.collect_name,
      allowed_methods: effective_methods(link),
      payment_link_id: link.id,
      success_url: attrs[:success_url],
      cancel_url: attrs[:cancel_url],
      metadata: link.metadata,
      expires_at: resolve_expires_at(link, attrs)
    }
  end

  defp resolve_expires_at(%PaymentLink{expires_at: exp}, attrs) when not is_nil(exp) do
    now = DateTime.utc_now()

    if DateTime.compare(exp, now) != :gt do
      exp
    else
      DateTime.add(now, attrs[:ttl_seconds] || @default_ttl_seconds, :second)
    end
  end

  defp resolve_expires_at(_link, attrs) do
    DateTime.add(DateTime.utc_now(), attrs[:ttl_seconds] || @default_ttl_seconds, :second)
  end

  defp generate_token_pair do
    token = Base.url_encode64(:crypto.strong_rand_bytes(@token_bytes), padding: false)
    {token, hash_token(token)}
  end

  defp validate_link_usable(%PaymentLink{active: false}), do: {:error, :link_inactive}
  defp validate_link_usable(%PaymentLink{expires_at: nil}), do: :ok

  defp validate_link_usable(%PaymentLink{expires_at: exp}) do
    if DateTime.compare(exp, DateTime.utc_now()) == :gt, do: :ok, else: {:error, :link_expired}
  end

  defp hash_token(token) do
    token
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end

  defp generate_reference do
    raw = :crypto.strong_rand_bytes(6)
    "REF-" <> Base.hex_encode32(raw, padding: false)
  end

  defp effective_methods(%PaymentLink{allowed_methods: [_ | _] = methods}), do: methods
  defp effective_methods(_link), do: ["mobile_money", "card", "bank_transfer"]

  defp insert_line_items(_session, []), do: {:ok, []}

  defp insert_line_items(session, items) do
    changesets =
      items
      |> Enum.with_index(1)
      |> Enum.map(fn {item, pos} ->
        attrs =
          item
          |> ensure_map()
          |> Map.put(:session_id, session.id)
          |> Map.put(:position, pos)

        CheckoutLineItem.changeset(%CheckoutLineItem{}, attrs)
      end)

    invalid = Enum.find(changesets, &(!&1.valid?))

    if invalid do
      {:error, invalid}
    else
      results = Enum.map(changesets, &Repo.insert/1)
      errors = Enum.filter(results, &match?({:error, _}, &1))

      if Enum.empty?(errors) do
        {:ok, Enum.map(results, fn {:ok, item} -> item end)}
      else
        {:error, hd(errors) |> elem(1)}
      end
    end
  end

  defp ensure_map(m) when is_struct(m), do: Map.from_struct(m)
  defp ensure_map(m), do: m

  defp event_changeset(%CheckoutSession{} = session, event_type, payload) do
    CheckoutEvent.changeset(%CheckoutEvent{}, %{
      session_id: session.id,
      event_type: event_type,
      payload: payload,
      occurred_at: DateTime.utc_now()
    })
  end
end
