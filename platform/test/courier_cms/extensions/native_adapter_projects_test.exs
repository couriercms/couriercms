defmodule CourierCMS.Extensions.NativeAdapterProjectsTest do
  use ExUnit.Case, async: true

  alias CourierCMS.ExtensionSDK.Manifest

  @projects ~w(content fake wordpress sanity)

  test "extension projects depend only on the public SDK boundary" do
    for project <- @projects,
        path <-
          Path.wildcard(Path.expand("../../../../extensions/#{project}/lib/**/*.ex", __DIR__)) do
      source = File.read!(path)

      refute Regex.match?(~r/CourierCMS\.(?!ExtensionSDK)/, source),
             "#{path} imports a platform-internal CourierCMS module"

      refute Regex.match?(~r/Application\.(?:get|fetch)_env!?\s*\(\s*:couriercms/, source),
             "#{path} reads platform-internal application configuration"
    end
  end

  test "extension manifests satisfy the public SDK contract" do
    for project <- @projects do
      path =
        Path.expand(
          "../../../../extensions/#{project}/couriercms-extension.json",
          __DIR__
        )

      manifest = path |> File.read!() |> Jason.decode!()
      assert {:ok, parsed} = Manifest.parse(manifest), path
      assert parsed.extension_id =~ ~r/^com\.couriercms\./
      assert parsed.components != []
    end
  end

  test "platform source does not reference concrete extension modules" do
    for path <- Path.wildcard(Path.expand("../../../lib/**/*.{ex,exs,heex}", __DIR__)) do
      refute File.read!(path) =~ "CourierCMSExtension.",
             "#{path} directly references a concrete extension module"
    end
  end

  test "platform production code does not encode official CMS implementations" do
    implementation_names =
      Path.expand("../../../../extensions/*/couriercms-extension.json", __DIR__)
      |> Path.wildcard()
      |> Enum.map(fn path ->
        manifest = path |> File.read!() |> Jason.decode!()

        if Enum.any?(manifest["components"], &(&1["kind"] == "adapter")) do
          manifest
          |> Map.fetch!("extensionId")
          |> String.split(".")
          |> List.last()
        end
      end)
      |> Enum.reject(&is_nil/1)

    patterns =
      implementation_names
      |> Enum.map_join("|", &Regex.escape/1)
      |> then(&Regex.compile!("\\b(?:#{&1})\\b", "i"))

    roots = [
      Path.expand("../../../lib/**/*.{ex,exs,heex}", __DIR__),
      Path.expand("../../../config/*.{ex,exs}", __DIR__),
      Path.expand("../../../priv/repo/migrations/*.exs", __DIR__)
    ]

    for root <- roots, path <- Path.wildcard(root) do
      refute Regex.match?(patterns, File.read!(path)),
             "#{path} embeds a concrete CMS implementation in the platform"
    end
  end
end
