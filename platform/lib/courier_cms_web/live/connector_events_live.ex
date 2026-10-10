defmodule CourierCMSWeb.ConnectorEventsLive do
  use CourierCMSWeb, :live_view

  alias CourierCMS.Connectors

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Connector events",
       events: Connectors.list_events(socket.assigns.current_scope)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Connector events
        <:subtitle>Signed notifications received from CMS-installed Connectors.</:subtitle>
      </.header>

      <section class="card border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body overflow-x-auto">
          <p :if={@events == []} class="text-sm text-base-content/60">
            No Connector events received yet.
          </p>
          <table :if={@events != []} class="table">
            <thead>
              <tr>
                <th>Received</th>
                <th>Connection</th>
                <th>Event</th>
                <th>Source item</th>
                <th>Runs</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={event <- @events} id={"connector-event-#{event.id}"}>
                <td class="whitespace-nowrap text-xs">
                  {Calendar.strftime(event.received_at, "%Y-%m-%d %H:%M:%S")}
                </td>
                <td>{event.connection.name}</td>
                <td>
                  <code class="text-xs">v{event.contract_version} {event.event_kind}</code>
                </td>
                <td class="font-mono">{event.source_item_key}</td>
                <td>{event.runs_started}</td>
                <td>
                  <span class={[
                    "badge badge-sm capitalize",
                    event.status == :processed && "badge-success",
                    event.status == :failed && "badge-error",
                    event.status in [:accepted, :processing] && "badge-info",
                    event.status == :ignored && "badge-ghost"
                  ]}>{event.status}</span>
                  <p :if={event.error_summary} class="mt-1 max-w-xs text-xs text-error">
                    {event.error_summary}
                  </p>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
