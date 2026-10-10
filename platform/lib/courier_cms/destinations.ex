defmodule CourierCMS.Destinations do
  @moduledoc "Manages validated target receiving scopes and their lifecycle."

  import Ecto.Query

  alias CourierCMS.Accounts
  alias CourierCMS.Accounts.Scope
  alias CourierCMS.Adapters.Definition
  alias CourierCMS.Connections.Connection
  alias CourierCMS.Destinations.Destination
  alias CourierCMS.ExtensionSDK.AdapterError
  alias CourierCMS.Extensions.Gateway
  alias CourierCMS.Repo

  def list_destinations(%Scope{} = scope) do
    Destination
    |> where([destination], destination.workspace_id == ^scope.workspace.id)
    |> order_by([destination], asc: destination.name)
    |> preload([:target_connection, :owner_route])
    |> Repo.all()
  end

  def list_available(%Scope{} = scope, target_connection_id) do
    Destination
    |> where(
      [destination],
      destination.workspace_id == ^scope.workspace.id and
        destination.target_connection_id == ^target_connection_id and
        destination.lifecycle_status == :available and
        destination.validation_status == :valid
    )
    |> order_by([destination], asc: destination.name)
    |> Repo.all()
  end

  def get_destination!(%Scope{} = scope, id) do
    Destination
    |> Repo.get_by!(id: id, workspace_id: scope.workspace.id)
    |> Repo.preload([:target_connection, :owner_route])
  end

  def create_destination(%Scope{} = scope, attrs) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin]) do
      do_create_destination(scope.workspace.id, attrs)
    end
  end

  @doc false
  def create_seed_destination(workspace_id, attrs), do: do_create_destination(workspace_id, attrs)

  defp do_create_destination(workspace_id, attrs) do
    connection_id = value(attrs, :target_connection_id)
    supplied_scope = value(attrs, :scope) || %{}

    with {:ok, connection_id} <- cast_binary_id(connection_id),
         %Connection{} = connection <-
           Repo.get_by(Connection, id: connection_id, workspace_id: workspace_id),
         true <- Gateway.target_available?(component_reference(connection)),
         {:ok, scope_settings} <-
           Definition.cast_destination_settings(connection.adapter_key, supplied_scope),
         :ok <- validate_external_scope(connection, scope_settings) do
      now = DateTime.utc_now()

      attrs =
        attrs
        |> atomize_destination_attrs()
        |> Map.merge(%{
          workspace_id: workspace_id,
          scope: scope_settings,
          scope_key: scope_key(scope_settings),
          lifecycle_status: :available,
          validation_status: :valid,
          validated_at: now,
          last_validation_error: nil
        })

      %Destination{}
      |> Destination.changeset(attrs)
      |> Repo.insert()
    else
      nil -> {:error, :target_connection_not_found}
      {:error, :invalid_binary_id} -> {:error, :target_connection_not_found}
      false -> {:error, AdapterError.new(:unsupported, "Target Adapter is not registered")}
      error -> error
    end
  end

  def revalidate(%Scope{} = scope, %Destination{} = destination) do
    with :ok <- Accounts.authorize(scope, [:owner, :admin]),
         true <- destination.workspace_id == scope.workspace.id do
      destination = Repo.preload(destination, :target_connection)
      now = DateTime.utc_now()

      case validate_external_scope(destination.target_connection, destination.scope) do
        :ok ->
          destination
          |> Destination.changeset(%{
            validation_status: :valid,
            validated_at: now,
            last_validation_error: nil
          })
          |> Repo.update()

        {:error, %AdapterError{} = error} ->
          destination
          |> Destination.changeset(%{
            validation_status: :invalid,
            validated_at: now,
            last_validation_error: error.message
          })
          |> Repo.update()
      end
    else
      false -> {:error, :not_found}
      error -> error
    end
  end

  defp validate_external_scope(connection, settings) do
    reference = component_reference(connection)

    if Gateway.target_supports?(reference, :validate_destination) do
      Gateway.target(reference, :validate_destination, [connection, settings])
    else
      if settings == %{},
        do: :ok,
        else:
          {:error,
           AdapterError.new(:unsupported, "Target Adapter does not support Destination settings")}
    end
  end

  defp scope_key(settings) when map_size(settings) == 0, do: Ecto.UUID.generate()

  defp scope_key(settings) do
    settings
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp atomize_destination_attrs(attrs) do
    %{
      name: value(attrs, :name),
      target_connection_id: value(attrs, :target_connection_id)
    }
  end

  defp value(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))

  defp component_reference(connection) do
    %{extension_id: connection.extension_id, component_id: connection.component_id}
  end

  defp cast_binary_id(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :invalid_binary_id}
    end
  end
end
