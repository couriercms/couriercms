defmodule CourierCMS.Assets.TransferTest do
  use ExUnit.Case, async: false

  alias CourierCMS.Assets.Transfer
  alias CourierCMS.ExtensionSDK.{AdapterError, AssetContent, AssetDescriptor}

  setup do
    previous_dir = Application.get_env(:couriercms, :asset_temp_dir)
    previous_limit = Application.fetch_env!(:couriercms, :max_asset_bytes)

    directory =
      Path.join(System.tmp_dir!(), "couriercms-transfer-#{System.unique_integer([:positive])}")

    Application.put_env(:couriercms, :asset_temp_dir, directory)
    Application.put_env(:couriercms, :max_asset_bytes, 32)

    on_exit(fn ->
      Application.put_env(:couriercms, :asset_temp_dir, previous_dir)
      Application.put_env(:couriercms, :max_asset_bytes, previous_limit)
      File.rm_rf!(directory)
    end)

    :ok
  end

  test "materializes a verified replayable stream and removes the temporary file" do
    checksum = "sha256:" <> Base.encode16(:crypto.hash(:sha256, "abcdef"), case: :lower)
    descriptor = %AssetDescriptor{source_key: "asset-1", size: 6, checksum: checksum}
    content = %AssetContent{chunks: ["abc", "def"], byte_size: 6, checksum: checksum}

    assert :accepted =
             Transfer.with_materialized(content, descriptor, fn materialized ->
               assert IO.iodata_to_binary(Enum.to_list(materialized.chunks)) == "abcdef"
               assert materialized.byte_size == 6
               assert materialized.checksum == checksum
               :accepted
             end)

    assert File.ls!(Application.fetch_env!(:couriercms, :asset_temp_dir)) == []
  end

  test "rejects streams that exceed the configured limit" do
    Application.put_env(:couriercms, :max_asset_bytes, 3)
    descriptor = %AssetDescriptor{source_key: "asset-1"}
    content = %AssetContent{chunks: ["abcd"]}

    assert {:error, %AdapterError{category: :invalid_content}} =
             Transfer.with_materialized(content, descriptor, fn _content -> :unexpected end)
  end

  test "rejects a declared size mismatch" do
    descriptor = %AssetDescriptor{source_key: "asset-1", size: 4, checksum: "sha256:bad"}
    content = %AssetContent{chunks: ["abc"], byte_size: 3}

    assert {:error, %AdapterError{message: message}} =
             Transfer.with_materialized(content, descriptor, fn _content -> :unexpected end)

    assert message =~ "size"
  end

  test "rejects a declared checksum mismatch" do
    descriptor = %AssetDescriptor{source_key: "asset-1", checksum: "sha256:bad"}
    content = %AssetContent{chunks: ["abc"], byte_size: 3}

    assert {:error, %AdapterError{message: message}} =
             Transfer.with_materialized(content, descriptor, fn _content -> :unexpected end)

    assert message =~ "checksum"
  end
end
