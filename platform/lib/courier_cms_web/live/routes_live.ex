defmodule CourierCMSWeb.RoutesLive do
  use CourierCMSWeb, :live_view
  on_mount {CourierCMSWeb.UserAuth, {:require_role, [:owner, :admin]}}

  alias CourierCMS.{Connections, Destinations, Mapping, Routes}
  alias CourierCMS.Adapters.Definition
  alias CourierCMS.ExtensionSDK.AdapterError
  alias CourierCMS.Extensions.Gateway
  alias CourierCMS.Transport.Projection

  @impl true
  def mount(_params, _session, socket) do
    connections = Connections.list_connections(socket.assigns.current_scope)
    sources = Enum.filter(connections, &source_connection?/1)
    targets = Enum.filter(connections, &target_connection?/1)
    source = List.first(sources)
    target = List.first(targets)
    destinations = Destinations.list_destinations(socket.assigns.current_scope)

    {:ok,
     assign(socket,
       page_title: "Routes",
       routes: Routes.list_routes(socket.assigns.current_scope),
       source_connections: sources,
       target_connections: targets,
       destinations: destinations,
       selected_source_id: source && source.id,
       selected_target_id: target && target.id,
       source_definition: source && source_definition(source),
       target_definition: target && target_definition(target),
       form: to_form(default_form(source, target, destinations), as: :route)
     )}
  end

  @impl true
  def handle_event("validate", %{"route" => params}, socket) do
    source_id = params["source_connection_id"]
    target_id = params["target_connection_id"]

    params =
      params
      |> maybe_reset_source(socket, source_id)
      |> maybe_reset_target(socket, target_id)

    source = find_connection(socket.assigns.source_connections, source_id)
    target = find_connection(socket.assigns.target_connections, target_id)

    {:noreply,
     assign(socket,
       selected_source_id: source_id,
       selected_target_id: target_id,
       source_definition: source && source_definition(source),
       target_definition: target && target_definition(target),
       destinations: Destinations.list_destinations(socket.assigns.current_scope),
       form: to_form(params, as: :route)
     )}
  end

  def handle_event("save", %{"route" => params}, socket) do
    source = find_connection(socket.assigns.source_connections, params["source_connection_id"])
    target = find_connection(socket.assigns.target_connections, params["target_connection_id"])

    route_attrs = %{
      name: params["name"],
      source_connection_id: params["source_connection_id"],
      target_connection_id: params["target_connection_id"],
      current_destination_id: params["current_destination_id"],
      enabled: params["enabled"] == "true",
      archived_at: nil
    }

    with %{} <- source || {:error, "Choose a source Connection."},
         %{} <- target || {:error, "Choose a target Connection."},
         {:ok, selection} <-
           Definition.cast_selection(source.adapter_key, params["selection"] || %{}),
         {:ok, mapping} <- Mapping.parse(params["mapping"]),
         {:ok, projections} <- Projection.parse(params["projections"]),
         {:ok, route} <-
           Routes.create_route(socket.assigns.current_scope, route_attrs, %{
             selection: selection,
             mapping: mapping,
             projections: projections,
             delivery_name_path: params["delivery_name_path"] || "payload.title"
           }) do
      {:noreply, push_navigate(socket, to: ~p"/routes/#{route.id}")}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, first_error(changeset))}

      {:error, %AdapterError{} = error} ->
        {:noreply, put_flash(socket, :error, error.message)}

      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      _other ->
        {:noreply, put_flash(socket, :error, "The Route could not be created.")}
    end
  end

  defp default_form(source, target, destinations) do
    source_key = source && source.adapter_key
    target_key = target && target.adapter_key

    %{
      "name" => "New content Route",
      "source_connection_id" => source && source.id,
      "target_connection_id" => target && target.id,
      "enabled" => "false",
      "selection" => Definition.default_selection(source_key),
      "mapping" => source_key |> Definition.default_mapping() |> Mapping.format(),
      "projections" => target_key |> Definition.default_projections() |> Projection.format(),
      "current_destination_id" => first_available_destination_id(destinations, target),
      "delivery_name_path" => "payload.title"
    }
  end

  defp maybe_reset_source(params, socket, source_id) do
    if source_id != socket.assigns.selected_source_id do
      source = find_connection(socket.assigns.source_connections, source_id)
      adapter_key = source && source.adapter_key

      params
      |> Map.put("selection", Definition.default_selection(adapter_key))
      |> Map.put("mapping", adapter_key |> Definition.default_mapping() |> Mapping.format())
    else
      params
    end
  end

  defp maybe_reset_target(params, socket, target_id) do
    if target_id != socket.assigns.selected_target_id do
      target = find_connection(socket.assigns.target_connections, target_id)
      adapter_key = target && target.adapter_key

      params
      |> Map.put(
        "projections",
        adapter_key |> Definition.default_projections() |> Projection.format()
      )
      |> Map.put(
        "current_destination_id",
        first_available_destination_id(socket.assigns.destinations, target)
      )
    else
      params
    end
  end

  defp source_definition(connection) do
    case Definition.source_definition(connection.adapter_key) do
      {:ok, definition} -> definition
      _error -> nil
    end
  end

  defp target_definition(connection) do
    case Definition.target_definition(connection.adapter_key) do
      {:ok, definition} -> definition
      _error -> nil
    end
  end

  defp find_connection(connections, id), do: Enum.find(connections, &(&1.id == id))

  defp source_connection?(connection),
    do: Gateway.source_available?(connection.adapter_key)

  defp target_connection?(connection),
    do: Gateway.target_available?(connection.adapter_key)

  defp selection_value(form, field) do
    selection = Map.get(form.params || %{}, "selection", %{})
    Definition.field_value(selection, field)
  end

  defp available_destination_options(destinations, target_id) do
    destinations
    |> Enum.filter(
      &(&1.target_connection_id == target_id && &1.lifecycle_status == :available &&
          &1.validation_status == :valid)
    )
    |> Enum.map(&{&1.name, &1.id})
  end

  defp first_available_destination_id(_destinations, nil), do: nil

  defp first_available_destination_id(destinations, target) do
    destinations
    |> available_destination_options(target.id)
    |> List.first()
    |> case do
      {_name, id} -> id
      nil -> nil
    end
  end

  defp first_error(changeset) do
    case changeset.errors do
      [{field, {message, _opts}} | _] -> "#{Phoenix.Naming.humanize(field)} #{message}."
      [] -> "The Route could not be created."
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Routes
        <:subtitle>
          Each Route owns one source, one target, one mapping, and an independent delivery history.
        </:subtitle>
      </.header>

      <div class="grid gap-6 xl:grid-cols-[1fr_1.1fr]">
        <section class="card border border-base-300 bg-base-100 shadow-sm">
          <div class="card-body">
            <h2 class="card-title">Configured Routes</h2>
            <div
              :if={@routes == []}
              class="rounded-2xl border border-dashed border-base-300 p-8 text-center text-base-content/60"
            >
              No Routes configured.
            </div>
            <.link
              :for={route <- @routes}
              navigate={~p"/routes/#{route.id}"}
              class="group rounded-2xl border border-base-300 p-5 hover:border-primary/50"
            >
              <div class="flex items-start justify-between gap-4">
                <div>
                  <p class="font-bold group-hover:text-primary">{route.name}</p>
                  <p class="mt-1 text-sm text-base-content/60">
                    {route.source_connection.name} → {route.target_connection.name}
                  </p>
                </div>
                <span class={[
                  "badge badge-sm",
                  route.enabled && is_nil(route.archived_at) && "badge-success",
                  (!route.enabled || route.archived_at) && "badge-ghost"
                ]}>
                  {cond do
                    route.archived_at -> "Archived"
                    route.enabled -> "Active"
                    true -> "Draft"
                  end}
                </span>
              </div>
              <p class="mt-3 font-mono text-xs text-base-content/40">
                Destination {route.current_destination.name}
              </p>
            </.link>
          </div>
        </section>

        <section class="card border border-base-300 bg-base-100 shadow-sm">
          <div class="card-body">
            <h2 class="card-title">Create Route</h2>
            <p class="text-sm text-base-content/60">
              Adapter capabilities define the available source selection and target projection options.
            </p>
            <div
              :if={@source_connections == [] || @target_connections == []}
              class="alert alert-warning mt-4"
            >
              Create at least one source Connection and one target Connection first.
            </div>
            <.form
              for={@form}
              id="route-form"
              phx-change="validate"
              phx-submit="save"
              class="mt-3 grid gap-3 sm:grid-cols-2"
            >
              <div class="sm:col-span-2"><.input field={@form[:name]} label="Route name" /></div>
              <.input
                field={@form[:source_connection_id]}
                type="select"
                label="Source"
                prompt="Choose source"
                options={Enum.map(@source_connections, &{&1.name, &1.id})}
              />
              <.input
                field={@form[:target_connection_id]}
                type="select"
                label="Target"
                prompt="Choose target"
                options={Enum.map(@target_connections, &{&1.name, &1.id})}
              />
              <.input
                field={@form[:current_destination_id]}
                type="select"
                label="Destination"
                prompt="Choose available Destination"
                options={available_destination_options(@destinations, @selected_target_id)}
              />
              <div
                :if={@source_definition}
                class="sm:col-span-2 rounded-xl border border-primary/20 bg-primary/5 p-4"
              >
                <p class="font-semibold">Collection of {@source_definition.content_label}</p>
                <p class="mt-1 text-xs text-base-content/60">{@source_definition.description}</p>
              </div>
              <.adapter_field
                :for={field <- (@source_definition && @source_definition.selection_fields) || []}
                field={field}
                name={"route[selection][#{field.key}]"}
                value={selection_value(@form, field)}
              />
              <div class="flex items-end">
                <.input field={@form[:enabled]} type="checkbox" label="Activate immediately" />
              </div>
              <div class="sm:col-span-2">
                <.input
                  field={@form[:delivery_name_path]}
                  label="Delivery Item name field"
                  placeholder="payload.title"
                />
                <p class="mt-1 text-xs text-base-content/55">
                  Canonical document path used for the readable flat item name. CourierCMS adds a stable collision suffix.
                </p>
              </div>
              <div class="sm:col-span-2">
                <.input
                  field={@form[:mapping]}
                  type="textarea"
                  rows="12"
                  label="Mapping (payload_path=source_path)"
                  class="textarea textarea-bordered w-full font-mono text-xs"
                />
              </div>
              <div class="sm:col-span-2">
                <.input
                  field={@form[:projections]}
                  type="textarea"
                  rows="5"
                  label="Target projections (field=canonical_path:type)"
                  class="textarea textarea-bordered w-full font-mono text-xs"
                />
                <p class="mt-1 text-xs text-base-content/55">
                  Optional query-friendly fields derived from the canonical document. The selected target Adapter validates support.
                </p>
              </div>
              <div class="sm:col-span-2">
                <.button
                  type="submit"
                  class="btn btn-primary w-full"
                  disabled={@source_connections == [] || @target_connections == []}
                >
                  Create Route
                </.button>
              </div>
            </.form>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
