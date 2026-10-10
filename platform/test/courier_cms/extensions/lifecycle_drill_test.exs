defmodule CourierCMS.Extensions.LifecycleDrillTest do
  use ExUnit.Case, async: false

  @moduletag :extension_lifecycle

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "couriercms-extension-drill-#{System.unique_integer([:positive])}"
      )

    active = Path.join(root, "active")
    staging = Path.join(root, "staging")
    cache = Path.join(root, "cache")
    File.mkdir_p!(active)
    File.mkdir_p!(staging)
    on_exit(fn -> File.rm_rf(root) end)

    %{root: root, active: active, staging: staging, cache: cache}
  end

  test "a clean node loads an upgrade and then restores the exact prior package", context do
    suffix = System.unique_integer([:positive])
    extension_id = "org.example.lifecycle_#{suffix}"
    component_id = "lifecycle_#{suffix}"
    application = "couriercms_lifecycle_#{suffix}"
    module_name = "CourierCMSLifecycle.Adapter#{suffix}"

    v1 =
      build_package!(
        context,
        "v1.couriercms",
        extension_id,
        component_id,
        application,
        module_name,
        "1.0.0"
      )

    v2 =
      build_package!(
        context,
        "v2.couriercms",
        extension_id,
        component_id,
        application,
        module_name,
        "1.1.0"
      )

    active_package = Path.join(context.active, "extension.couriercms")

    File.cp!(v1, active_package)
    installed = start_clean_node!(context)
    assert installed["status"] == "loaded"
    assert installed["version"] == "1.0.0"
    assert installed["artifact_version"] == "1.0.0"

    File.cp!(v2, active_package)
    upgraded = start_clean_node!(context)
    assert upgraded["status"] == "loaded"
    assert upgraded["version"] == "1.1.0"
    assert upgraded["artifact_version"] == "1.1.0"
    refute upgraded["checksum"] == installed["checksum"]

    File.cp!(v1, active_package)
    rolled_back = start_clean_node!(context)
    assert rolled_back["status"] == "loaded"
    assert rolled_back["version"] == "1.0.0"
    assert rolled_back["checksum"] == installed["checksum"]
    assert rolled_back["artifact_checksum"] == installed["artifact_checksum"]
  end

  defp start_clean_node!(context) do
    script = """
    Application.load(:couriercms_extension_sdk)
    Application.load(:couriercms)
    {:ok, _} = Application.ensure_all_started(:crypto)
    {:ok, _} = Application.ensure_all_started(:jason)
    {:ok, _} = Application.ensure_all_started(:couriercms_extension_sdk)

    Application.put_env(:couriercms, :extensions_dir, #{inspect(context.active)})
    Application.put_env(:couriercms, :extension_cache_dir, #{inspect(context.cache)})
    Application.put_env(:couriercms, :extension_signature_policy, :optional)
    Application.put_env(:couriercms, :extension_trusted_keys, %{})
    Application.put_env(:couriercms, :extension_max_package_bytes, 1_000_000)
    Application.put_env(:couriercms, :extension_max_uncompressed_bytes, 2_000_000)
    Application.put_env(:couriercms, :extension_max_entries, 100)
    Application.put_env(:couriercms, :extension_max_packages, 10)

    name = CourierCMSLifecycleDrillLoader
    {:ok, _pid} = CourierCMS.Extensions.PackageLoader.start_link(
      name: name,
      extensions_dir: #{inspect(context.active)},
      cache_dir: #{inspect(context.cache)},
      signature_policy: :optional,
      trusted_keys: %{},
      max_package_bytes: 1_000_000,
      max_uncompressed_bytes: 2_000_000,
      max_entries: 100,
      max_packages: 10
    )

    [diagnostic] = CourierCMS.Extensions.PackageLoader.diagnostics(name)
    [entry] = CourierCMS.Extensions.PackageLoader.component_entries(name)

    result = %{
      status: diagnostic.status,
      version: diagnostic.version,
      checksum: diagnostic.checksum,
      artifact_version: entry.artifact["version"],
      artifact_checksum: entry.artifact["checksum"]
    }

    IO.puts("COURIERCMS_DRILL_RESULT=" <> Jason.encode!(result))
    """

    executable = System.find_executable("elixir") || flunk("elixir executable is unavailable")
    build_lib = Path.expand("_build/test/lib")
    runner_path = Path.join(context.root, "start-node.exs")
    File.write!(runner_path, script)

    {output, status} =
      System.cmd(executable, [runner_path],
        env: [
          {"ERL_LIBS", build_lib},
          {"TEMP", context.root},
          {"TMP", context.root}
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output

    json =
      output
      |> String.split(["\r\n", "\n"], trim: true)
      |> Enum.find_value(fn
        "COURIERCMS_DRILL_RESULT=" <> json -> json
        _line -> nil
      end)

    assert is_binary(json), output
    Jason.decode!(json)
  end

  defp build_package!(
         context,
         filename,
         extension_id,
         component_id,
         application,
         module_name,
         version
       ) do
    beam =
      compile_fixture_beam!(
        context,
        module_name,
        extension_id,
        component_id,
        version
      )

    root = "lib/#{application}-#{version}/ebin"

    manifest = %{
      "manifestVersion" => 1,
      "extensionId" => extension_id,
      "name" => "Lifecycle fixture",
      "version" => version,
      "otpApplication" => application,
      "sdkRequirement" => ">= 0.1.0 and < 1.0.0",
      "couriercmsRequirement" => ">= 0.1.0 and < 1.0.0",
      "elixirRequirement" => ">= 1.17.0 and < 2.0.0",
      "otpRequirement" => ">= 27.0.0 and < 40.0.0",
      "components" => [
        %{
          "id" => component_id,
          "kind" => "adapter",
          "module" => module_name,
          "capabilities" => ["source"]
        }
      ]
    }

    files = %{
      "couriercms-extension.json" => Jason.encode!(manifest),
      "#{root}/#{application}.app" =>
        "{application,#{application},[{vsn,\"#{version}\"},{applications,[kernel,stdlib,elixir,couriercms_extension_sdk]}]}.",
      "#{root}/Elixir.#{module_name}.beam" => beam
    }

    files = Map.put(files, "CHECKSUMS", checksums(files))
    package_path = Path.join(context.staging, filename)
    entries = Enum.map(files, fn {name, contents} -> {String.to_charlist(name), contents} end)
    assert {:ok, _path} = :zip.create(String.to_charlist(package_path), entries)
    package_path
  end

  defp compile_fixture_beam!(context, module_name, extension_id, component_id, version) do
    source_path = Path.join(context.root, "fixture_#{version}.ex")
    output_path = Path.join(context.root, "compiled-#{version}")
    File.mkdir_p!(output_path)

    source = """
    defmodule #{module_name} do
      @behaviour CourierCMS.ExtensionSDK.SourceAdapter
      alias CourierCMS.ExtensionSDK.Component

      def component do
        Component.new!(
          extension_id: #{inspect(extension_id)},
          component_id: #{inspect(component_id)},
          kind: :adapter,
          version: #{inspect(version)},
          capabilities: [:source]
        )
      end

      def definition do
        %{
          key: #{inspect(component_id)},
          label: "Lifecycle fixture #{version}",
          connection: %{endpoint: %{mode: :input}, fields: []},
          source: %{
            content_label: "items",
            selection_fields: [],
            default_mapping: %{"title" => "fields.title"}
          }
        }
      end

      def capabilities(_connection), do: %{"source" => true}
      def test_connection(_connection), do: :ok
      def enumerate(_connection, _selection, _cursor), do: {:ok, %{items: [], cursor: nil}}
      def read_root(_connection, _identity, _rules), do: {:error, :not_implemented}
    end
    """

    File.write!(source_path, source)

    assert {:ok, [module], %{compile_warnings: [], runtime_warnings: []}} =
             Kernel.ParallelCompiler.compile_to_path([source_path], output_path,
               return_diagnostics: true
             )

    beam_path = Path.join(output_path, "Elixir.#{module_name}.beam")
    Code.delete_path(output_path)
    :code.purge(module)
    :code.delete(module)
    File.read!(beam_path)
  end

  defp checksums(files) do
    files
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map_join("\n", fn {path, contents} ->
      digest = :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower)
      "#{digest}  #{path}"
    end)
    |> Kernel.<>("\n")
  end
end
