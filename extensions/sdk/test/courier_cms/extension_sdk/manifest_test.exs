defmodule CourierCMS.ExtensionSDK.ManifestTest do
  use ExUnit.Case, async: true

  alias CourierCMS.ExtensionSDK.Manifest

  test "parses a valid manifest without loading its declared module" do
    assert {:ok, manifest} = Manifest.parse(valid_manifest())
    assert manifest.extension_id == "com.couriercms.wordpress"
    assert manifest.otp_application == "couriercms_wordpress"
    assert [%{id: "wordpress", kind: :adapter}] = manifest.components
  end

  test "rejects duplicate component IDs" do
    manifest = valid_manifest()
    component = hd(manifest["components"])

    assert {:error, errors} = Manifest.parse(%{manifest | "components" => [component, component]})
    assert "component IDs must be unique" in errors
  end

  test "rejects invalid compatibility requirements and module names" do
    manifest = valid_manifest()
    component = %{hd(manifest["components"]) | "module" => "wordpress_adapter"}

    manifest =
      manifest
      |> Map.put("sdkRequirement", "whatever is newest")
      |> Map.put("components", [component])

    assert {:error, errors} = Manifest.parse(manifest)
    assert "sdkRequirement must be a valid version requirement" in errors
    assert "component module must be a fully qualified Elixir module" in errors
  end

  test "bounds strings before the loader converts names to atoms" do
    manifest = Map.put(valid_manifest(), "otpApplication", "a" <> String.duplicate("b", 64))

    assert {:error, errors} = Manifest.parse(manifest)
    assert "otpApplication must be a non-empty string" in errors
  end

  defp valid_manifest do
    %{
      "manifestVersion" => 1,
      "extensionId" => "com.couriercms.wordpress",
      "name" => "WordPress",
      "version" => "1.0.0",
      "otpApplication" => "couriercms_wordpress",
      "sdkRequirement" => ">= 0.1.0 and < 1.0.0",
      "couriercmsRequirement" => ">= 0.2.0 and < 1.0.0",
      "elixirRequirement" => "~> 1.20",
      "otpRequirement" => ">= 29.0.0 and < 30.0.0",
      "components" => [
        %{
          "id" => "wordpress",
          "kind" => "adapter",
          "module" => "CourierCMSExtension.WordPress.Adapter",
          "capabilities" => ["source", "incremental_changes"]
        }
      ]
    }
  end
end
