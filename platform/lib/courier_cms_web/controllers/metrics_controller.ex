defmodule CourierCMSWeb.MetricsController do
  use CourierCMSWeb, :controller

  alias CourierCMS.Observability

  def index(conn, _params) do
    if authorized?(conn) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, Observability.prometheus())
    else
      conn
      |> put_resp_header("www-authenticate", ~s(Bearer realm="metrics"))
      |> send_resp(401, "unauthorized\n")
    end
  end

  defp authorized?(conn) do
    case Application.get_env(:couriercms, :metrics_token) do
      nil -> Application.get_env(:couriercms, :allow_unauthenticated_metrics, false)
      token when is_binary(token) and byte_size(token) >= 32 -> bearer_valid?(conn, token)
      _other -> false
    end
  end

  defp bearer_valid?(conn, expected) do
    with ["Bearer " <> supplied] <- get_req_header(conn, "authorization"),
         true <- byte_size(supplied) == byte_size(expected) do
      Plug.Crypto.secure_compare(supplied, expected)
    else
      _other -> false
    end
  end
end
