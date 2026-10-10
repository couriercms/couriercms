defmodule CourierCMSWeb.DeliveriesLive do
  use CourierCMSWeb, :live_view

  alias CourierCMS.Execution

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Deliveries",
       deliveries: Execution.list_delivery_items(socket.assigns.current_scope)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Delivery Items
        <:subtitle>
          The latest CourierCMS-owned target bindings accepted by configured Destinations.
        </:subtitle>
      </.header>

      <div
        :if={@deliveries == []}
        class="rounded-3xl border border-dashed border-base-300 bg-base-100 p-12 text-center"
      >
        <.icon name="hero-inbox" class="mx-auto size-10 text-base-content/30" />
        <p class="mt-3 font-semibold">No Delivery Items yet</p>
        <p class="mt-1 text-sm text-base-content/55">Run an active Route from the overview.</p>
      </div>

      <div
        :if={@deliveries != []}
        class="overflow-x-auto rounded-2xl border border-base-300 bg-base-100"
      >
        <table class="table">
          <thead>
            <tr>
              <th>Route</th>
              <th>Source identity</th>
              <th>Locale</th>
              <th>Target identity</th>
              <th>Status</th>
              <th>Last delivered</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={delivery <- @deliveries} id={"delivery-#{delivery.id}"}>
              <td class="font-medium">{delivery.route_item.route.name}</td>
              <td class="font-mono text-xs">{delivery.route_item.source_item_key}</td>
              <td>{delivery.route_item.locale_key}</td>
              <td class="max-w-72 truncate font-mono text-xs">
                {delivery.target_reference || "Pending"}
              </td>
              <td><span class="badge badge-outline">{delivery.state}</span></td>
              <td>{format_datetime(delivery.last_delivered_at)}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end

  defp format_datetime(nil), do: "Not yet delivered"
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")
end
