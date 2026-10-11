defmodule CourierCMS.LocalSecrets do
  @moduledoc "Persistent installation secrets generated for a Local release."

  @version 1

  def load_or_create! do
    CourierCMS.LocalPaths.prepare!()
    path = CourierCMS.LocalPaths.secrets_path()

    case File.read(path) do
      {:ok, encoded} ->
        decode!(encoded, path)

      {:error, :enoent} ->
        create!(path)

      {:error, reason} ->
        raise "cannot read Local installation secrets: #{:file.format_error(reason)}"
    end
  end

  defp create!(path) do
    payload = %{
      "version" => @version,
      "cookie_secret" => random_base64(64),
      "vault_key" => random_base64(32)
    }

    temporary_path = path <> ".#{System.unique_integer([:positive])}.tmp"
    File.write!(temporary_path, Jason.encode!(payload), [:exclusive])
    restrict_permissions(temporary_path)

    case File.rename(temporary_path, path) do
      :ok ->
        decode!(Jason.encode!(payload), path)

      {:error, :eexist} ->
        File.rm!(temporary_path)
        path |> File.read!() |> decode!(path)

      {:error, reason} ->
        File.rm!(temporary_path)
        raise "cannot persist Local installation secrets: #{:file.format_error(reason)}"
    end
  end

  defp decode!(encoded, path) do
    with {:ok,
          %{
            "version" => @version,
            "cookie_secret" => cookie_secret,
            "vault_key" => encoded_vault_key
          }} <- Jason.decode(encoded),
         {:ok, vault_key} <- Base.decode64(encoded_vault_key),
         true <- byte_size(vault_key) == 32,
         true <- is_binary(cookie_secret) and byte_size(cookie_secret) >= 64 do
      %{cookie_secret: cookie_secret, vault_key: vault_key}
    else
      _reason -> raise "Local installation secrets are invalid: #{path}"
    end
  end

  defp random_base64(bytes), do: bytes |> :crypto.strong_rand_bytes() |> Base.encode64()

  defp restrict_permissions(path) do
    if match?({:unix, _name}, :os.type()), do: File.chmod!(path, 0o600)
  end
end
