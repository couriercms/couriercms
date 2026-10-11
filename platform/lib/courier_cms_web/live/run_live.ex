defmodule CourierCMSWeb.RunLive do
  use CourierCMSWeb, :live_view

  @progress_refresh_interval 2_000
  @item_statuses ~w(all pending processing succeeded retrying failed skipped cancelled)
  @asset_statuses ~w(all pending processing succeeded retrying failed skipped cancelled)

  alias CourierCMS.Accounts.Scope
  alias CourierCMS.Execution

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      socket
      |> assign(
        items_visible?: false,
        run_items_page: nil,
        item_status: "all",
        item_source_query: "",
        item_statuses: @item_statuses,
        assets_visible?: false,
        run_assets_page: nil,
        asset_status: "all",
        asset_source_query: "",
        asset_statuses: @asset_statuses
      )
      |> assign_run(id)

    if connected?(socket) do
      Execution.subscribe(id)
      schedule_progress_refresh(socket.assigns.run)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info({:run_updated, id}, socket) do
    {:noreply,
     socket
     |> assign_run(id)
     |> refresh_items()
     |> refresh_assets()}
  end

  def handle_info(:refresh_active_run, socket) do
    socket = assign_run(socket, socket.assigns.run.id)
    schedule_progress_refresh(socket.assigns.run)
    {:noreply, socket}
  end

  @impl true
  def handle_event("retry", %{"id" => item_id}, socket) do
    case Execution.retry_run_item(socket.assigns.current_scope, item_id) do
      {:ok, _job} ->
        {:noreply,
         socket
         |> put_flash(:info, "Delivery queued for retry.")
         |> assign_run(socket.assigns.run.id)
         |> refresh_items()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "This item cannot be retried in its current state.")}
    end
  end

  def handle_event("retry-asset", %{"id" => asset_id}, socket) do
    case Execution.retry_run_asset(socket.assigns.current_scope, asset_id) do
      {:ok, _jobs} ->
        {:noreply,
         socket
         |> put_flash(:info, "Asset and affected Delivery Items queued for retry.")
         |> assign_run(socket.assigns.run.id)
         |> refresh_items()
         |> refresh_assets()}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, "This asset cannot be retried in its current state.")}
    end
  end

  def handle_event("show-items", params, socket) do
    status = normalize_status(params["status"])

    {:noreply,
     socket
     |> assign(items_visible?: true, item_status: status)
     |> load_items(1)}
  end

  def handle_event("hide-items", _params, socket) do
    {:noreply, assign(socket, items_visible?: false, run_items_page: nil)}
  end

  def handle_event("filter-items", %{"filters" => filters}, socket) do
    {:noreply,
     socket
     |> assign(
       items_visible?: true,
       item_status: normalize_status(filters["status"]),
       item_source_query: String.trim(filters["source"] || "")
     )
     |> load_items(1)}
  end

  def handle_event("items-page", %{"page" => page}, socket) do
    {:noreply, load_items(socket, parse_page(page))}
  end

  def handle_event("show-assets", params, socket) do
    status = normalize_asset_status(params["status"])

    {:noreply,
     socket
     |> assign(assets_visible?: true, asset_status: status)
     |> load_assets(1)}
  end

  def handle_event("hide-assets", _params, socket) do
    {:noreply, assign(socket, assets_visible?: false, run_assets_page: nil)}
  end

  def handle_event("filter-assets", %{"filters" => filters}, socket) do
    {:noreply,
     socket
     |> assign(
       assets_visible?: true,
       asset_status: normalize_asset_status(filters["status"]),
       asset_source_query: String.trim(filters["source"] || "")
     )
     |> load_assets(1)}
  end

  def handle_event("assets-page", %{"page" => page}, socket) do
    {:noreply, load_assets(socket, parse_page(page))}
  end

  def handle_event("cancel", _params, socket) do
    case Execution.cancel_run(socket.assigns.current_scope, socket.assigns.run.id) do
      {:ok, _run} ->
        {:noreply,
         socket
         |> put_flash(:info, "Run cancelled. Completed deliveries remain in the target.")
         |> assign_run(socket.assigns.run.id)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "This Run cannot be cancelled.")}
    end
  end

  defp assign_run(socket, id) do
    run = Execution.get_run!(socket.assigns.current_scope, id)

    assign(socket,
      page_title: "Run #{String.slice(run.id, 0, 8)}",
      run: run,
      progress: progress(run),
      can_retry?: Scope.role?(socket.assigns.current_scope, [:owner, :admin, :operator]),
      can_cancel?: Scope.role?(socket.assigns.current_scope, [:owner, :admin, :operator])
    )
  end

  defp load_items(socket, page) do
    result =
      Execution.list_run_items(socket.assigns.current_scope, socket.assigns.run.id,
        page: page,
        status: status_atom(socket.assigns.item_status),
        source_query: socket.assigns.item_source_query
      )

    assign(socket, run_items_page: result)
  end

  defp load_assets(socket, page) do
    result =
      Execution.list_run_assets(socket.assigns.current_scope, socket.assigns.run.id,
        page: page,
        status: status_atom(socket.assigns.asset_status),
        source_query: socket.assigns.asset_source_query
      )

    assign(socket, run_assets_page: result)
  end

  defp refresh_items(%{assigns: %{items_visible?: true, run_items_page: page}} = socket)
       when not is_nil(page),
       do: load_items(socket, page.page)

  defp refresh_items(socket), do: socket

  defp refresh_assets(%{assigns: %{assets_visible?: true, run_assets_page: page}} = socket)
       when not is_nil(page),
       do: load_assets(socket, page.page)

  defp refresh_assets(socket), do: socket

  defp normalize_status(status) when status in @item_statuses, do: status
  defp normalize_status(_status), do: "all"

  defp normalize_asset_status(status) when status in @asset_statuses, do: status
  defp normalize_asset_status(_status), do: "all"

  defp status_atom("all"), do: nil
  defp status_atom(status), do: String.to_existing_atom(status)

  defp parse_page(page) do
    case Integer.parse(page) do
      {page, ""} when page > 0 -> page
      _other -> 1
    end
  end

  defp progress(%{items_discovered: 0}), do: 0

  defp progress(run),
    do:
      round(
        (run.items_succeeded + run.items_failed + run.items_skipped) / run.items_discovered * 100
      )

  defp schedule_progress_refresh(run) do
    if run.status in [:queued, :planning, :running] do
      Process.send_after(self(), :refresh_active_run, @progress_refresh_interval)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <.header>
          Run {String.slice(@run.id, 0, 8)}
          <:subtitle>
            <.link navigate={~p"/routes/#{@run.route.id}"} class="hover:text-primary">{@run.route.name}</.link>
            · {@run.trigger_kind}
          </:subtitle>
        </.header>
        <div class="flex items-center gap-2">
          <button
            :if={@can_cancel? && @run.status in [:queued, :planning, :running]}
            phx-click="cancel"
            data-confirm="Cancel this Run? Completed target deliveries will remain."
            class="btn btn-outline btn-error btn-sm"
          >Cancel Run</button>
          <span class={[
            "badge badge-lg capitalize",
            @run.status == :succeeded && "badge-success",
            @run.status == :failed && "badge-error",
            @run.status == :partially_succeeded && "badge-warning",
            @run.status == :cancelled && "badge-ghost",
            @run.status in [:queued, :planning, :running] && "badge-info"
          ]}>{status_label(@run.status)}</span>
        </div>
      </div>

      <div :if={@run.error_summary} class="alert alert-error" role="alert">
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <div>
          <p class="font-semibold">Run planning failed</p>
          <p class="text-sm">{@run.error_summary}</p>
          <p :if={@run.error_category} class="mt-1 font-mono text-xs opacity-70">
            {@run.error_category}
          </p>
        </div>
      </div>

      <section class="card border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body">
          <div class="flex items-center justify-between text-sm">
            <span class="font-semibold">Delivery progress</span><span>{@progress}%</span>
          </div>
          <progress class="progress progress-primary w-full" value={@progress} max="100"></progress>
          <p :if={run_summary(@run)} class="mt-2 text-sm text-base-content/60">
            {run_summary(@run)}
          </p>
          <div class="mt-2 grid grid-cols-2 gap-3 sm:grid-cols-5">
            <.count label="Discovered" value={@run.items_discovered} status="all" />
            <.count
              label="Created / updated"
              value={@run.items_succeeded}
              tone="text-success"
              status="succeeded"
            />
            <.count label="Retrying" value={@run.items_retrying} tone="text-info" status="retrying" />
            <.count label="Failed" value={@run.items_failed} tone="text-error" status="failed" />
            <.count label="Unchanged" value={@run.items_skipped} status="skipped" />
          </div>
          <p class="mt-3 text-xs text-base-content/50">
            Select a summary to inspect a bounded page of matching Delivery Items.
          </p>
        </div>
      </section>

      <section
        :if={@run.assets_discovered > 0}
        class="card border border-base-300 bg-base-100 shadow-sm"
      >
        <div class="card-body">
          <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h2 class="card-title">Delivery assets</h2>
              <p class="text-sm text-base-content/60">
                Independently delivered files and media required by this Run.
              </p>
            </div>
            <button
              :if={!@assets_visible?}
              id="show-delivery-assets"
              phx-click="show-assets"
              class="btn btn-outline btn-sm"
            >Browse delivery assets</button>
          </div>
          <div class="mt-2 grid grid-cols-2 gap-3 sm:grid-cols-5">
            <.asset_count label="Discovered" value={@run.assets_discovered} status="all" />
            <.asset_count
              label="Created / updated"
              value={@run.assets_succeeded}
              tone="text-success"
              status="succeeded"
            />
            <.asset_count
              label="Retrying"
              value={@run.assets_retrying}
              tone="text-info"
              status="retrying"
            />
            <.asset_count
              label="Failed"
              value={@run.assets_failed}
              tone="text-error"
              status="failed"
            />
            <.asset_count label="Unchanged" value={@run.assets_skipped} status="skipped" />
          </div>
        </div>
      </section>

      <section
        :if={@assets_visible?}
        id="delivery-assets"
        class="card border border-base-300 bg-base-100 shadow-sm"
      >
        <div class="card-body overflow-x-auto">
          <div class="flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <h2 class="card-title">Delivery assets</h2>
              <p class="text-sm text-base-content/60">
                {@run_assets_page.total_count} matching asset{if @run_assets_page.total_count == 1,
                  do: "",
                  else: "s"}.
              </p>
            </div>
            <form
              phx-submit="filter-assets"
              id="run-asset-filters"
              class="flex flex-col gap-2 sm:flex-row sm:items-end"
            >
              <label class="form-control">
                <span class="label-text text-xs">Status</span>
                <select name="filters[status]" class="select select-bordered select-sm">
                  <option
                    :for={status <- @asset_statuses}
                    value={status}
                    selected={status == @asset_status}
                  >
                    {item_status_label(status)}
                  </option>
                </select>
              </label>
              <label class="form-control">
                <span class="label-text text-xs">Source asset ID or filename</span>
                <input
                  type="search"
                  name="filters[source]"
                  value={@asset_source_query}
                  placeholder="Search assets"
                  class="input input-bordered input-sm"
                />
              </label>
              <button class="btn btn-primary btn-sm" type="submit">Apply</button>
              <button class="btn btn-ghost btn-sm" type="button" phx-click="hide-assets">
                Close
              </button>
            </form>
          </div>
          <table class="table mt-3">
            <thead>
              <tr>
                <th>Source asset</th><th>File</th><th>Operation</th><th>Attempts</th><th>Status</th><th>
                  Target / error
                </th><th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={entry <- @run_assets_page.items} id={"run-asset-#{entry.run_asset.id}"}>
                <td class="font-mono font-semibold">{entry.delivery_asset.source_asset_key}</td>
                <td>
                  <p class="text-sm">{entry.delivery_asset.filename || "—"}</p>
                  <p class="text-xs text-base-content/45">{entry.delivery_asset.media_type}</p>
                </td>
                <td class="capitalize">{entry.run_asset.planned_operation || "—"}</td>
                <td>{entry.run_asset.attempt_count}</td>
                <td>
                  <span class={[
                    "badge badge-sm capitalize",
                    entry.run_asset.status == :succeeded && "badge-success",
                    entry.run_asset.status == :failed && "badge-error",
                    entry.run_asset.status == :retrying && "badge-info",
                    entry.run_asset.status == :skipped && "badge-ghost"
                  ]}>{entry.run_asset.status}</span>
                </td>
                <td class="max-w-xs text-xs">
                  <p :if={entry.run_asset.error_summary} class="text-error">
                    {entry.run_asset.error_summary}
                  </p>
                  <p
                    :if={entry.binding && !entry.run_asset.error_summary}
                    class="truncate font-mono text-base-content/60"
                    title={entry.binding.target_reference}
                  >
                    {entry.binding.target_reference}
                  </p>
                </td>
                <td>
                  <button
                    :if={entry.run_asset.status == :failed && @can_retry?}
                    phx-click="retry-asset"
                    phx-value-id={entry.run_asset.id}
                    class="btn btn-ghost btn-xs"
                  >Retry</button>
                </td>
              </tr>
            </tbody>
          </table>
          <p :if={@run_assets_page.items == []} class="py-8 text-center text-sm text-base-content/55">
            No Delivery Assets match this filter.
          </p>
          <div :if={@run_assets_page.total_pages > 1} class="mt-4 flex items-center justify-between">
            <button
              phx-click="assets-page"
              phx-value-page={@run_assets_page.page - 1}
              disabled={@run_assets_page.page == 1}
              class="btn btn-outline btn-sm"
            >Previous</button>
            <span class="text-sm text-base-content/60">
              Page {@run_assets_page.page} of {@run_assets_page.total_pages}
            </span>
            <button
              phx-click="assets-page"
              phx-value-page={@run_assets_page.page + 1}
              disabled={@run_assets_page.page == @run_assets_page.total_pages}
              class="btn btn-outline btn-sm"
            >Next</button>
          </div>
        </div>
      </section>

      <section :if={!@items_visible?} class="card border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body items-start sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h2 class="card-title">Delivery items</h2>
            <p class="text-sm text-base-content/60">
              Items are loaded only when requested so large Runs remain fast and memory-efficient.
            </p>
          </div>
          <button id="show-delivery-items" phx-click="show-items" class="btn btn-outline btn-sm">
            Browse delivery items
          </button>
        </div>
      </section>

      <section
        :if={@items_visible?}
        id="delivery-items"
        class="card border border-base-300 bg-base-100 shadow-sm"
      >
        <div class="card-body overflow-x-auto">
          <div class="flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <h2 class="card-title">Delivery items</h2>
              <p class="text-sm text-base-content/60">
                {@run_items_page.total_count} matching item{if @run_items_page.total_count == 1,
                  do: "",
                  else: "s"}.
              </p>
            </div>
            <form
              phx-submit="filter-items"
              id="run-item-filters"
              class="flex flex-col gap-2 sm:flex-row sm:items-end"
            >
              <label class="form-control">
                <span class="label-text text-xs">Status</span>
                <select name="filters[status]" class="select select-bordered select-sm">
                  <option
                    :for={status <- @item_statuses}
                    value={status}
                    selected={status == @item_status}
                  >
                    {item_status_label(status)}
                  </option>
                </select>
              </label>
              <label class="form-control">
                <span class="label-text text-xs">Source item ID</span>
                <input
                  type="search"
                  name="filters[source]"
                  value={@item_source_query}
                  placeholder="Search source ID"
                  class="input input-bordered input-sm"
                />
              </label>
              <button class="btn btn-primary btn-sm" type="submit">Apply</button>
              <button class="btn btn-ghost btn-sm" type="button" phx-click="hide-items">Close</button>
            </form>
          </div>
          <table class="table mt-3">
            <thead>
              <tr>
                <th>Source</th><th>Locale / revision</th><th>Operation</th><th>Attempts</th><th>
                  Status
                </th><th>Error</th><th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={item <- @run_items_page.items} id={"run-item-#{item.id}"}>
                <td class="font-mono font-semibold">{item.source_item_key}</td>
                <td>
                  <span class="text-sm">{item.locale_key}</span><span class="ml-2 text-xs text-base-content/45">rev {item.source_revision_key}</span>
                </td>
                <td class="capitalize">{item.planned_operation || "—"}</td>
                <td>{item.attempt_count}</td>
                <td>
                  <span class={[
                    "badge badge-sm capitalize",
                    item.status == :succeeded && "badge-success",
                    item.status == :failed && "badge-error",
                    item.status == :retrying && "badge-info",
                    item.status == :skipped && "badge-ghost"
                  ]}>{item.status}</span>
                </td>
                <td class="max-w-xs text-xs text-error">{item.error_summary}</td>
                <td>
                  <button
                    :if={item.status == :failed && @can_retry?}
                    phx-click="retry"
                    phx-value-id={item.id}
                    class="btn btn-ghost btn-xs"
                  >Retry</button>
                </td>
              </tr>
            </tbody>
          </table>
          <p :if={@run_items_page.items == []} class="py-8 text-center text-sm text-base-content/55">
            No Delivery Items match this filter.
          </p>
          <div :if={@run_items_page.total_pages > 1} class="mt-4 flex items-center justify-between">
            <button
              phx-click="items-page"
              phx-value-page={@run_items_page.page - 1}
              disabled={@run_items_page.page == 1}
              class="btn btn-outline btn-sm"
            >Previous</button>
            <span class="text-sm text-base-content/60">
              Page {@run_items_page.page} of {@run_items_page.total_pages}
            </span>
            <button
              phx-click="items-page"
              phx-value-page={@run_items_page.page + 1}
              disabled={@run_items_page.page == @run_items_page.total_pages}
              class="btn btn-outline btn-sm"
            >Next</button>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :tone, :string, default: ""
  attr :status, :string, required: true

  defp count(assigns) do
    ~H"""
    <button
      id={"show-#{@status}-items"}
      type="button"
      phx-click="show-items"
      phx-value-status={@status}
      class="rounded-xl bg-base-200 p-3 text-center transition hover:bg-base-300 focus:outline-none focus:ring-2 focus:ring-primary"
      aria-label={"Browse #{@label} Delivery Items"}
    >
      <p class={["text-2xl font-black", @tone]}>{@value}</p><p class="text-xs text-base-content/50">
        {@label}
      </p>
    </button>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :tone, :string, default: ""
  attr :status, :string, required: true

  defp asset_count(assigns) do
    ~H"""
    <button
      id={"show-#{@status}-assets"}
      type="button"
      phx-click="show-assets"
      phx-value-status={@status}
      class="rounded-xl bg-base-200 p-3 text-center transition hover:bg-base-300 focus:outline-none focus:ring-2 focus:ring-primary"
      aria-label={"Browse #{@label} Delivery Assets"}
    >
      <p class={["text-2xl font-black", @tone]}>{@value}</p><p class="text-xs text-base-content/50">
        {@label}
      </p>
    </button>
    """
  end

  defp status_label(:all), do: "All statuses"

  defp status_label(:succeeded), do: "Completed"
  defp status_label(status), do: status |> to_string() |> String.replace("_", " ")

  defp item_status_label("all"), do: "All statuses"
  defp item_status_label(status), do: status |> String.replace("_", " ") |> String.capitalize()

  defp run_summary(%{status: :succeeded, items_succeeded: 0, items_skipped: skipped})
       when skipped > 0,
       do: "Completed — #{skipped} unchanged; no target writes were needed."

  defp run_summary(%{status: :succeeded, items_succeeded: written, items_skipped: skipped})
       when written > 0,
       do: "Completed — #{written} created or updated, #{skipped} unchanged."

  defp run_summary(_run), do: nil
end
