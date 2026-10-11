defmodule CourierCMS.Transport.ContentBundleValidatorTest do
  use ExUnit.Case, async: true

  alias CourierCMS.ExtensionSDK.{
    AdapterError,
    AssetDescriptor,
    ContentBundle,
    ContentNode,
    SourceIdentity
  }

  alias CourierCMS.Transport.ContentBundleValidator

  test "accepts a valid bundle within platform limits" do
    assert :ok = ContentBundleValidator.validate(bundle())
  end

  test "returns a normalized safe error when an Adapter exceeds a limit" do
    limit = Application.fetch_env!(:couriercms, :max_content_bundle_assets)

    oversized = %{
      bundle()
      | assets:
          Enum.map(0..limit, fn index ->
            %AssetDescriptor{source_key: "asset-#{index}"}
          end)
    }

    assert {:error, %AdapterError{category: :invalid_content, retryable: false} = error} =
             ContentBundleValidator.validate(oversized)

    assert error.message =~ "assets count"
    refute error.message =~ "source_url"
  end

  test "rejects values outside the ContentBundle contract" do
    assert {:error, %AdapterError{category: :invalid_content}} =
             ContentBundleValidator.validate(%{"root" => %{}})
  end

  defp bundle do
    identity = %SourceIdentity{
      item_key: "101",
      locale_key: "en",
      revision_key: "1",
      state: :published
    }

    %ContentBundle{
      root: %ContentNode{identity: identity, source_type: "post", fields: %{"title" => "A"}}
    }
  end
end
