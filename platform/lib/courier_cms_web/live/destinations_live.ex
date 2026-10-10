defmodule CourierCMSWeb.DestinationsLive do
  use CourierCMSWeb, :live_view
  on_mount {CourierCMSWeb.UserAuth, {:require_role, [:owner, :admin]}}

  alias CourierCMS.{Connections, Destinations}
  alias CourierCMS.Adapters.Definition
  alias CourierCMS.ExtensionSDK.AdapterError
  alias CourierCMS.Extensions.Gateway

  @impl true
  def mount(_params, _session, socket) do
    targets =
      socket.assigns.current_scope
      |> Connections.list_connections()
      |> Enum.filter(&Gateway.target_available?(&1.adapter_key))

    target = List.first(targets)

    {:ok,
     assign(socket,
       page_title: "Destinations",
       target_connections: targets,
       selected_target_id: target && target.id,
       target_definition: target && target_definition(target),
       destinations: Destinations.list_destinations(socket.assigns.current_scope),
       form: to_form(default_form(target), as: :destination)
     )}
  end

  @impl true
  def handle_event("validate", %{"destination" => params}, socket) do
    target_id = params["target_connection_id"]
    target = find_connection(socket.assigns.target_connections, target_id)

    params =
      if target_id != socket.assigns.selected_target_id do
        Map.put(
          params,
          "scope",
          Definition.default_destination_settings(target && target.adapter_key)
        )
      else
        params
      end

    {:noreply,
     assign(socket,
       selected_target_id: target_id,
       target_definition: target && target_definition(target),
       form: to_form(params, as: :destination)
     )}
  end

  def handle_event("save", %{"destination" => params}, socket) do
    case Destinations.create_destination(socket.assigns.current_scope, params) do
      {:ok, _destination} ->
        {:noreply,
         socket
         |> put_flash(:info, "Destination registered and validated.")
         |> reload()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, first_error(changeset))}

      {:error, %AdapterError{} = error} ->
        {:noreply, put_flash(socket, :error, error.message)}

      _error ->
        {:noreply, put_flash(socket, :error, "Destination could not be registered.")}
    end
  end

  def handle_event("revalidate", %{"id" => id}, socket) do
    destination = Destinations.get_destination!(socket.assigns.current_scope, id)

    case Destinations.revalidate(socket.assigns.current_scope, destination) do
      {:ok, %{validation_status: :valid}} ->
        {:noreply, socket |> put_flash(:info, "Destination is valid.") |> reload()}

      {:ok, %{validation_status: :invalid, last_validation_error: message}} ->
        {:noreply,
         socket
         |> put_flash(:error, message || "Destination validation failed.")
         |> reload()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, first_error(changeset))}

      _error ->
        {:noreply, socket |> put_flash(:error, "Destination validation failed.") |> reload()}
    end
  end

  defp reload(socket) do
    target = find_connection(socket.assigns.target_connections, socket.assigns.selected_target_id)

    assign(socket,
      destinations: Destinations.list_destinations(socket.assigns.current_scope),
      form: to_form(default_form(target), as: :destination)
    )
  end

  defp default_form(target) do
    %{
      "name" => "New Destination",
      "target_connection_id" => target && target.id,
      "scope" => Definition.default_destination_settings(target && target.adapter_key)
    }
  end

  defp target_definition(connection) do
    case Definition.target_definition(connection.adapter_key) do
      {:ok, definition} -> definition
      _error -> %{destination_fields: []}
    end
  end

  defp find_connection(connections, id), do: Enum.find(connections, &(&1.id == id))

  defp scope_value(form, field) do
    form.params
    |> Map.get("scope", %{})
    |> Definition.field_value(field)
  end

  defp first_error(changeset) do
    case changeset.errors do
      [{field, {message, _opts}} | _] -> "#{Phoenix.Naming.humanize(field)} #{message}."
      [] -> "Destination configuration is invalid."
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Destinations
        <:subtitle>
          Register and validate exclusive receiving scopes before assigning them to Routes.
        </:subtitle>
      </.header>

      <div class="grid gap-6 xl:grid-cols-[1fr_1fr]">
        <section class="card border border-base-300 bg-base-100 shadow-sm">
          <div class="card-body">
            <h2 class="card-title">Registered Destinations</h2>
            <p :if={@destinations == []} class="text-sm text-base-content/55">
              No Destinations registered yet.
            </p>
            <div :for={destination <- @destinations} class="rounded-xl border border-base-300 p-4">
              <div class="flex items-start justify-between gap-3">
                <div>
                  <p class="font-semibold">{destination.name}</p>
                  <p class="text-sm text-base-content/60">{destination.target_connection.name}</p>
                </div>
                <div class="flex gap-2">
                  <span class="badge badge-outline">{destination.lifecycle_status}</span>
                  <span class="badge badge-outline">{destination.validation_status}</span>
                </div>
              </div>
              <p class="mt-2 text-xs text-base-content/55">
                Owner: {if destination.owner_route,
                  do: destination.owner_route.name,
                  else: "Available"}
              </p>
              <pre class="mt-2 overflow-auto rounded-lg bg-neutral p-3 text-xs text-neutral-content">{Jason.encode!(destination.scope, pretty: true)}</pre>
              <button
                type="button"
                class="btn btn-ghost btn-sm mt-2"
                phx-click="revalidate"
                phx-value-id={destination.id}
              >Revalidate</button>
            </div>
          </div>
        </section>

        <section class="card border border-base-300 bg-base-100 shadow-sm">
          <div class="card-body">
            <h2 class="card-title">Register Destination</h2>
            <.form
              for={@form}
              id="destination-form"
              phx-change="validate"
              phx-submit="save"
              class="space-y-3"
            >
              <.input field={@form[:name]} label="Destination name" />
              <.input
                field={@form[:target_connection_id]}
                type="select"
                label="Target Connection"
                prompt="Choose target"
                options={Enum.map(@target_connections, &{&1.name, &1.id})}
              />
              <.adapter_field
                :for={field <- (@target_definition && @target_definition[:destination_fields]) || []}
                field={field}
                name={"destination[scope][#{field.key}]"}
                value={scope_value(@form, field)}
              />
              <p class="text-xs text-base-content/55">
                Create the receiving scope in the target first. CourierCMS validates it but does not mutate target schema during delivery.
              </p>
              <.button type="submit" class="btn btn-primary w-full">Register and validate</.button>
            </.form>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
