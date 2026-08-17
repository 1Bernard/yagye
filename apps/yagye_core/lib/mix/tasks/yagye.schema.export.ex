defmodule Mix.Tasks.Yagye.Schema.Export do
  @shortdoc "Export DBML schema files to a timestamped snapshot under docs/schema/exports/"

  @moduledoc """
  Copies DBML files for all three apps from docs/schema/ into a timestamped
  snapshot directory and writes a manifest.json keyed by app name.

  ## Usage

      mix yagye.schema.export

  ## Options

      --out PATH   Override the export root (default: docs/schema/exports)

  ## Output

      docs/schema/exports/<timestamp>/
        yagye-core.dbml
        yagye-portal.dbml
        gateway-simulator.dbml
        manifest.json
  """

  use Mix.Task
  use Boundary, classify_to: YagyeCore

  # Maps DBML filename (without extension) to the canonical app name.
  @apps [
    {"yagye-core", "yagye_core"},
    {"yagye-portal", "yagye_portal"},
    {"gateway-simulator", "gateway_simulator"}
  ]

  @default_out "docs/schema/exports"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [out: :string])
    root = repo_root()
    out_root = Path.join(root, Keyword.get(opts, :out, @default_out))
    schema_dir = Path.join(root, "docs/schema")

    timestamp = timestamp()
    export_dir = Path.join(out_root, timestamp)
    File.mkdir_p!(export_dir)

    app_entries =
      Enum.map(@apps, fn {slug, app_name} ->
        src = Path.join(schema_dir, "#{slug}.dbml")

        unless File.exists?(src) do
          Mix.raise("Expected schema file not found: #{src}")
        end

        content = File.read!(src)
        dest = Path.join(export_dir, "#{slug}.dbml")
        File.cp!(src, dest)

        table_count =
          content
          |> String.split("\n")
          |> Enum.count(&String.starts_with?(&1, "Table "))

        checksum = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

        Mix.shell().info("  #{app_name}: #{slug}.dbml (#{table_count} tables)")

        {app_name,
         %{
           file: "#{slug}.dbml",
           tables: table_count,
           sha256: checksum
         }}
      end)

    total_tables = app_entries |> Enum.map(fn {_, e} -> e.tables end) |> Enum.sum()

    manifest = %{
      exported_at: timestamp,
      schema_dir: Path.relative_to(schema_dir, root),
      total_tables: total_tables,
      apps: Map.new(app_entries)
    }

    manifest_path = Path.join(export_dir, "manifest.json")
    File.write!(manifest_path, Jason.encode!(manifest, pretty: true))

    Mix.shell().info("""

    Schema export complete.
      directory    : #{Path.relative_to(export_dir, root)}
      apps         : #{length(@apps)}
      total tables : #{total_tables}
      manifest     : #{Path.relative_to(manifest_path, root)}
    """)
  end

  defp repo_root do
    {root, 0} = System.cmd("git", ["rev-parse", "--show-toplevel"])
    String.trim(root)
  end

  defp timestamp do
    {{y, mo, d}, {h, mi, s}} = :calendar.universal_time()
    :io_lib.format("~4..0B~2..0B~2..0BT~2..0B~2..0B~2..0BZ", [y, mo, d, h, mi, s])
    |> IO.iodata_to_binary()
  end
end
