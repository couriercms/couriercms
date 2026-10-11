defmodule CourierCMS.Local.LocalPathsTest do
  use ExUnit.Case

  if CourierCMS.ReleaseProfile.server?() do
    @moduletag skip: "Local filesystem behavior"
  end

  alias CourierCMS.{LocalPaths, LocalSecrets}

  test "Local uses one stable data root and retains generated encryption material" do
    previous = System.get_env("COURIERCMS_LOCAL_DATA_PATH")
    root = Path.expand("../../../.tmp/local-paths-#{System.unique_integer([:positive])}", __DIR__)
    System.put_env("COURIERCMS_LOCAL_DATA_PATH", root)

    on_exit(fn ->
      if previous,
        do: System.put_env("COURIERCMS_LOCAL_DATA_PATH", previous),
        else: System.delete_env("COURIERCMS_LOCAL_DATA_PATH")

      File.rm_rf!(root)
    end)

    first = LocalSecrets.load_or_create!()
    second = LocalSecrets.load_or_create!()

    assert first == second
    assert byte_size(first.vault_key) == 32
    assert byte_size(first.cookie_secret) >= 64
    assert LocalPaths.database_path() == Path.join(root, "couriercms.db")
    assert File.exists?(LocalPaths.secrets_path())

    for directory <- [
          LocalPaths.extensions_dir(),
          LocalPaths.extension_cache_dir(),
          LocalPaths.logs_dir(),
          LocalPaths.temporary_dir(),
          LocalPaths.backups_dir()
        ] do
      assert File.dir?(directory)
    end
  end

  test "Local has no configurable public bind address" do
    assert CourierCMS.ReleaseProfile.http_ip() == {127, 0, 0, 1}
  end
end
