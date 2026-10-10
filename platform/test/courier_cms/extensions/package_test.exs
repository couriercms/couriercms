defmodule CourierCMS.Extensions.PackageTest do
  use ExUnit.Case, async: false

  alias CourierCMS.Extensions.{Package, PackageLoader}

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "couriercms-extension-test-#{System.unique_integer([:positive])}"
      )

    packages = Path.join(root, "packages")
    cache = Path.join(root, "cache")
    File.mkdir_p!(packages)
    on_exit(fn -> File.rm_rf(root) end)
    %{packages: packages, cache: cache}
  end

  test "validates a checksummed package without loading its code", context do
    path = package_path(context.packages, "valid.couriercms")
    create_package!(path, package_files())

    assert {:ok, candidate} = Package.inspect(path, options(context))
    assert candidate.manifest.extension_id == "org.example.fixture"
    assert candidate.manifest.version == "1.0.0"
    assert byte_size(candidate.checksum) == 64
  end

  test "rejects a package when checked content was modified", context do
    path = package_path(context.packages, "modified.couriercms")

    files =
      package_files()
      |> Map.put(
        "lib/couriercms_fixture-1.0.0/ebin/CourierCMSFixture.Adapter.beam",
        "modified after checksums"
      )

    create_package!(path, files)

    assert {:error, "package checksum verification failed"} =
             Package.inspect(path, options(context))
  end

  test "rejects unsafe archive paths before extraction", context do
    path = package_path(context.packages, "unsafe.couriercms")
    create_package!(path, %{"../outside" => "unsafe"})

    assert {:error, message} = Package.inspect(path, options(context))
    assert message =~ "path traversal"
    refute File.exists?(Path.join(context.packages, "outside"))
  end

  test "an application-name collision never stops the existing OTP application", context do
    base = package_files()
    manifest = base |> Map.fetch!("couriercms-extension.json") |> Jason.decode!()

    manifest =
      manifest
      |> Map.put("extensionId", "org.example.logger_collision")
      |> Map.put("otpApplication", "logger")

    files = %{
      "couriercms-extension.json" => Jason.encode!(manifest),
      "lib/logger-1.0.0/ebin/logger.app" =>
        "{application,logger,[{vsn,\"1.0.0\"},{applications,[kernel,stdlib]}]}.",
      "lib/logger-1.0.0/ebin/Collision.beam" => "not a beam"
    }

    files = Map.put(files, "CHECKSUMS", checksums(files))
    path = package_path(context.packages, "logger-collision.couriercms")
    create_package!(path, files)

    assert {:ok, candidate} = Package.inspect(path, options(context))
    assert {:error, message} = Package.activate(candidate, options(context))
    assert message =~ "already loaded"

    assert Enum.any?(Application.started_applications(), fn {app, _description, _version} ->
             app == :logger
           end)
  end

  test "enforces signature policy and verifies trusted Ed25519 signatures", context do
    unsigned_path = package_path(context.packages, "unsigned.couriercms")
    unsigned = package_files()
    create_package!(unsigned_path, unsigned)

    required = %{options(context) | signature_policy: :required}
    assert {:error, "package signature is required"} = Package.inspect(unsigned_path, required)

    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)
    checksums = Map.fetch!(unsigned, "CHECKSUMS")
    signature = :crypto.sign(:eddsa, :none, checksums, [private_key, :ed25519])

    signed =
      Map.put(
        unsigned,
        "SIGNATURE",
        Jason.encode!(%{
          "algorithm" => "ed25519",
          "keyId" => "test-key",
          "signature" => Base.encode64(signature)
        })
      )

    signed_path = package_path(context.packages, "signed.couriercms")
    create_package!(signed_path, signed)

    assert {:ok, _candidate} =
             Package.inspect(signed_path, %{required | trusted_keys: %{"test-key" => public_key}})
  end

  test "a bad package becomes a diagnostic and does not stop the loader", context do
    path = package_path(context.packages, "bad-code.couriercms")
    create_package!(path, package_files())
    name = Module.concat(__MODULE__, "Loader#{System.unique_integer([:positive])}")

    assert {:ok, pid} =
             start_supervised(
               {PackageLoader,
                [
                  name: name,
                  extensions_dir: context.packages,
                  cache_dir: context.cache,
                  signature_policy: :optional,
                  trusted_keys: %{}
                ]}
             )

    assert Process.alive?(pid)
    assert [] == PackageLoader.component_entries(name)

    assert [%{status: :rejected, extension_id: "org.example.fixture"}] =
             PackageLoader.diagnostics(name)
  end

  test "loads a precompiled OTP application and registers its component", context do
    suffix = System.unique_integer([:positive])
    application = "couriercms_fixture_#{suffix}"
    extension_id = "org.example.fixture_#{suffix}"
    component_id = "fixture_#{suffix}"
    module_name = "CourierCMSFixture.Adapter#{suffix}"
    beam = compile_fixture_beam!(context.cache, module_name, extension_id, component_id)
    root = "lib/#{application}-1.0.0/ebin"

    manifest = %{
      "manifestVersion" => 1,
      "extensionId" => extension_id,
      "name" => "Compiled fixture",
      "version" => "1.0.0",
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
        "{application,#{application},[{vsn,\"1.0.0\"},{applications,[kernel,stdlib,elixir,couriercms_extension_sdk]}]}.",
      "#{root}/Elixir.#{module_name}.beam" => beam
    }

    files = Map.put(files, "CHECKSUMS", checksums(files))
    path = package_path(context.packages, "compiled.couriercms")
    create_package!(path, files)

    assert {:ok, candidate} = Package.inspect(path, options(context))
    assert {:ok, loaded} = Package.activate(candidate, options(context))

    assert [%{adapter_key: ^component_id, source_module: source_module}] =
             loaded.component_entries

    assert source_module.definition().key == component_id

    on_exit(fn ->
      Application.stop(loaded.otp_application)
      Application.unload(loaded.otp_application)
      Code.delete_path(loaded.code_path)
      :code.purge(source_module)
      :code.delete(source_module)
    end)
  end

  defp package_files do
    root = "lib/couriercms_fixture-1.0.0/ebin"

    files = %{
      "couriercms-extension.json" =>
        Jason.encode!(%{
          "manifestVersion" => 1,
          "extensionId" => "org.example.fixture",
          "name" => "Fixture",
          "version" => "1.0.0",
          "otpApplication" => "couriercms_fixture",
          "sdkRequirement" => ">= 0.1.0 and < 1.0.0",
          "couriercmsRequirement" => ">= 0.1.0 and < 1.0.0",
          "elixirRequirement" => ">= 1.17.0 and < 2.0.0",
          "otpRequirement" => ">= 27.0.0 and < 40.0.0",
          "components" => [
            %{
              "id" => "fixture",
              "kind" => "adapter",
              "module" => "CourierCMSFixture.Adapter",
              "capabilities" => ["source"]
            }
          ]
        }),
      "#{root}/couriercms_fixture.app" =>
        "{application,couriercms_fixture,[{vsn,\"1.0.0\"},{applications,[kernel,stdlib]}]}.",
      "#{root}/CourierCMSFixture.Adapter.beam" => "not a beam"
    }

    Map.put(files, "CHECKSUMS", checksums(files))
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

  defp create_package!(path, files) do
    entries = Enum.map(files, fn {name, contents} -> {String.to_charlist(name), contents} end)
    assert {:ok, _path} = :zip.create(String.to_charlist(path), entries)
    path
  end

  defp compile_fixture_beam!(directory, module_name, extension_id, component_id) do
    source_path = Path.join(directory, "fixture_#{System.unique_integer([:positive])}.ex")
    output_path = Path.join(directory, "compiled")
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
          version: "1.0.0",
          capabilities: [:source]
        )
      end

      def definition do
        %{
          key: #{inspect(component_id)},
          label: "Compiled fixture",
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
    assert :non_existing == :code.which(module)
    File.read!(beam_path)
  end

  defp package_path(directory, name), do: Path.join(directory, name)

  defp options(context) do
    %{
      cache_dir: context.cache,
      signature_policy: :optional,
      trusted_keys: %{},
      max_package_bytes: 1_000_000,
      max_uncompressed_bytes: 2_000_000,
      max_entries: 100
    }
  end
end
