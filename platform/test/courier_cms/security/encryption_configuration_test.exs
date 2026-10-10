defmodule CourierCMS.Security.EncryptionConfigurationTest do
  use ExUnit.Case, async: true

  @affected_modules ["Cloak.Ciphers.AES.CTR", "Cloak.Ecto.PBKDF2", "Cloak.Fields.PBKDF2"]

  test "the vault uses authenticated AES-GCM ciphers only" do
    ciphers =
      :couriercms
      |> Application.fetch_env!(CourierCMS.Vault)
      |> Keyword.fetch!(:ciphers)

    assert ciphers != []

    assert Enum.all?(ciphers, fn
             {_label, {Cloak.Ciphers.AES.GCM, _options}} -> true
             _other -> false
           end)
  end

  test "runtime code and configuration do not reference acknowledged affected paths" do
    project_root = Path.expand("../../..", __DIR__)

    source =
      ["lib", "config"]
      |> Enum.flat_map(fn directory ->
        project_root
        |> Path.join(directory)
        |> Path.join("**/*.{ex,exs}")
        |> Path.wildcard()
      end)
      |> Enum.map_join("\n", &File.read!/1)

    refute Enum.any?(@affected_modules, &String.contains?(source, &1))
  end
end
