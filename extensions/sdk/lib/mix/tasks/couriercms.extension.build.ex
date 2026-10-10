defmodule Mix.Tasks.Couriercms.Extension.Build do
  @shortdoc "Builds the current OTP application as a .couriercms Extension package"

  @moduledoc """
  Builds the current Extension project and writes a precompiled `.couriercms`
  archive. Run from the Extension project root:

      MIX_ENV=prod mix couriercms.extension.build
      MIX_ENV=prod mix couriercms.extension.build --output path/package.couriercms
  """

  use Mix.Task

  alias CourierCMS.ExtensionSDK.Manifest

  @switches [output: :string]

  @impl true
  def run(args) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: @switches)

    if positional != [] or invalid != [] do
      Mix.raise("usage: mix couriercms.extension.build [--output path]")
    end

    Mix.Task.run("compile")

    project = Mix.Project.config()
    app = Keyword.fetch!(project, :app)
    version = Keyword.fetch!(project, :version)
    manifest_path = Path.expand("couriercms-extension.json", File.cwd!())
    manifest_bytes = File.read!(manifest_path)

    manifest =
      with {:ok, decoded} <- Jason.decode(manifest_bytes),
           {:ok, parsed} <- Manifest.parse(decoded) do
        parsed
      else
        {:error, reason} -> Mix.raise("invalid Extension manifest: #{inspect(reason)}")
      end

    validate_identity!(manifest, app, version)

    app_directory = "lib/#{app}-#{version}/ebin"

    compiled_entries =
      Mix.Project.compile_path()
      |> Path.join("*")
      |> Path.wildcard()
      |> Enum.filter(&(Path.extname(&1) in [".beam", ".app"]))
      |> Enum.map(fn path ->
        {Path.join(app_directory, Path.basename(path)) |> normalize_path(), File.read!(path)}
      end)

    if compiled_entries == [] do
      Mix.raise("Extension compilation produced no BEAM application files")
    end

    entries = [{"couriercms-extension.json", manifest_bytes} | compiled_entries]
    checksums = checksum_manifest(entries)
    archive_entries = entries ++ [{"CHECKSUMS", checksums}]

    output =
      opts[:output] || Path.join("dist", "#{app}-#{version}.couriercms")

    output = Path.expand(output, File.cwd!())
    File.mkdir_p!(Path.dirname(output))
    File.rm(output)

    zip_entries =
      Enum.map(archive_entries, fn {name, bytes} ->
        {String.to_charlist(name), bytes}
      end)

    case :zip.create(String.to_charlist(output), zip_entries) do
      {:ok, _path} -> Mix.shell().info("Built #{output}")
      {:error, reason} -> Mix.raise("could not build Extension package: #{inspect(reason)}")
    end
  end

  defp validate_identity!(manifest, app, version) do
    if manifest.otp_application != Atom.to_string(app),
      do: Mix.raise("manifest otpApplication does not match Mix project app")

    if manifest.version != version,
      do: Mix.raise("manifest version does not match Mix project version")
  end

  defp checksum_manifest(entries) do
    entries
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map_join("\n", fn {name, bytes} ->
      digest = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
      "#{digest}  #{name}"
    end)
    |> Kernel.<>("\n")
  end

  defp normalize_path(path), do: String.replace(path, "\\", "/")
end
