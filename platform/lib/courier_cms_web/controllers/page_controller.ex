defmodule CourierCMSWeb.PageController do
  use CourierCMSWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
