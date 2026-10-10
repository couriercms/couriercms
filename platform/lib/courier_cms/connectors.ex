defmodule CourierCMS.Connectors do
  @moduledoc "Authenticated ingress and durable processing for installed CMS Connectors."

  import Ecto.Query

  alias CourierCMS.Adapters.Definition
  alias CourierCMS.Connectors.{ConnectorEvent, ConnectorEventWorker}
  alias CourierCMS.Accounts.Scope
  alias CourierCMS.Connections.Connection
  alias CourierCMS.Execution
  alias CourierCMS.Execution.JobArgs
  alias CourierCMS.Repo

  @allowed_kinds ["content.published", "content.updated"]
  @supported_contract_versions [1]
  @signature_window_seconds 300

  def list_events(%Scope{} = scope, limit \\ 100) do
    ConnectorEvent
    |> join(:inner, [event], connection in assoc(event, :connection))
    |> where([_event, connection], connection.workspace_id == ^scope.workspace.id)
    |> order_by([event], desc: event.received_at)
    |> limit(^limit)
    |> preload(:connection)
    |> Repo.all()
  end

  def accept_event(connection_id, timestamp, signature, raw_body, params, opts \\ []) do
    job_builder = Keyword.get(opts, :job_builder, &connector_job/1)

    with %Connection{enabled: true} = connection <- Repo.get(Connection, connection_id),
         {:ok, _connector} <- connector_definition(connection),
         {:ok, secrets} <- connector_secrets(connection),
         :ok <- verify_timestamp(timestamp),
         :ok <- verify_signature(secrets, timestamp, signature, raw_body),
         {:ok, attrs} <- normalize_event(params),
         {:ok, event, duplicate?} <- persist_event_and_job(connection, attrs, job_builder) do
      :telemetry.execute(
        [:couriercms, :connector, :event, :accepted],
        %{count: 1},
        %{adapter: connection.adapter_key, duplicate: duplicate?}
      )

      {:ok, event, duplicate?}
    else
      nil -> {:error, :not_found}
      %Connection{} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def process_event(event_id) do
    event = ConnectorEvent |> Repo.get!(event_id) |> Repo.preload(:connection)

    if event.status in [:processed, :ignored] do
      :ok
    else
      do_process_event(event)
    end
  end

  defp do_process_event(event) do
    event
    |> ConnectorEvent.changeset(%{status: :processing, error_summary: nil})
    |> Repo.update!()

    case Execution.start_connector_runs(event) do
      {:ok, runs} ->
        status = if runs == [], do: :ignored, else: :processed

        event
        |> ConnectorEvent.changeset(%{
          status: status,
          runs_started: length(runs),
          processed_at: DateTime.utc_now()
        })
        |> Repo.update!()

        :telemetry.execute(
          [:couriercms, :connector, :event, :processed],
          %{count: 1, runs_started: length(runs)},
          %{adapter: event.connection.adapter_key, status: status}
        )

        :ok

      {:error, reason} ->
        event
        |> ConnectorEvent.changeset(%{
          status: :failed,
          error_summary: safe_reason(reason),
          processed_at: DateTime.utc_now()
        })
        |> Repo.update!()

        {:error, safe_reason(reason)}
    end
  end

  defp persist_event_and_job(connection, attrs, job_builder) do
    changeset =
      ConnectorEvent.changeset(
        %ConnectorEvent{},
        Map.merge(attrs, %{
          connection_id: connection.id,
          status: :accepted,
          received_at: DateTime.utc_now()
        })
      )

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:event, changeset)
    |> Oban.insert(:job, fn %{event: event} -> job_builder.(event) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{event: event}} ->
        {:ok, event, false}

      {:error, :event, %Ecto.Changeset{errors: errors}, _changes} ->
        if Keyword.has_key?(errors, :connection_id) do
          event =
            Repo.get_by!(ConnectorEvent,
              connection_id: connection.id,
              external_event_id: attrs.external_event_id
            )

          case ensure_event_job(event, job_builder) do
            :ok -> {:ok, event, true}
            {:error, _reason} -> {:error, :enqueue_failed}
          end
        else
          {:error, :invalid_event}
        end

      {:error, :job, _reason, _changes} ->
        {:error, :enqueue_failed}

      {:error, _operation, _reason, _changes} ->
        {:error, :enqueue_failed}
    end
  end

  defp ensure_event_job(event, job_builder) do
    case Oban.insert(job_builder.(event)) do
      {:ok, _job} -> :ok
      {:error, _reason} -> {:error, :enqueue_failed}
    end
  end

  defp connector_job(event) do
    ConnectorEventWorker.new(JobArgs.put(%{"event_id" => event.id}))
  end

  defp normalize_event(params) when is_map(params) do
    event_id = params["event_id"]
    event_kind = params["event"]
    contract_version = params["contract_version"]
    source_item_id = normalize_source_item_id(params["source_item_id"])
    source_modified_at = params["source_modified_at"]

    cond do
      contract_version not in @supported_contract_versions ->
        {:error, :unsupported_contract_version}

      not (is_binary(event_id) and byte_size(event_id) in 8..160) ->
        {:error, :invalid_event}

      event_kind not in @allowed_kinds ->
        {:error, :invalid_event}

      not (is_binary(source_item_id) and byte_size(source_item_id) in 1..255) ->
        {:error, :invalid_event}

      not valid_datetime?(source_modified_at) ->
        {:error, :invalid_event}

      true ->
        {:ok,
         %{
           contract_version: contract_version,
           external_event_id: event_id,
           event_kind: event_kind,
           source_item_key: source_item_id,
           source_modified_at: parse_datetime(source_modified_at)
         }}
    end
  end

  defp normalize_event(_params), do: {:error, :invalid_event}

  defp normalize_source_item_id(value) when is_binary(value), do: String.trim(value)
  defp normalize_source_item_id(_value), do: nil

  defp connector_definition(%Connection{adapter_key: adapter_key}) do
    case Definition.connector(adapter_key) do
      {:ok, connector} -> {:ok, connector}
      :error -> {:error, :not_found}
    end
  end

  defp connector_secrets(%Connection{credentials: credentials}) when is_map(credentials) do
    secrets =
      [credentials["connector_secret"], valid_previous_secret(credentials)]
      |> Enum.filter(&(is_binary(&1) and byte_size(&1) >= 32))

    if secrets == [], do: {:error, :connector_not_configured}, else: {:ok, secrets}
  end

  defp connector_secrets(_connection), do: {:error, :connector_not_configured}

  defp valid_previous_secret(credentials) do
    with secret when is_binary(secret) <- credentials["connector_previous_secret"],
         valid_until when is_binary(valid_until) <- credentials["connector_previous_valid_until"],
         {:ok, datetime, _offset} <- DateTime.from_iso8601(valid_until),
         :gt <- DateTime.compare(datetime, DateTime.utc_now()) do
      secret
    else
      _other -> nil
    end
  end

  defp verify_timestamp(timestamp) when is_binary(timestamp) do
    with {unix, ""} <- Integer.parse(timestamp),
         true <- abs(System.system_time(:second) - unix) <= @signature_window_seconds do
      :ok
    else
      _other -> {:error, :stale_signature}
    end
  end

  defp verify_timestamp(_timestamp), do: {:error, :stale_signature}

  defp verify_signature(secrets, timestamp, "sha256=" <> provided, raw_body)
       when is_binary(raw_body) do
    with {:ok, decoded} <- Base.decode16(provided, case: :mixed),
         true <-
           Enum.any?(secrets, fn secret ->
             expected = :crypto.mac(:hmac, :sha256, secret, timestamp <> "." <> raw_body)

             byte_size(decoded) == byte_size(expected) and
               Plug.Crypto.secure_compare(decoded, expected)
           end) do
      :ok
    else
      _other -> {:error, :invalid_signature}
    end
  end

  defp verify_signature(_secrets, _timestamp, _signature, _raw_body),
    do: {:error, :invalid_signature}

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _other -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp valid_datetime?(nil), do: true

  defp valid_datetime?(value) when is_binary(value) do
    match?({:ok, _datetime, _offset}, DateTime.from_iso8601(value))
  end

  defp valid_datetime?(_value), do: false

  defp safe_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp safe_reason(reason) when is_binary(reason), do: reason
  defp safe_reason(_reason), do: "Connector event processing failed"
end
