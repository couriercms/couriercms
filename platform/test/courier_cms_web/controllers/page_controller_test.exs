defmodule CourierCMSWeb.DashboardLiveTest do
  use CourierCMSWeb.ConnCase
  setup :register_and_log_in_user

  test "renders the CMS-neutral overview", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Reliable CMS content delivery"
    assert html =~ "CMS-aware content transport"
  end
end
