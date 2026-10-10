defmodule CourierCMSWeb.ConnectorEventController do
  use CourierCMSWeb, :controller

  alias CourierCMS.Connectors

  def create(conn, %{"connection_id" => connection_id} = params) do
    timestamp = header(conn, "x-couriercms-timestamp")
    signature = header(conn, "x-couriercms-signature")
    raw_body = conn.private[:raw_body] || ""
    event_params = Map.drop(params, ["connection_id"])

    case Connectors.accept_event(
           connection_id,
           timestamp,
           signature,
           raw_body,
           event_params
         ) do
      {:ok, event, duplicate?} ->
        status = if duplicate?, do: :ok, else: :accepted

        conn
        |> put_status(status)
        |> json(%{status: if(duplicate?, do: "duplicate", else: "accepted"), event_id: event.id})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "connector_not_found"})

      {:error, :connector_not_configured} ->
        conn |> put_status(:not_found) |> json(%{error: "connector_not_found"})

      {:error, reason} when reason in [:invalid_signature, :stale_signature] ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid_signature"})

      {:error, :invalid_event} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_event"})

      {:error, :unsupported_contract_version} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "unsupported_contract_version", supported_versions: [1]})

      {:error, _reason} ->
        conn |> put_status(:service_unavailable) |> json(%{error: "temporarily_unavailable"})
    end
  end

  defp header(conn, name), do: conn |> get_req_header(name) |> List.first()
end
