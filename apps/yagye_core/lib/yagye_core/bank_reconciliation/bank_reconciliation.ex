defmodule YagyeCore.BankReconciliation do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias YagyeCore.BankReconciliation.Schemas.{BankStatement, BankStatementLine}
  alias YagyeCore.Repo

  # ── Statements ────────────────────────────────────────────────────────────────

  @doc """
  Ingests a bank statement with its lines atomically.
  `attrs` must include statement-level fields; `lines` is a list of line attrs maps.
  Returns {:error, :duplicate_statement} when the same checksum+account+date already exists.
  """
  def ingest_statement(attrs, lines) do
    Multi.new()
    |> Multi.insert(:statement, BankStatement.create_changeset(%BankStatement{}, attrs))
    |> Multi.run(:lines, fn _repo, %{statement: statement} ->
      insert_lines(statement, lines)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{statement: statement, lines: line_count}} ->
        {:ok, %{statement: statement, line_count: line_count}}

      {:error, :statement, %Ecto.Changeset{} = cs, _} ->
        if unique_constraint_violated?(cs, [:account_reference, :statement_date, :checksum]) do
          {:error, :duplicate_statement}
        else
          {:error, cs}
        end

      {:error, _step, reason, _} ->
        {:error, reason}
    end
  end

  def get_statement(id) do
    case Repo.get(BankStatement, id) do
      nil -> {:error, :not_found}
      stmt -> {:ok, stmt}
    end
  end

  def list_statements(account_reference, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(s in BankStatement,
      where: s.account_reference == ^account_reference,
      order_by: [desc: s.statement_date],
      limit: ^limit
    )
    |> Repo.all()
  end

  # ── Lines ─────────────────────────────────────────────────────────────────────

  def list_lines(%BankStatement{} = statement, opts \\ []) do
    match_state = Keyword.get(opts, :match_state)
    limit = Keyword.get(opts, :limit, 500)

    query =
      from(l in BankStatementLine,
        where: l.statement_id == ^statement.id,
        order_by: [asc: l.line_number],
        limit: ^limit
      )

    query =
      if match_state,
        do: where(query, [l], l.match_state == ^match_state),
        else: query

    Repo.all(query)
  end

  def match_line(%BankStatementLine{} = line, state) do
    line
    |> BankStatementLine.match_changeset(state)
    |> Repo.update()
  end

  @doc """
  Returns counts of lines grouped by match_state for a statement.
  """
  def line_match_summary(%BankStatement{id: statement_id}) do
    from(l in BankStatementLine,
      where: l.statement_id == ^statement_id,
      group_by: l.match_state,
      select: {l.match_state, count(l.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp insert_lines(%BankStatement{id: statement_id}, lines) do
    inserted =
      Enum.each(lines, fn line_attrs ->
        %BankStatementLine{}
        |> BankStatementLine.create_changeset(Map.put(line_attrs, :statement_id, statement_id))
        |> Repo.insert!()
      end)

    _ = inserted
    {:ok, length(lines)}
  end

  defp unique_constraint_violated?(%Ecto.Changeset{} = cs, fields) do
    Enum.any?(cs.errors, fn {field, {_msg, opts}} ->
      field in fields and Keyword.get(opts, :constraint) == :unique
    end)
  end
end
