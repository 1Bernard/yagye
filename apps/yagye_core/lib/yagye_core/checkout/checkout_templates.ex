defmodule YagyeCore.CheckoutTemplates do
  @moduledoc false

  import Ecto.Query

  alias YagyeCore.Checkout.Schemas.{CheckoutTemplate, CheckoutTemplateComponent}
  alias YagyeCore.Repo

  @default_components [
    %{component_type: "order_summary", position: 1, visible: true, config: %{}},
    %{component_type: "customer_fields", position: 2, visible: true, config: %{}},
    %{component_type: "payment_methods", position: 3, visible: true, config: %{}},
    %{component_type: "terms_checkbox", position: 4, visible: false, config: %{}},
    %{component_type: "submit_button", position: 5, visible: true, config: %{}}
  ]

  @doc """
  Returns the merchant's draft template for a given mode.
  Creates one with default components if none exists.
  """
  def get_or_create_draft(merchant_id, mode \\ "live") do
    draft =
      Repo.one(
        from t in CheckoutTemplate,
          where:
            t.merchant_id == ^merchant_id and
              t.mode == ^mode and
              t.status == "draft",
          limit: 1
      )

    case draft do
      nil -> create_draft(merchant_id, mode, %{})
      template -> {:ok, Repo.preload(template, :components)}
    end
  end

  @doc "Returns the published template for a given mode, with components preloaded."
  def get_published(merchant_id, mode \\ "live") do
    case Repo.one(
           from t in CheckoutTemplate,
             where:
               t.merchant_id == ^merchant_id and
                 t.mode == ^mode and
                 t.status == "published",
             limit: 1
         ) do
      nil -> {:error, :not_found}
      template -> {:ok, Repo.preload(template, :components)}
    end
  end

  @doc """
  Creates or updates the draft template's theme, then publishes it.
  Accepts theme_attrs with optional keys: font_family, brand_color, methods.
  """
  def upsert_and_publish(merchant_id, mode \\ "live", theme_attrs \\ %{}) do
    with {:ok, draft} <- get_or_create_draft(merchant_id, mode),
         {:ok, _updated} <- update_theme(draft, theme_attrs) do
      publish_draft(merchant_id, mode)
    end
  end

  @doc "Archives current published, then publishes the draft."
  def publish_draft(merchant_id, mode \\ "live") do
    Repo.transaction(fn ->
      Repo.update_all(
        from(t in CheckoutTemplate,
          where:
            t.merchant_id == ^merchant_id and
              t.mode == ^mode and
              t.status == "published"
        ),
        set: [status: "archived"]
      )

      draft =
        Repo.one(
          from t in CheckoutTemplate,
            where:
              t.merchant_id == ^merchant_id and
                t.mode == ^mode and
                t.status == "draft",
            preload: :components,
            limit: 1
        )

      case draft do
        nil ->
          Repo.rollback(:no_draft)

        template ->
          template
          |> CheckoutTemplate.changeset(%{status: "published"})
          |> Repo.update!()
          |> Repo.preload(:components)
      end
    end)
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp create_draft(merchant_id, mode, extra_attrs) do
    name = "Default #{String.capitalize(mode)} template"
    theme = Map.get(extra_attrs, :theme, %{})

    changeset =
      CheckoutTemplate.changeset(%CheckoutTemplate{}, %{
        merchant_id: merchant_id,
        mode: mode,
        name: name,
        status: "draft",
        theme: theme
      })

    case Repo.insert(changeset) do
      {:ok, template} ->
        components =
          Enum.map(@default_components, fn attrs ->
            %CheckoutTemplateComponent{}
            |> CheckoutTemplateComponent.changeset(Map.put(attrs, :template_id, template.id))
            |> Repo.insert!()
          end)

        {:ok, %{template | components: components}}

      {:error, _} = error ->
        error
    end
  end

  defp update_theme(template, theme_attrs) when map_size(theme_attrs) == 0, do: {:ok, template}

  defp update_theme(template, theme_attrs) do
    merged = Map.merge(template.theme || %{}, stringify_keys(theme_attrs))

    template
    |> CheckoutTemplate.changeset(%{theme: merged})
    |> Repo.update()
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
