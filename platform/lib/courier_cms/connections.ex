defmodule CourierCMS.Connections do
  @moduledoc "The boundary for configured CMS adapter instances."

  import Ecto.Query

  alias CourierCMS.Accounts
  alias CourierCMS.Accounts.Scope
  alias CourierCMS.Adapters.Definition
  alias CourierCMS.ExtensionSDK.AdapterError
  alias CourierCMS.Extensions.Gateway
  alias CourierCMS.Connections.Connection
  alias CourierCMS.Repo
  alias CourierCMS.Workspaces

  def list_connections(%Scope{} = scope) do
    Connection
    |> where([connection], connection.workspace_id == ^scope.workspace.id)
    |> order_by([connection], asc: connection.name)
    |> Repo.all()
  end

  def get_connection!(%Scope{} = scope, id) do
    Repo.get_by!(Connection, id: id, workspace_id: scope.workspace.id)
  end

  def create_connection(%Scope{} = scope, attrs) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin]),
         {:ok, attrs} <- Definition.prepare_connection_attrs(attrs),
         {:ok, attrs} <- put_component_identity(attrs) do
      attrs = put_workspace(attrs, scope.workspace.id)

      %Connection{}
      |> Connection.changeset(attrs)
      |> put_prepared_credentials(attrs)
      |> Repo.insert()
    end
  end

  def update_connection(%Scope{} = scope, %Connection{} = connection, attrs) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin]),
         true <- connection.workspace_id == scope.workspace.id do
      connection
      |> Connection.changeset(preserve_component_identity(connection, attrs))
      |> Repo.update()
    else
      false -> {:error, :not_found}
      error -> error
    end
  end

  def update_concurrency_limit(%Scope{} = scope, %Connection{} = connection, value) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin]),
         true <- connection.workspace_id == scope.workspace.id,
         {:ok, limit} <- parse_concurrency_limit(value) do
      settings = Map.put(connection.settings || %{}, "max_concurrency", limit)

      case connection |> Ecto.Changeset.change(settings: settings) |> Repo.update() do
        {:ok, updated} ->
          Workspaces.audit(scope, "connection.concurrency_updated", "connection", updated.id)
          {:ok, updated}

        error ->
          error
      end
    else
      false -> {:error, :not_found}
      error -> error
    end
  end

  def update_request_rate_limit(%Scope{} = scope, %Connection{} = connection, value) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin]),
         true <- connection.workspace_id == scope.workspace.id,
         {:ok, limit} <- parse_request_rate_limit(value) do
      settings = Map.put(connection.settings || %{}, "requests_per_second", limit)

      case connection |> Ecto.Changeset.change(settings: settings) |> Repo.update() do
        {:ok, updated} ->
          Workspaces.audit(scope, "connection.rate_limit_updated", "connection", updated.id)
          {:ok, updated}

        error ->
          error
      end
    else
      false -> {:error, :not_found}
      error -> error
    end
  end

  def rotate_credentials(%Scope{} = scope, %Connection{} = connection, attrs) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin]),
         true <- connection.workspace_id == scope.workspace.id,
         {:ok, credentials} <- rotated_credentials(connection, attrs) do
      case connection
           |> Ecto.Changeset.change(credentials: credentials)
           |> Repo.update() do
        {:ok, updated} ->
          Workspaces.audit(scope, "connection.credentials_rotated", "connection", updated.id)
          {:ok, updated}

        error ->
          error
      end
    else
      false -> {:error, :not_found}
      error -> error
    end
  end

  def change_connection(%Scope{}, %Connection{} = connection, attrs \\ %{}) do
    case attrs do
      attrs when attrs == %{} ->
        Connection.changeset(connection, attrs)

      attrs ->
        change_connection_with_definition(connection, attrs)
    end
  end

  defp change_connection_with_definition(connection, attrs) do
    case Definition.prepare_connection_attrs(attrs) do
      {:ok, prepared} ->
        connection
        |> Connection.changeset(prepared)
        |> put_prepared_credentials(prepared)

      {:error, %AdapterError{} = error} ->
        connection
        |> Connection.changeset(attrs)
        |> Ecto.Changeset.add_error(:configuration, error.message)
    end
  end

  def test_connection(%Scope{} = scope, %Connection{} = connection) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin]),
         true <- connection.workspace_id == scope.workspace.id do
      do_test_connection(connection)
    else
      false -> {:error, :not_found}
      error -> error
    end
  end

  def configure_connector(%Scope{} = scope, %Connection{} = connection) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin]),
         true <- connection.workspace_id == scope.workspace.id,
         {:ok, _connector} <- Definition.connector(connection.adapter_key) do
      secret = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
      credentials = rotate_connector_secret(connection.credentials || %{}, secret)

      case connection |> Ecto.Changeset.change(credentials: credentials) |> Repo.update() do
        {:ok, updated} ->
          Workspaces.audit(scope, "connection.connector_secret_rotated", "connection", updated.id)
          {:ok, updated, secret}

        error ->
          error
      end
    else
      false -> {:error, :not_found}
      :error -> {:error, :unsupported_adapter}
      error -> error
    end
  end

  def connector_configured?(%Connection{} = connection) do
    match?({:ok, _connector}, Definition.connector(connection.adapter_key)) and
      is_map(connection.credentials) and is_binary(connection.credentials["connector_secret"])
  end

  def connector_definition(%Connection{} = connection),
    do: Definition.connector(connection.adapter_key)

  defp do_test_connection(connection) do
    result =
      case Gateway.test_connection(component_reference(connection), connection) do
        :error -> {:error, AdapterError.new(:unsupported, "Adapter is not registered")}
        result -> result
      end

    status = if result == :ok, do: "succeeded", else: "failed"

    capabilities =
      if result == :ok do
        Gateway.capabilities(component_reference(connection), connection)
      else
        connection.capabilities
      end

    connection
    |> Ecto.Changeset.change(
      last_test_status: status,
      last_tested_at: DateTime.utc_now(),
      capabilities: capabilities
    )
    |> Repo.update!()

    result
  end

  defp put_workspace(attrs, workspace_id) do
    if Enum.all?(Map.keys(attrs), &is_atom/1),
      do: Map.put(attrs, :workspace_id, workspace_id),
      else: Map.put(attrs, "workspace_id", workspace_id)
  end

  defp put_component_identity(attrs) do
    adapter_key = Map.get(attrs, "adapter_key", Map.get(attrs, :adapter_key))

    case Gateway.identity_attributes(adapter_key) do
      {:ok, identity} ->
        if Enum.all?(Map.keys(attrs), &is_atom/1),
          do: {:ok, Map.merge(attrs, identity)},
          else:
            {:ok,
             attrs
             |> Map.put("extension_id", identity.extension_id)
             |> Map.put("component_id", identity.component_id)}

      :error ->
        {:error, AdapterError.new(:unsupported, "Adapter is not registered")}
    end
  end

  defp preserve_component_identity(connection, attrs) do
    attrs
    |> Map.delete(:adapter_key)
    |> Map.delete("adapter_key")
    |> then(fn attrs ->
      if Enum.all?(Map.keys(attrs), &is_atom/1) do
        attrs
        |> Map.put(:adapter_key, connection.adapter_key)
        |> Map.put(:extension_id, connection.extension_id)
        |> Map.put(:component_id, connection.component_id)
      else
        attrs
        |> Map.put("adapter_key", connection.adapter_key)
        |> Map.put("extension_id", connection.extension_id)
        |> Map.put("component_id", connection.component_id)
      end
    end)
  end

  defp component_reference(connection) do
    %{extension_id: connection.extension_id, component_id: connection.component_id}
  end

  defp put_prepared_credentials(changeset, attrs) do
    credentials = Map.get(attrs, "credentials", Map.get(attrs, :credentials, %{}))

    if is_map(credentials) and map_size(credentials) > 0,
      do: Ecto.Changeset.put_change(changeset, :credentials, credentials),
      else: changeset
  end

  defp parse_concurrency_limit(value) when is_integer(value) and value in 1..100,
    do: {:ok, value}

  defp parse_concurrency_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} when limit in 1..100 -> {:ok, limit}
      _other -> {:error, :invalid_concurrency_limit}
    end
  end

  defp parse_concurrency_limit(_value), do: {:error, :invalid_concurrency_limit}

  defp parse_request_rate_limit(value) when is_integer(value) and value in 1..10_000,
    do: {:ok, value}

  defp parse_request_rate_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} when limit in 1..10_000 -> {:ok, limit}
      _other -> {:error, :invalid_request_rate_limit}
    end
  end

  defp parse_request_rate_limit(_value), do: {:error, :invalid_request_rate_limit}

  defp rotated_credentials(%Connection{} = connection, attrs) do
    with {:ok, submitted} <- Definition.cast_credentials(connection.adapter_key, attrs) do
      {:ok, Map.merge(connection.credentials || %{}, submitted)}
    else
      {:error, _reason} -> {:error, :invalid_credentials}
    end
  end

  defp rotate_connector_secret(credentials, secret) do
    credentials
    |> maybe_preserve_connector_secret()
    |> Map.put("connector_secret", secret)
  end

  defp maybe_preserve_connector_secret(%{"connector_secret" => current} = credentials)
       when is_binary(current) do
    credentials
    |> Map.put("connector_previous_secret", current)
    |> Map.put(
      "connector_previous_valid_until",
      DateTime.utc_now() |> DateTime.add(24, :hour) |> DateTime.to_iso8601()
    )
  end

  defp maybe_preserve_connector_secret(credentials), do: credentials
end
