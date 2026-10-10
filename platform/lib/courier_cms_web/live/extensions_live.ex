defmodule CourierCMSWeb.ExtensionsLive do
  use CourierCMSWeb, :live_view

  on_mount {CourierCMSWeb.UserAuth, {:require_role, [:owner, :admin]}}

  alias CourierCMS.Extensions

  @impl true
  def mount(_params, _session, socket) do
    {:ok, inventory} = Extensions.operator_inventory(socket.assigns.current_scope)

    {:ok,
     assign(socket,
       page_title: "Extensions",
       inventory: inventory
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        System · Extensions
        <:subtitle>
          Startup-loaded native components and safe package lifecycle diagnostics for this node.
        </:subtitle>
      </.header>

      <div class="alert alert-info">
        <.icon name="hero-information-circle" class="size-5" />
        <div>
          <p class="font-semibold">Packages are read-only while CourierCMS is running.</p>
          <p class="text-sm">
            Stage and verify a package, pause and drain affected Routes, replace it atomically,
            then restart eligible nodes. Queued work remains durable in PostgreSQL.
          </p>
        </div>
      </div>

      <section class="grid gap-4 sm:grid-cols-3">
        <.metric label="Node" value={@inventory.node} hint="Node-local registry" />
        <.metric
          label="Available Extensions"
          value={Enum.count(@inventory.extensions, &(&1.status == :loaded))}
          hint="Registered on this node"
        />
        <.metric
          label="Rejected packages"
          value={length(@inventory.rejected_packages)}
          hint="Require operator action"
        />
      </section>

      <section class="card border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body">
          <div class="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h2 class="card-title">Cluster package consistency</h2>
              <p class="text-sm text-base-content/70">
                Fresh node heartbeats are compared with the package set loaded by this node.
              </p>
            </div>
            <span class={cluster_badge(@inventory.cluster.consistent?)}>
              {if @inventory.cluster.consistent?, do: "consistent", else: "mismatch"}
            </span>
          </div>

          <div class="mt-2 overflow-x-auto">
            <table class="table">
              <thead>
                <tr>
                  <th>Node</th><th>Role</th><th>Release</th><th>Extension state</th><th>
                    Fingerprint
                  </th><th>Seen</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={node <- @inventory.cluster.fresh_nodes}>
                  <td class="font-mono text-xs">{node.node_id}</td>
                  <td><span class="badge badge-outline">{node.role}</span></td>
                  <td>{node.version}</td>
                  <td>
                    <span class={node_status_badge(node)}>
                      {if node.matches_local, do: node.status, else: "mismatch"}
                    </span>
                  </td>
                  <td class="font-mono text-xs">{short_checksum(node.fingerprint)}</td>
                  <td class="text-xs">
                    {Calendar.strftime(node.last_seen_at, "%Y-%m-%d %H:%M:%S UTC")}
                  </td>
                </tr>
                <tr :if={@inventory.cluster.fresh_nodes == []}>
                  <td colspan="6" class="text-center text-base-content/55">
                    No fresh persisted node heartbeats. This node's local registry is still shown below.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </section>

      <section class="space-y-4">
        <div
          :for={extension <- @inventory.extensions}
          id={"extension-#{extension.extension_id}"}
          class="card border border-base-300 bg-base-100 shadow-sm"
        >
          <div class="card-body gap-5">
            <div class="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
              <div>
                <div class="flex flex-wrap items-center gap-2">
                  <h2 class="card-title">{extension.name || extension.extension_id}</h2>
                  <span class={status_badge(extension.status)}>{extension.status}</span>
                  <span :if={extension.provenance} class="badge badge-outline">
                    {extension.provenance}
                  </span>
                </div>
                <p class="mt-1 font-mono text-xs text-base-content/55">
                  {extension.extension_id}
                </p>
                <p class="mt-2 text-sm text-base-content/70">{extension.message}</p>
              </div>

              <div class="grid grid-cols-2 gap-x-6 gap-y-2 text-sm sm:grid-cols-3">
                <.fact label="Version" value={extension.version || "Unavailable"} />
                <.fact label="OTP application" value={extension.application || "Unavailable"} />
                <.fact label="SDK" value={extension.sdk_compatibility || "Unavailable"} />
                <.fact label="Package" value={extension.package || "Bundled"} />
                <.fact label="Node" value={extension.node} />
                <.fact label="Checksum" value={short_checksum(extension.checksum)} mono />
              </div>
            </div>

            <div class="grid gap-4 lg:grid-cols-2">
              <div>
                <h3 class="mb-2 text-xs font-bold uppercase tracking-widest text-base-content/45">
                  Components
                </h3>
                <div class="space-y-2">
                  <div
                    :for={component <- extension.components}
                    class="rounded-xl border border-base-300 px-4 py-3"
                  >
                    <div class="flex flex-wrap items-center gap-2">
                      <span class="font-mono text-sm font-semibold">{component.id}</span>
                      <span :if={component.kind} class="badge badge-sm badge-outline">
                        {component.kind}
                      </span>
                      <span :if={!component.available} class="badge badge-sm badge-error">
                        missing
                      </span>
                    </div>
                    <div class="mt-2 flex flex-wrap gap-1">
                      <span
                        :for={capability <- component.capabilities}
                        class="badge badge-sm badge-ghost"
                      >
                        {capability}
                      </span>
                    </div>
                  </div>
                </div>
              </div>

              <div>
                <h3 class="mb-2 text-xs font-bold uppercase tracking-widest text-base-content/45">
                  Durable references
                </h3>
                <div class="grid grid-cols-2 gap-2 sm:grid-cols-3">
                  <.reference label="Connections" value={extension.references.connections} />
                  <.reference
                    label="Enabled connections"
                    value={extension.references.enabled_connections}
                  />
                  <.reference label="Routes" value={extension.references.routes} />
                  <.reference label="Active routes" value={extension.references.active_routes} />
                  <.reference
                    label="Unfinished runs"
                    value={extension.references.unfinished_runs}
                  />
                </div>
                <div class={removal_class(extension.references)}>
                  {removal_message(extension.references)}
                </div>
              </div>
            </div>
          </div>
        </div>

        <div
          :if={@inventory.extensions == []}
          class="rounded-xl border border-dashed border-base-300 bg-base-100 p-8 text-center"
        >
          No Extension components are registered on this node.
        </div>
      </section>

      <section
        :if={@inventory.rejected_packages != []}
        class="card border border-error/40 bg-base-100"
      >
        <div class="card-body">
          <h2 class="card-title text-error">Rejected packages</h2>
          <p class="text-sm text-base-content/70">
            Rejected packages never enter the code path or Component Registry.
          </p>
          <div class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr>
                  <th>Package</th><th>Identity</th><th>Reason</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={diagnostic <- @inventory.rejected_packages}>
                  <td class="font-mono text-xs">{diagnostic.package}</td>
                  <td>{diagnostic.extension_id || "Not readable"}</td>
                  <td class="text-error">{diagnostic.message}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :mono, :boolean, default: false

  defp fact(assigns) do
    ~H"""
    <div>
      <div class="text-xs text-base-content/45">{@label}</div>
      <div class={["max-w-48 truncate font-medium", @mono && "font-mono text-xs"]} title={@value}>
        {@value}
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :hint, :string, required: true

  defp metric(assigns) do
    ~H"""
    <div class="card border border-base-300 bg-base-100 shadow-sm">
      <div class="card-body gap-1 p-5">
        <div class="text-xs font-bold uppercase tracking-widest text-base-content/45">{@label}</div>
        <div class="truncate text-2xl font-black" title={to_string(@value)}>{@value}</div>
        <div class="text-xs text-base-content/55">{@hint}</div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp reference(assigns) do
    ~H"""
    <div class="rounded-lg bg-base-200/70 p-3">
      <div class="text-xl font-bold">{@value}</div>
      <div class="text-xs text-base-content/55">{@label}</div>
    </div>
    """
  end

  defp status_badge(:loaded), do: "badge badge-success"
  defp status_badge(_status), do: "badge badge-error"

  defp cluster_badge(true), do: "badge badge-success"
  defp cluster_badge(false), do: "badge badge-error"

  defp node_status_badge(%{matches_local: false}), do: "badge badge-error"
  defp node_status_badge(%{status: "ok"}), do: "badge badge-success"
  defp node_status_badge(_node), do: "badge badge-warning"

  defp short_checksum(nil), do: "Unavailable"
  defp short_checksum(checksum), do: String.slice(checksum, 0, 12) <> "…"

  defp removal_class(references) do
    if removable?(references),
      do: "alert alert-success mt-3 py-2 text-sm",
      else: "alert alert-warning mt-3 py-2 text-sm"
  end

  defp removal_message(references) do
    if removable?(references) do
      "No active references block removal. Historical disabled references remain visible."
    else
      "Removal blocked: disable affected Connections and Routes, then allow unfinished Runs to drain."
    end
  end

  defp removable?(references) do
    references.enabled_connections == 0 and references.active_routes == 0 and
      references.unfinished_runs == 0
  end
end
