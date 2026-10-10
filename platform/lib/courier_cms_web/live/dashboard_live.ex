defmodule CourierCMSWeb.DashboardLive do
  use CourierCMSWeb, :live_view

  alias CourierCMS.Accounts.Scope
  alias CourierCMS.{Connections, Execution, Routes}

  @impl true
  def mount(_params, _session, socket), do: {:ok, load(socket)}

  @impl true
  def handle_event("run", %{"id" => route_id}, socket) do
    case Execution.start_manual_run(socket.assigns.current_scope, route_id) do
      {:ok, run} ->
        {:noreply, push_navigate(socket, to: ~p"/runs/#{run.id}")}

      {:error, :route_not_active} ->
        {:noreply, put_flash(socket, :error, "Activate the Route before running it.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "The Run could not be started.")}
    end
  end

  defp load(socket) do
    scope = socket.assigns.current_scope

    assign(socket,
      page_title: "Overview",
      connections: Connections.list_connections(scope),
      routes: Routes.list_routes(scope),
      runs: Execution.list_runs(scope, 8),
      can_run?: Scope.role?(scope, [:owner, :admin, :operator])
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="rounded-3xl bg-neutral px-7 py-9 text-neutral-content shadow-xl sm:px-10">
        <div class="max-w-3xl">
          <div class="mb-4 inline-flex items-center gap-2 rounded-full border border-white/15 px-3 py-1 text-xs font-semibold uppercase tracking-wider text-white/70">
            CMS-aware content transport
          </div>
          <h1 class="text-3xl font-black tracking-tight sm:text-5xl">
            Reliable CMS content delivery, visible end to end.
          </h1>
          <p class="mt-4 max-w-2xl text-base text-white/65 sm:text-lg">
            Configure one-way Routes, follow each delivery independently, and monitor the canonical content accepted by target Destinations.
          </p>
        </div>
      </section>

      <section class="grid gap-4 sm:grid-cols-3">
        <.metric label="Connections" value={length(@connections)} hint="CMS endpoints" />
        <.metric label="Routes" value={length(@routes)} hint="One source → one target" />
        <.metric label="Recent runs" value={length(@runs)} hint="Observable executions" />
      </section>

      <section class="grid gap-6 lg:grid-cols-[1.4fr_1fr]">
        <div class="card border border-base-300 bg-base-100 shadow-sm">
          <div class="card-body">
            <div class="flex items-center justify-between">
              <div>
                <h2 class="card-title">Routes</h2>
                <p class="text-sm text-base-content/60">
                  Select many source items and deliver each independently.
                </p>
              </div>
              <.button navigate={~p"/routes"}>Configure</.button>
            </div>
            <div
              :if={@routes == []}
              class="mt-5 rounded-2xl border border-dashed border-base-300 p-8 text-center text-base-content/60"
            >
              Create a Route to begin.
            </div>
            <div
              :for={route <- @routes}
              class="mt-4 flex flex-col gap-4 rounded-2xl border border-base-300 p-5 sm:flex-row sm:items-center"
            >
              <div class="min-w-0 flex-1">
                <div class="flex items-center gap-2">
                  <.link navigate={~p"/routes/#{route.id}"} class="font-bold hover:text-primary">{route.name}</.link>
                  <span class={[
                    "badge badge-sm",
                    route.enabled && "badge-success",
                    !route.enabled && "badge-ghost"
                  ]}>{if route.enabled, do: "Active", else: "Draft"}</span>
                </div>
                <p class="mt-1 truncate text-sm text-base-content/60">
                  {route.source_connection.name} → {route.target_connection.name}
                </p>
              </div>
              <button
                :if={route.enabled && @can_run?}
                id={"run-#{route.id}"}
                phx-click="run"
                phx-value-id={route.id}
                class="btn btn-primary btn-sm"
              ><.icon name="hero-play-solid" /> Run now</button>
            </div>
          </div>
        </div>

        <div class="card border border-base-300 bg-base-100 shadow-sm">
          <div class="card-body">
            <h2 class="card-title">Recent activity</h2>
            <p :if={@runs == []} class="mt-4 text-sm text-base-content/60">
              No Runs yet. Start an active Route.
            </p>
            <.link
              :for={run <- @runs}
              navigate={~p"/runs/#{run.id}"}
              class="mt-2 flex items-center justify-between rounded-xl border border-base-300 px-4 py-3 hover:border-primary/50"
            >
              <div>
                <p class="text-sm font-semibold">{run.route.name}</p>
                <p class="text-xs text-base-content/50">
                  {Calendar.strftime(run.inserted_at, "%b %d, %H:%M:%S")}
                </p>
              </div>
              <.status_badge status={run.status} />
            </.link>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :hint, :string, required: true

  defp metric(assigns) do
    ~H"""
    <div class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm">
      <p class="text-xs font-bold uppercase tracking-widest text-base-content/45">{@label}</p>
      <p class="mt-2 text-3xl font-black">{@value}</p>
      <p class="mt-1 text-sm text-base-content/55">{@hint}</p>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp status_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm capitalize",
      @status == :succeeded && "badge-success",
      @status == :failed && "badge-error",
      @status == :partially_succeeded && "badge-warning",
      @status in [:queued, :planning, :running] && "badge-info",
      @status == :cancelled && "badge-ghost"
    ]}>{@status |> to_string() |> String.replace("_", " ")}</span>
    """
  end
end
