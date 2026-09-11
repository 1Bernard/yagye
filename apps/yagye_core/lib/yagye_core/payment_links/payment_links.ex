defmodule YagyeCore.PaymentLinks do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias YagyeCore.Merchants
  alias YagyeCore.Outbox
  alias YagyeCore.PaymentLinks.Schemas.PaymentLink
  alias YagyeCore.Repo
  alias YagyeCore.Shared.Pagination

  @url_slug_alphabet "abcdefghijklmnopqrstuvwxyz0123456789"
  @url_slug_length 12

  # ── Public API ───────────────────────────────────────────────────────────────

  def list_links(merchant_id, opts \\ []) do
    active = Keyword.get(opts, :active)

    base =
      from(pl in PaymentLink,
        where: pl.merchant_id == ^merchant_id,
        order_by: [desc: pl.inserted_at]
      )

    base = if is_nil(active), do: base, else: where(base, [pl], pl.active == ^active)
    {:ok, Pagination.paginate(base, :public_id, opts)}
  end

  def get_link(public_id, merchant_id) do
    case Repo.get_by(PaymentLink, public_id: public_id, merchant_id: merchant_id) do
      nil -> {:error, :not_found}
      link -> {:ok, link}
    end
  end

  def get_link_by_slug(slug) do
    case Repo.get_by(PaymentLink, url_slug: slug) do
      nil -> {:error, :not_found}
      link -> {:ok, link}
    end
  end

  def create_link(merchant_id, attrs) do
    with {:ok, mode} <- resolve_mode(merchant_id, attrs) do
      attrs =
        attrs
        |> Map.put(:merchant_id, merchant_id)
        |> Map.put(:mode, mode)
        |> Map.put_new(:url_slug, generate_slug())
        |> Map.put_new(:use_count, 0)
        |> Map.put_new(:active, true)

      Multi.new()
      |> Multi.insert(:link, PaymentLink.changeset(%PaymentLink{}, attrs))
      |> Multi.insert(:outbox, fn %{link: link} ->
        Outbox.build_changeset(link, "payment_link.created", %{
          link_id: link.public_id,
          merchant_id: merchant_id,
          mode: link.mode,
          kind: link.kind,
          amount: link.amount,
          currency: link.currency,
          reusable: link.reusable,
          active: true
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{link: link}} -> {:ok, link}
        {:error, _step, reason, _} -> {:error, reason}
      end
    end
  end

  def deactivate_link(public_id, merchant_id) do
    with {:ok, link} <- get_link(public_id, merchant_id),
         false <- link.kind == "invoice" do
      Multi.new()
      |> Multi.update(:link, PaymentLink.deactivate_changeset(link))
      |> Multi.insert(:outbox, fn %{link: updated} ->
        Outbox.build_changeset(updated, "payment_link.deactivated", %{
          link_id: updated.public_id,
          merchant_id: merchant_id,
          mode: updated.mode
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{link: link}} -> {:ok, link}
        {:error, _step, reason, _} -> {:error, reason}
      end
    else
      true -> {:error, :invoice_link_immutable}
      {:error, _} = err -> err
    end
  end

  def update_checkout_layout(public_id, merchant_id, layout) do
    with {:ok, link} <- get_link(public_id, merchant_id) do
      link
      |> PaymentLink.changeset(%{checkout_layout: layout})
      |> Repo.update()
    end
  end

  def increment_use_count(%PaymentLink{} = link) do
    {1, [updated]} =
      Repo.update_all(
        from(pl in PaymentLink,
          where: pl.id == ^link.id,
          select: pl
        ),
        inc: [use_count: 1]
      )

    {:ok, updated}
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp resolve_mode(_merchant_id, %{mode: mode}) when is_binary(mode), do: {:ok, mode}

  defp resolve_mode(merchant_id, _attrs) do
    mode = if Merchants.live_mode_enabled?(merchant_id), do: "live", else: "simulation"
    {:ok, mode}
  end

  defp generate_slug do
    alphabet = String.graphemes(@url_slug_alphabet)
    len = length(alphabet)
    Enum.map_join(1..@url_slug_length, fn _ -> Enum.at(alphabet, :rand.uniform(len) - 1) end)
  end
end
