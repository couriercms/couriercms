defmodule CourierCMSWeb.ConnectionsLive do
  use CourierCMSWeb, :live_view
  on_mount {CourierCMSWeb.UserAuth, {:require_role, [:owner, :admin]}}

  alias CourierCMS.Connections
  alias CourierCMS.Adapters.Definition
  alias CourierCMS.ExtensionSDK.AdapterError
  alias CourierCMS.Extensions.Gateway

  @impl true
  def mount(_params, _session, socket) do
    definitions = Gateway.definitions()
    default_adapter_key = definitions |> List.first() |> then(&(&1 && &1.key))

    {:ok,
     assign(socket,
       page_title: "Connections",
       connections: Connections.list_connections(socket.assigns.current_scope),
       connector_setup: nil,
       adapter_definitions: definitions,
       selected_adapter_key: default_adapter_key,
       form: connection_form(default_adapter_key)
     )}
  end

  @impl true
  def handle_event("validate", %{"connection" => params}, socket) do
    adapter_key = params["adapter_key"]

    params =
      if adapter_key != socket.assigns.selected_adapter_key do
        defaults = Definition.default_connection_values(adapter_key)

        params
        |> Map.put("configuration", defaults["configuration"])
        |> Map.put("credential_values", defaults["credential_values"])
        |> Map.put("endpoint", defaults["endpoint"])
      else
        params
      end

    {:noreply,
     assign(socket,
       selected_adapter_key: adapter_key,
       form: to_form(params, as: :connection)
     )}
  end

  def handle_event("save", %{"connection" => params}, socket) do
    case Connections.create_connection(socket.assigns.current_scope, params) do
      {:ok, _connection} ->
        {:noreply,
         socket
         |> put_flash(:info, "Connection created.")
         |> assign(
           connections: Connections.list_connections(socket.assigns.current_scope),
           form: connection_form(socket.assigns.selected_adapter_key)
         )}

      {:error, %AdapterError{} = error} ->
        {:noreply, put_flash(socket, :error, error.message)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, first_error(changeset))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Connection could not be created.")}
    end
  end

  def handle_event("test", %{"id" => id}, socket) do
    connection = Connections.get_connection!(socket.assigns.current_scope, id)
    result = Connections.test_connection(socket.assigns.current_scope, connection)

    message =
      if result == :ok,
        do: {:info, "Connection test succeeded."},
        else: {:error, "Connection test failed safely."}

    {kind, text} = message

    {:noreply,
     socket
     |> put_flash(kind, text)
     |> assign(:connections, Connections.list_connections(socket.assigns.current_scope))}
  end

  def handle_event(
        "update-concurrency",
        %{
          "connection_id" => id,
          "max_concurrency" => max_concurrency,
          "requests_per_second" => requests_per_second
        },
        socket
      ) do
    connection = Connections.get_connection!(socket.assigns.current_scope, id)

    with {:ok, connection} <-
           Connections.update_concurrency_limit(
             socket.assigns.current_scope,
             connection,
             max_concurrency
           ),
         {:ok, _connection} <-
           Connections.update_request_rate_limit(
             socket.assigns.current_scope,
             connection,
             requests_per_second
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Connection delivery limits updated.")
       |> assign(:connections, Connections.list_connections(socket.assigns.current_scope))}
    else
      {:error, reason}
      when reason in [:invalid_concurrency_limit, :invalid_request_rate_limit] ->
        {:noreply,
         put_flash(socket, :error, "Concurrency must be 1–100 and requests/second 1–10,000.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Connection limits could not be updated.")}
    end
  end

  def handle_event("configure-connector", %{"id" => id}, socket) do
    connection = Connections.get_connection!(socket.assigns.current_scope, id)

    case Connections.configure_connector(
           socket.assigns.current_scope,
           connection
         ) do
      {:ok, updated, secret} ->
        {:ok, connector} = Connections.connector_definition(updated)

        setup = %{
          connection_name: updated.name,
          endpoint:
            CourierCMSWeb.Endpoint.url() <>
              Definition.connector_path(connector, updated.id),
          secret: secret
        }

        {:noreply,
         socket
         |> put_flash(:info, "Connector credentials generated.")
         |> assign(
           connector_setup: setup,
           connections: Connections.list_connections(socket.assigns.current_scope)
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Connector credentials could not be generated.")}
    end
  end

  def handle_event("rotate-credentials", %{"credentials" => params}, socket) do
    connection = Connections.get_connection!(socket.assigns.current_scope, params["id"])

    case Connections.rotate_credentials(socket.assigns.current_scope, connection, params) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Connection credentials rotated.")
         |> assign(:connections, Connections.list_connections(socket.assigns.current_scope))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Enter valid replacement credentials.")}
    end
  end

  defp connection_form(nil), do: to_form(%{}, as: :connection)

  defp connection_form(adapter_key) do
    defaults = Definition.default_connection_values(adapter_key)

    to_form(
      %{
        "name" => "",
        "adapter_key" => adapter_key,
        "endpoint" => defaults["endpoint"],
        "configuration" => defaults["configuration"],
        "credential_values" => defaults["credential_values"],
        "enabled" => "true"
      },
      as: :connection
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        Connections
        <:subtitle>
          Configured instances of one CMS Adapter. Credentials are encrypted before storage.
        </:subtitle>
      </.header>

      <section :if={@connector_setup} class="alert alert-warning mb-6 items-start">
        <.icon name="hero-key" class="mt-1" />
        <div class="min-w-0 flex-1">
          <p class="font-bold">{@connector_setup.connection_name} Connector setup</p>
          <p class="mt-1 text-sm">Copy these values now. The secret is not shown again.</p>
          <p class="mt-3 text-xs font-bold uppercase tracking-wide">Webhook URL</p>
          <code class="block break-all text-xs">{@connector_setup.endpoint}</code>
          <p class="mt-3 text-xs font-bold uppercase tracking-wide">Signing secret</p>
          <code id="connector-secret" class="block break-all text-xs">{@connector_setup.secret}</code>
        </div>
      </section>

      <div class="grid gap-6 lg:grid-cols-[1.2fr_0.8fr]">
        <section class="card border border-base-300 bg-base-100 shadow-sm">
          <div class="card-body">
            <h2 class="card-title">Configured connections</h2>
            <div
              :if={@connections == []}
              class="rounded-2xl border border-dashed border-base-300 p-8 text-center text-base-content/60"
            >
              No connections configured.
            </div>
            <div
              :for={connection <- @connections}
              id={"connection-#{connection.id}"}
              class="flex flex-col gap-3 rounded-2xl border border-base-300 p-5 sm:flex-row sm:items-center"
            >
              <div class="flex-1">
                <div class="flex items-center gap-2">
                  <p class="font-bold">{connection.name}</p>
                  <span class="badge badge-outline badge-sm">{adapter_label(connection.adapter_key)}</span>
                </div>
                <p class="mt-1 text-sm text-base-content/55">{connection.endpoint}</p>
                <p :if={connection.last_tested_at} class="mt-2 text-xs text-base-content/45">
                  Last tested {Calendar.strftime(connection.last_tested_at, "%b %d, %H:%M")}
                </p>
                <.form
                  for={%{}}
                  as={:limit}
                  phx-submit="update-concurrency"
                  class="mt-3 flex max-w-xs items-end gap-2"
                >
                  <input type="hidden" name="connection_id" value={connection.id} />
                  <label class="form-control flex-1">
                    <span class="label-text text-xs">Max concurrent operations</span>
                    <input
                      type="number"
                      name="max_concurrency"
                      min="1"
                      max="100"
                      value={concurrency_limit(connection)}
                      class="input input-bordered input-sm w-full"
                    />
                  </label>
                  <label class="form-control flex-1">
                    <span class="label-text text-xs">Requests / second</span>
                    <input
                      type="number"
                      name="requests_per_second"
                      min="1"
                      max="10000"
                      value={request_rate_limit(connection)}
                      class="input input-bordered input-sm w-full"
                    />
                  </label>
                  <button type="submit" class="btn btn-outline btn-sm">Apply</button>
                </.form>
                <.form
                  :if={credential_fields(connection) != []}
                  for={%{}}
                  as={:credentials}
                  phx-submit="rotate-credentials"
                  class="mt-3 grid max-w-xl items-end gap-2 sm:grid-cols-2"
                >
                  <input type="hidden" name="credentials[id]" value={connection.id} />
                  <.adapter_field
                    :for={field <- credential_fields(connection)}
                    field={field}
                    name={"credentials[#{field.key}]"}
                    value=""
                  />
                  <button type="submit" class="btn btn-outline btn-sm">Rotate credentials</button>
                </.form>
              </div>
              <span
                :if={connection.last_test_status}
                class={[
                  "badge",
                  connection.last_test_status == "succeeded" && "badge-success",
                  connection.last_test_status == "failed" && "badge-error"
                ]}
              >{connection.last_test_status}</span>
              <button phx-click="test" phx-value-id={connection.id} class="btn btn-outline btn-sm">Test</button>
              <button
                :if={connector_definition(connection)}
                phx-click="configure-connector"
                phx-value-id={connection.id}
                class="btn btn-outline btn-sm"
              >
                {if Connections.connector_configured?(connection),
                  do: connector_definition(connection).rotate_label,
                  else: connector_definition(connection).setup_label}
              </button>
            </div>
          </div>
        </section>

        <section class="card border border-base-300 bg-base-100 shadow-sm">
          <div class="card-body">
            <h2 class="card-title">Add connection</h2>
            <p class="text-sm text-base-content/60">
              Choose an Adapter. Its own definition supplies configuration, credentials, and help text.
            </p>
            <.form
              for={@form}
              id="connection-form"
              phx-change="validate"
              phx-submit="save"
              class="mt-3 space-y-3"
            >
              <.input field={@form[:name]} label="Name" placeholder="Corporate source" />
              <.input
                field={@form[:adapter_key]}
                type="select"
                label="Adapter"
                prompt="Choose an adapter"
                options={Enum.map(@adapter_definitions, &{&1.label, &1.key})}
              />
              <p
                :if={selected_definition(@selected_adapter_key)}
                class="sm:col-span-2 text-sm text-base-content/60"
              >
                {selected_definition(@selected_adapter_key).description}
              </p>
              <.input
                :if={endpoint_definition(@selected_adapter_key).mode == :input}
                field={@form[:endpoint]}
                type="url"
                label={Map.get(endpoint_definition(@selected_adapter_key), :label, "Endpoint")}
                placeholder={Map.get(endpoint_definition(@selected_adapter_key), :placeholder)}
              />
              <.adapter_field
                :for={field <- visible_connection_fields(@selected_adapter_key)}
                field={field}
                name={connection_field_name(field)}
                value={connection_form_value(@form, field)}
              />
              <input
                :for={field <- hidden_connection_fields(@selected_adapter_key)}
                type="hidden"
                name={connection_field_name(field)}
                value={connection_form_value(@form, field)}
              />
              <.input field={@form[:enabled]} type="checkbox" label="Enabled" />
              <.button type="submit" class="btn btn-primary w-full">Create connection</.button>
            </.form>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp concurrency_limit(connection) do
    connection.settings["max_concurrency"] ||
      Application.fetch_env!(:couriercms, :default_connection_concurrency)
  end

  defp request_rate_limit(connection) do
    connection.settings["requests_per_second"] ||
      Application.fetch_env!(:couriercms, :default_connection_requests_per_second)
  end

  defp selected_definition(nil), do: nil

  defp selected_definition(adapter_key) do
    case Gateway.fetch_definition(adapter_key) do
      {:ok, definition} -> definition
      :error -> nil
    end
  end

  defp adapter_label(adapter_key) do
    case selected_definition(adapter_key) do
      nil -> adapter_key
      definition -> definition.label
    end
  end

  defp endpoint_definition(adapter_key), do: Definition.endpoint_definition(adapter_key)

  defp visible_connection_fields(adapter_key),
    do: Enum.reject(Definition.connection_fields(adapter_key), &Map.get(&1, :hidden, false))

  defp hidden_connection_fields(adapter_key),
    do: Enum.filter(Definition.connection_fields(adapter_key), &Map.get(&1, :hidden, false))

  defp credential_fields(connection) do
    connection.adapter_key
    |> Definition.connection_fields()
    |> Enum.filter(&(&1.storage == :credential))
  end

  defp connector_definition(connection) do
    case Connections.connector_definition(connection) do
      {:ok, connector} -> connector
      :error -> nil
    end
  end

  defp connection_field_name(field) do
    namespace = if field.storage == :credential, do: "credential_values", else: "configuration"
    "connection[#{namespace}][#{field.key}]"
  end

  defp connection_form_value(form, field) do
    namespace = if field.storage == :credential, do: "credential_values", else: "configuration"
    values = Map.get(form.params || %{}, namespace, %{})
    Map.get(values, to_string(field.key), Map.get(field, :default, ""))
  end

  defp first_error(changeset) do
    case changeset.errors do
      [{field, {message, _opts}} | _] -> "#{Phoenix.Naming.humanize(field)} #{message}."
      [] -> "Connection could not be created."
    end
  end
end
