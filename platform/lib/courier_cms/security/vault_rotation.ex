defmodule CourierCMS.Security.VaultRotation do
  @moduledoc "Re-encrypts stored Connection credentials with the current default vault key."

  import Ecto.Query

  alias CourierCMS.Connections.Connection
  alias CourierCMS.Repo

  def rotate! do
    Repo.transaction(fn ->
      Connection
      |> where([connection], not is_nil(connection.credentials))
      |> Repo.stream(max_rows: 100)
      |> Enum.reduce(0, fn connection, count ->
        connection
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.force_change(:credentials, connection.credentials)
        |> Repo.update!()

        count + 1
      end)
    end)
    |> case do
      {:ok, count} -> count
      {:error, reason} -> raise "vault rotation failed: #{inspect(reason)}"
    end
  end
end
