defmodule CourierCMSWeb.RouteLive do
  use CourierCMSWeb, :live_view

  @progress_refresh_interval 2_000

  alias CourierCMS.Accounts.Scope
  alias CourierCMS.Adapters.Definition
  alias CourierCMS.ExtensionSDK.AdapterError
  alias CourierCMS.{Destinations, Execution, Mapping, Processors, Routes, Transformations}
  alias CourierCMS.Processors.Definition, as: ProcessorDefinition
  alias CourierCMS.Transport.Projection

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket = socket |> assign(run_history_page: 1) |> load(id)

    if connected?(socket) do
      Execution.subscribe_route(id)
      schedule_progress_refresh()
    end

    {:ok, socket}
  end

  @impl true
  def handle_info({:route_runs_updated, route_id}, socket)
      when route_id == socket.assigns.route.id do
    {:noreply, assign_runs(socket)}
  end

  def handle_info(:refresh_active_runs, socket) do
    socket = assign_runs(socket)
    schedule_progress_refresh()
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate-selection", %{"selection" => params}, socket),
    do: {:noreply, assign(socket, :selection_form, to_form(params, as: :selection))}

  def handle_event("save-selection", %{"selection" => params}, socket) do
    result =
      with {:ok, selection} <-
             Definition.cast_selection(
               socket.assigns.route.source_connection.adapter_key,
               params
             ) do
        Routes.update_selection(socket.assigns.current_scope, socket.assigns.route, selection)
      end

    case result do
      {:ok, _route} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Source selection saved as a new Route Revision. The next incremental Run establishes a new full baseline."
         )
         |> load(socket.assigns.route.id)}

      {:error, %AdapterError{} = error} ->
        {:noreply, put_flash(socket, :error, error.message)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "The source selection could not be saved.")}
    end
  end

  def handle_event("validate-mapping", %{"mapping" => params}, socket),
    do: {:noreply, assign(socket, :mapping_form, to_form(params, as: :mapping))}

  def handle_event("preview-draft-selection", _params, socket) do
    with {:ok, selection} <-
           Definition.cast_selection(
             socket.assigns.route.source_connection.adapter_key,
             socket.assigns.selection_form.params
           ),
         {:ok, preview} <-
           Execution.preview_route(socket.assigns.current_scope, socket.assigns.route.id,
             selection: selection
           ) do
      {:noreply, assign(socket, :delivery_preview, preview)}
    else
      {:error, %AdapterError{} = error} ->
        {:noreply, put_flash(socket, :error, error.message)}

      {:error, :no_matching_content} ->
        {:noreply, put_flash(socket, :error, "No source item matches the draft selection.")}

      _error ->
        {:noreply, put_flash(socket, :error, "Draft selection preview could not be generated.")}
    end
  end

  def handle_event("save-mapping", %{"mapping" => params}, socket) do
    with {:ok, mapping} <- Mapping.parse(params["definitions"]),
         {:ok, _route} <-
           Routes.update_mapping(socket.assigns.current_scope, socket.assigns.route, mapping) do
      {:noreply,
       socket
       |> put_flash(
         :info,
         "Mapping saved as a new Route Revision and Delivery Contract version."
       )
       |> load(socket.assigns.route.id)}
    else
      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, first_error(changeset))}

      _error ->
        {:noreply, put_flash(socket, :error, "Mapping could not be saved.")}
    end
  end

  def handle_event("preview-draft-mapping", _params, socket) do
    params = socket.assigns.mapping_form.params

    with {:ok, mapping} <- Mapping.parse(params["definitions"]),
         {:ok, preview} <-
           Execution.preview_route(socket.assigns.current_scope, socket.assigns.route.id,
             mapping: mapping
           ) do
      {:noreply, assign(socket, :delivery_preview, preview)}
    else
      {:error, %AdapterError{} = error} ->
        {:noreply, put_flash(socket, :error, error.message)}

      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      _error ->
        {:noreply, put_flash(socket, :error, "Draft mapping preview could not be generated.")}
    end
  end

  def handle_event("validate-transformations", %{"transformations" => params}, socket),
    do: {:noreply, assign(socket, :transformations_form, to_form(params, as: :transformations))}

  def handle_event("save-transformations", %{"transformations" => params}, socket) do
    with {:ok, transformations} <- Transformations.parse(params["definitions"]),
         {:ok, _route} <-
           Routes.update_transformations(
             socket.assigns.current_scope,
             socket.assigns.route,
             transformations
           ) do
      {:noreply,
       socket
       |> put_flash(
         :info,
         "Transformations saved as a new Route Revision and Delivery Contract version."
       )
       |> load(socket.assigns.route.id)}
    else
      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, first_error(changeset))}

      _error ->
        {:noreply, put_flash(socket, :error, "Transformations could not be saved.")}
    end
  end

  def handle_event("preview-draft-transformations", _params, socket) do
    params = socket.assigns.transformations_form.params

    with {:ok, transformations} <- Transformations.parse(params["definitions"]),
         {:ok, preview} <-
           Execution.preview_route(socket.assigns.current_scope, socket.assigns.route.id,
             transformations: transformations
           ) do
      {:noreply, assign(socket, :delivery_preview, preview)}
    else
      {:error, %AdapterError{} = error} ->
        {:noreply, put_flash(socket, :error, error.message)}

      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      _error ->
        {:noreply,
         put_flash(socket, :error, "Draft transformation preview could not be generated.")}
    end
  end

  def handle_event("validate-processors", %{"processors" => params}, socket) do
    socket = assign(socket, :processors_form, to_form(params, as: :processors))

    case Processors.parse(params["definitions"]) do
      {:ok, processors} -> {:noreply, assign(socket, :draft_processors, processors)}
      _error -> {:noreply, socket}
    end
  end

  def handle_event("validate-processor-builder", params, socket) do
    builder_params = Map.get(params, "processor_builder", %{})
    config_params = Map.get(params, "processor_config", %{})
    reference = builder_params["reference"]

    definition = processor_definition(socket.assigns.processor_definitions, reference)

    config_params =
      if definition && reference != socket.assigns.selected_processor_reference,
        do: ProcessorDefinition.defaults(definition),
        else: config_params

    {:noreply,
     assign(socket,
       processor_builder_form: to_form(builder_params, as: :processor_builder),
       processor_config_form: to_form(config_params, as: :processor_config),
       selected_processor_definition: definition,
       selected_processor_reference: reference
     )}
  end

  def handle_event("add-draft-processor", params, socket) do
    builder_params = Map.get(params, "processor_builder", %{})
    config_params = Map.get(params, "processor_config", %{})

    with %{} = definition <-
           processor_definition(
             socket.assigns.processor_definitions,
             builder_params["reference"]
           ),
         {:ok, config} <- ProcessorDefinition.cast_config(definition, config_params),
         {:ok, current} <- Processors.parse(socket.assigns.processors_form.params["definitions"]),
         {:ok, [processor]} <-
           Processors.prepare([
             %{
               "extension_id" => definition.extension_id,
               "component_id" => definition.component_id,
               "input_path" => builder_params["input_path"],
               "output_path" => builder_params["output_path"],
               "config" => config
             }
           ]) do
      processors = put_draft_processor(current, processor, builder_params["edit_index"])

      {:noreply,
       socket
       |> assign(
         processors_form: processors_form(processors),
         draft_processors: processors,
         processor_builder_form:
           processor_builder_form(
             builder_params["reference"],
             builder_params["input_path"],
             builder_params["output_path"]
           )
       )
       |> put_flash(
         :info,
         "Processor draft updated. Preview it, then save to create a Route Revision."
       )}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Choose an installed Processor.")}

      {:error, %AdapterError{} = error} ->
        {:noreply, put_flash(socket, :error, error.message)}

      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      _error ->
        {:noreply, put_flash(socket, :error, "Processor could not be added to the draft.")}
    end
  end

  def handle_event("edit-draft-processor", %{"index" => index}, socket) do
    with {index, ""} <- Integer.parse(index),
         %{} = processor <- Enum.at(socket.assigns.draft_processors, index),
         reference <- "#{processor["extension_id"]}/#{processor["component_id"]}",
         %{} = definition <-
           processor_definition(socket.assigns.processor_definitions, reference) do
      builder =
        to_form(
          %{
            "reference" => reference,
            "input_path" => processor["input_path"],
            "output_path" => processor["output_path"],
            "edit_index" => to_string(index)
          },
          as: :processor_builder
        )

      {:noreply,
       assign(socket,
         processor_builder_form: builder,
         processor_config_form:
           to_form(ProcessorDefinition.form_values(definition, processor["config"]),
             as: :processor_config
           ),
         selected_processor_definition: definition,
         selected_processor_reference: reference
       )}
    else
      _error -> {:noreply, put_flash(socket, :error, "Draft Processor could not be edited.")}
    end
  end

  def handle_event("remove-draft-processor", %{"index" => index}, socket) do
    update_draft_processors(socket, index, fn processors, parsed_index ->
      List.delete_at(processors, parsed_index)
    end)
  end

  def handle_event(
        "move-draft-processor",
        %{"index" => index, "direction" => direction},
        socket
      ) do
    update_draft_processors(socket, index, fn processors, parsed_index ->
      target = if direction == "up", do: parsed_index - 1, else: parsed_index + 1
      swap_processors(processors, parsed_index, target)
    end)
  end

  def handle_event("save-processors", %{"processors" => params}, socket) do
    with {:ok, processors} <- Processors.parse(params["definitions"]),
         {:ok, _route} <-
           Routes.update_processors(
             socket.assigns.current_scope,
             socket.assigns.route,
             processors
           ) do
      {:noreply,
       socket
       |> put_flash(
         :info,
         "Processors saved as a new Route Revision and Delivery Contract version."
       )
       |> load(socket.assigns.route.id)}
    else
      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, first_error(changeset))}

      _error ->
        {:noreply, put_flash(socket, :error, "Processors could not be saved.")}
    end
  end

  def handle_event("preview-draft-processors", _params, socket) do
    params = socket.assigns.processors_form.params

    with {:ok, processors} <- Processors.parse(params["definitions"]),
         {:ok, preview} <-
           Execution.preview_route(socket.assigns.current_scope, socket.assigns.route.id,
             processors: processors
           ) do
      {:noreply, assign(socket, :delivery_preview, preview)}
    else
      {:error, %AdapterError{} = error} ->
        {:noreply, put_flash(socket, :error, error.message)}

      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      _error ->
        {:noreply, put_flash(socket, :error, "Draft Processor preview could not be generated.")}
    end
  end

  def handle_event("save-route", %{"route" => params}, socket) do
    attrs = %{name: params["name"], enabled: params["enabled"] == "true"}

    case Routes.update_route(socket.assigns.current_scope, socket.assigns.route, attrs) do
      {:ok, _route} ->
        {:noreply,
         socket
         |> put_flash(:info, "Route details updated.")
         |> load(socket.assigns.route.id)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, first_error(changeset))}

      _error ->
        {:noreply, put_flash(socket, :error, "Route details could not be updated.")}
    end
  end

  def handle_event("validate-delivery-name", %{"delivery_name" => params}, socket),
    do: {:noreply, assign(socket, :delivery_name_form, to_form(params, as: :delivery_name))}

  def handle_event("save-delivery-name", %{"delivery_name" => params}, socket) do
    with {:ok, _route} <-
           Routes.update_delivery_name_path(
             socket.assigns.current_scope,
             socket.assigns.route,
             params["path"] || ""
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Delivery Item naming saved as a new Route Revision.")
       |> load(socket.assigns.route.id)}
    else
      _error ->
        {:noreply, put_flash(socket, :error, "Delivery Item naming could not be saved.")}
    end
  end

  def handle_event("move-destination", %{"move_destination" => params}, socket) do
    case Routes.move_destination(
           socket.assigns.current_scope,
           socket.assigns.route,
           params["destination_id"]
         ) do
      {:ok, _route} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Destination moved. The old scope was preserved and the next execution will establish new bindings."
         )
         |> load(socket.assigns.route.id)}

      {:error, :route_has_active_run} ->
        {:noreply, put_flash(socket, :error, "Wait for the active Run to finish before moving.")}

      {:error, :destination_unavailable} ->
        {:noreply, put_flash(socket, :error, "The selected Destination is no longer available.")}

      _error ->
        {:noreply, put_flash(socket, :error, "Destination could not be moved.")}
    end
  end

  def handle_event("archive-route", _params, socket) do
    case Routes.archive_route(socket.assigns.current_scope, socket.assigns.route) do
      {:ok, _route} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Route archived. Its undelivered Destination was released; a used Destination was retired."
         )
         |> push_navigate(to: ~p"/routes")}

      {:error, :route_has_active_run} ->
        {:noreply,
         put_flash(socket, :error, "Wait for the active Run to finish before archiving.")}

      _error ->
        {:noreply, put_flash(socket, :error, "Route could not be archived.")}
    end
  end

  def handle_event("validate-schedule", %{"schedule" => params}, socket),
    do: {:noreply, assign(socket, :schedule_form, to_form(params, as: :schedule))}

  def handle_event("save-schedule", %{"schedule" => params}, socket) do
    enabled = params["enabled"] == "true"

    with {interval, ""} <- Integer.parse(params["interval_minutes"] || ""),
         {reconciliation_interval, ""} <-
           Integer.parse(params["reconciliation_interval_minutes"] || ""),
         {:ok, _route} <-
           Routes.update_schedule(
             socket.assigns.current_scope,
             socket.assigns.route,
             enabled,
             interval,
             params["polling_mode"],
             reconciliation_interval
           ) do
      {:noreply,
       socket
       |> put_flash(:info, "Periodic delivery schedule updated.")
       |> load(socket.assigns.route.id)}
    else
      _error ->
        {:noreply, put_flash(socket, :error, "Choose a supported delivery interval.")}
    end
  end

  def handle_event("validate-projections", %{"projections" => params}, socket),
    do: {:noreply, assign(socket, :projections_form, to_form(params, as: :projections))}

  def handle_event("save-projections", %{"projections" => params}, socket) do
    with {:ok, projections} <- Projection.parse(params["definitions"]),
         {:ok, _route} <-
           Routes.update_projections(
             socket.assigns.current_scope,
             socket.assigns.route,
             projections
           ) do
      {:noreply,
       socket
       |> put_flash(
         :info,
         "Projection configuration validated and saved as a new contract version."
       )
       |> load(socket.assigns.route.id)}
    else
      {:error, %AdapterError{} = error} ->
        {:noreply, put_flash(socket, :error, error.message)}

      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      _error ->
        {:noreply, put_flash(socket, :error, "Projection configuration could not be saved.")}
    end
  end

  def handle_event("preview-delivery", _params, socket) do
    case Execution.preview_route(socket.assigns.current_scope, socket.assigns.route.id) do
      {:ok, preview} ->
        {:noreply, assign(socket, :delivery_preview, preview)}

      {:error, %AdapterError{} = error} ->
        {:noreply, put_flash(socket, :error, error.message)}

      {:error, :no_matching_content} ->
        {:noreply, put_flash(socket, :error, "No source item currently matches this Route.")}

      _error ->
        {:noreply, put_flash(socket, :error, "Delivery preview could not be generated.")}
    end
  end

  @impl true
  def handle_event("run", _params, socket) do
    case Execution.start_manual_run(socket.assigns.current_scope, socket.assigns.route.id) do
      {:ok, run} ->
        {:noreply, push_navigate(socket, to: ~p"/runs/#{run.id}")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "The Route must be active before it can run.")}
    end
  end

  def handle_event("force-redelivery", _params, socket) do
    case Execution.start_manual_run(socket.assigns.current_scope, socket.assigns.route.id,
           force_redelivery: true
         ) do
      {:ok, run} ->
        {:noreply, push_navigate(socket, to: ~p"/runs/#{run.id}")}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, "The Route must be active before it can be redelivered.")}
    end
  end

  def handle_event("runs-page", %{"page" => page}, socket) do
    page =
      case Integer.parse(page) do
        {page, ""} when page > 0 -> page
        _other -> 1
      end

    {:noreply, socket |> assign(run_history_page: page) |> assign_runs()}
  end

  defp load(socket, id) do
    scope = socket.assigns.current_scope
    route = Routes.get_route!(scope, id)
    processor_definitions = Processors.definitions()
    selected_processor_definition = List.first(processor_definitions)
    selected_processor_reference = processor_reference(selected_processor_definition)

    assign(socket,
      page_title: route.name,
      route: route,
      can_run?: is_nil(route.archived_at) && Scope.role?(scope, [:owner, :admin, :operator]),
      can_edit?: is_nil(route.archived_at) && Scope.role?(scope, [:owner, :admin]),
      source_definition: source_definition(route.source_connection.adapter_key),
      target_definition: target_definition(route.target_connection.adapter_key),
      route_form: route_form(route),
      selection_form: selection_form(route.current_revision.selection),
      mapping_form: mapping_form(route.current_revision.mapping),
      transformations_form: transformations_form(route.current_revision.transformations),
      processors_form: processors_form(route.current_revision.processors),
      draft_processors: route.current_revision.processors,
      processor_definitions: processor_definitions,
      processor_builder_form:
        processor_builder_form(selected_processor_reference, "payload.body", "payload.body"),
      processor_config_form: processor_config_form(selected_processor_definition),
      selected_processor_definition: selected_processor_definition,
      selected_processor_reference: selected_processor_reference,
      schedule_form: schedule_form(route.current_revision.trigger_settings),
      projections_form: projections_form(route.current_revision.projections),
      delivery_name_form:
        to_form(%{"path" => route.current_revision.delivery_name_path}, as: :delivery_name),
      move_destination_form: to_form(%{"destination_id" => ""}, as: :move_destination),
      available_destinations: Destinations.list_available(scope, route.target_connection_id),
      delivery_preview: nil,
      next_scheduled_at: Execution.next_scheduled_at(route)
    )
    |> assign_runs()
  end

  defp assign_runs(socket) do
    result =
      Execution.list_route_runs(socket.assigns.current_scope, socket.assigns.route.id,
        page: socket.assigns.run_history_page,
        page_size: 20
      )

    assign(socket, runs: result.items, runs_page: result, run_history_page: result.page)
  end

  defp schedule_progress_refresh,
    do: Process.send_after(self(), :refresh_active_runs, @progress_refresh_interval)

  defp selection_form(selection) do
    to_form(selection, as: :selection)
  end

  defp mapping_form(mapping),
    do: to_form(%{"definitions" => Mapping.format(mapping)}, as: :mapping)

  defp transformations_form(transformations),
    do:
      to_form(%{"definitions" => Transformations.format(transformations)},
        as: :transformations
      )

  defp processors_form(processors),
    do: to_form(%{"definitions" => Processors.format(processors)}, as: :processors)

  defp processor_builder_form(reference, input_path, output_path) do
    to_form(
      %{
        "reference" => reference,
        "input_path" => input_path,
        "output_path" => output_path,
        "edit_index" => ""
      },
      as: :processor_builder
    )
  end

  defp processor_config_form(nil), do: to_form(%{}, as: :processor_config)

  defp processor_config_form(definition),
    do: to_form(ProcessorDefinition.defaults(definition), as: :processor_config)

  defp processor_reference(nil), do: nil

  defp processor_reference(definition),
    do: "#{definition.extension_id}/#{definition.component_id}"

  defp processor_definition(definitions, reference) do
    Enum.find(definitions, &(processor_reference(&1) == reference))
  end

  defp processor_options(definitions) do
    Enum.map(definitions, fn definition ->
      {"#{definition.label} — #{definition.extension_id}/#{definition.component_id}",
       processor_reference(definition)}
    end)
  end

  defp processor_input_type(%{type: :checkbox}), do: "checkbox"
  defp processor_input_type(%{type: :integer}), do: "number"
  defp processor_input_type(%{type: :json_object}), do: "textarea"
  defp processor_input_type(_field), do: "text"

  defp put_draft_processor(processors, processor, index) do
    case Integer.parse(to_string(index || "")) do
      {index, ""} when index >= 0 and index < length(processors) ->
        List.replace_at(processors, index, processor)

      _other ->
        processors ++ [processor]
    end
  end

  defp update_draft_processors(socket, index, update) do
    with {index, ""} <- Integer.parse(index),
         true <- index >= 0 and index < length(socket.assigns.draft_processors) do
      processors = update.(socket.assigns.draft_processors, index)

      {:noreply,
       assign(socket,
         draft_processors: processors,
         processors_form: processors_form(processors)
       )}
    else
      _error -> {:noreply, put_flash(socket, :error, "Draft Processor could not be changed.")}
    end
  end

  defp swap_processors(processors, from, to)
       when to >= 0 and to < length(processors) do
    left = Enum.at(processors, from)
    right = Enum.at(processors, to)

    processors
    |> List.replace_at(from, right)
    |> List.replace_at(to, left)
  end

  defp swap_processors(processors, _from, _to), do: processors

  defp route_form(route),
    do: to_form(%{"name" => route.name, "enabled" => to_string(route.enabled)}, as: :route)

  defp source_definition(adapter_key) do
    case Definition.source_definition(adapter_key) do
      {:ok, definition} -> definition
      _error -> %{content_label: "content items", description: "", selection_fields: []}
    end
  end

  defp target_definition(adapter_key) do
    case Definition.target_definition(adapter_key) do
      {:ok, definition} -> definition
      _error -> %{destination_fields: []}
    end
  end

  defp selection_value(selection, field),
    do: Definition.field_value(selection, field)

  defp filter_value(value) when value in [nil, "", []], do: "Any"
  defp filter_value(value) when is_list(value), do: Enum.join(value, ", ")
  defp filter_value(value), do: value

  defp first_error(changeset) do
    case changeset.errors do
      [{field, {message, _opts}} | _] -> "#{Phoenix.Naming.humanize(field)} #{message}."
      [] -> "Configuration could not be saved."
    end
  end

  defp schedule_form(trigger_settings) do
    schedule = trigger_settings["schedule"] || %{}

    to_form(
      %{
        "enabled" => to_string(schedule["enabled"] == true),
        "interval_minutes" => to_string(schedule["interval_minutes"] || 15),
        "polling_mode" => schedule["polling_mode"] || "incremental",
        "reconciliation_interval_minutes" =>
          to_string(schedule["reconciliation_interval_minutes"] || 1_440)
      },
      as: :schedule
    )
  end

  defp projections_form(projections) do
    to_form(%{"definitions" => Projection.format(projections)}, as: :projections)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <.header>
          {@route.name}
          <:subtitle>{@route.source_connection.name} → {@route.target_connection.name}</:subtitle>
        </.header>
        <div class="flex flex-wrap gap-2">
          <button
            id="run-route"
            phx-click="run"
            class="btn btn-primary"
            disabled={!@route.enabled || !@can_run?}
          ><.icon name="hero-play-solid" /> Run full scan</button>
          <button
            id="force-redelivery"
            phx-click="force-redelivery"
            data-confirm="Redeliver every matching item? Unchanged items will be written to the target again."
            class="btn btn-outline"
            disabled={!@route.enabled || !@can_run?}
          ><.icon name="hero-arrow-path" /> Force full redelivery</button>
        </div>
      </div>

      <div class="grid gap-6 lg:grid-cols-3">
        <section class="card border border-base-300 bg-base-100 shadow-sm lg:col-span-2">
          <div class="card-body">
            <h2 class="card-title">Source selection</h2>
            <div class="alert mb-4 border-primary/20 bg-primary/5 text-sm">
              <.icon name="hero-rectangle-stack" />
              <span>
                Collection Route: every matching {@source_definition.content_label} item is delivered independently. Future matches are included automatically.
              </span>
            </div>
            <div class="grid gap-3 sm:grid-cols-4">
              <.fact
                :for={field <- @source_definition.selection_fields}
                label={field.label}
                value={filter_value(@route.current_revision.selection[to_string(field.key)])}
              />
            </div>
            <details
              :if={@can_edit?}
              class="collapse-arrow collapse mt-4 border border-base-300 bg-base-100"
            >
              <summary class="collapse-title font-semibold">Edit collection filters</summary>
              <div class="collapse-content">
                <.form
                  for={@selection_form}
                  id="selection-form"
                  phx-change="validate-selection"
                  phx-submit="save-selection"
                  class="grid gap-3 sm:grid-cols-3"
                >
                  <.adapter_field
                    :for={field <- @source_definition.selection_fields}
                    field={field}
                    name={"selection[#{field.key}]"}
                    value={selection_value(@selection_form.params, field)}
                  />
                  <div class="sm:col-span-3 flex justify-end gap-2">
                    <button type="button" phx-click="preview-draft-selection" class="btn btn-outline">
                      Preview draft
                    </button>
                    <.button type="submit" class="btn btn-primary">Save selection</.button>
                  </div>
                </.form>
              </div>
            </details>
            <div class="divider"></div>
            <h3 class="font-bold">Payload mapping</h3>
            <div class="grid gap-2 sm:grid-cols-2">
              <div
                :for={{target, source} <- Enum.sort(@route.current_revision.mapping)}
                class="flex items-center gap-2 rounded-xl bg-base-200 px-3 py-2 text-xs"
              >
                <code class="font-semibold text-primary">{source}</code><span class="text-base-content/35">→</span><code>{target}</code>
              </div>
            </div>
            <details
              :if={@can_edit?}
              class="collapse-arrow collapse mt-4 border border-base-300 bg-base-100"
            >
              <summary class="collapse-title font-semibold">Edit payload mapping</summary>
              <div class="collapse-content">
                <.form
                  for={@mapping_form}
                  id="mapping-form"
                  phx-change="validate-mapping"
                  phx-submit="save-mapping"
                >
                  <.input
                    field={@mapping_form[:definitions]}
                    type="textarea"
                    rows="12"
                    label="One mapping per line (payload_path=source_path)"
                    class="textarea textarea-bordered w-full font-mono text-xs"
                  />
                  <p class="mt-2 text-xs text-base-content/55">
                    Saving creates an immutable Route Revision, increments the Delivery Contract version, and preserves previous Runs.
                  </p>
                  <div class="mt-3 flex justify-end gap-2">
                    <button
                      type="button"
                      phx-click="preview-draft-mapping"
                      class="btn btn-outline"
                    >Preview draft</button>
                    <.button type="submit" class="btn btn-primary">Validate and save</.button>
                  </div>
                </.form>
              </div>
            </details>
            <div class="divider"></div>
            <h3 class="font-bold">Portable transformations</h3>
            <div class="grid gap-2 sm:grid-cols-2">
              <div
                :for={transformation <- @route.current_revision.transformations}
                class="rounded-xl bg-base-200 px-3 py-2 text-xs"
              >
                <code class="font-semibold text-primary">{transformation["input_path"]}</code>
                <span class="mx-2 text-base-content/35">|</span>
                <code>{transformation["operation"]}</code>
                <p class="mt-1 text-base-content/45">
                  writes <code>{transformation["output_path"]}</code> · v{transformation["version"]}
                </p>
              </div>
              <p
                :if={@route.current_revision.transformations == []}
                class="text-sm text-base-content/55"
              >
                No transformations configured. The mapped payload is delivered unchanged.
              </p>
            </div>
            <details
              :if={@can_edit?}
              class="collapse-arrow collapse mt-4 border border-base-300 bg-base-100"
            >
              <summary class="collapse-title font-semibold">Edit portable transformations</summary>
              <div class="collapse-content">
                <.form
                  for={@transformations_form}
                  id="transformations-form"
                  phx-change="validate-transformations"
                  phx-submit="save-transformations"
                >
                  <.input
                    field={@transformations_form[:definitions]}
                    type="textarea"
                    rows="6"
                    label="One ordered transformation per line"
                    placeholder="title=title|string.trim\nslug=title|string.slug"
                    class="textarea textarea-bordered w-full font-mono text-xs"
                  />
                  <p class="mt-2 text-xs text-base-content/55">
                    Format: output_path=input_path|operation. Available: {Enum.join(
                      Transformations.operations(),
                      ", "
                    )}. Saving creates a new immutable contract version.
                  </p>
                  <div class="mt-3 flex justify-end gap-2">
                    <button
                      type="button"
                      phx-click="preview-draft-transformations"
                      class="btn btn-outline"
                    >Preview draft</button>
                    <.button type="submit" class="btn btn-primary">Validate and save</.button>
                  </div>
                </.form>
              </div>
            </details>
            <div class="divider"></div>
            <h3 class="font-bold">Extension Processors</h3>
            <p class="text-sm text-base-content/55">
              Ordered, target-independent processing supplied by trusted installed Extensions.
            </p>
            <div class="mt-3 grid gap-2 sm:grid-cols-2">
              <div
                :for={processor <- @route.current_revision.processors}
                class="rounded-xl bg-base-200 px-3 py-2 text-xs"
              >
                <code class="font-semibold text-primary">{processor["input_path"]}</code>
                <span class="mx-2 text-base-content/35">to</span>
                <code>{processor["output_path"]}</code>
                <p class="mt-1 break-all text-base-content/45">
                  {processor["extension_id"]}/{processor["component_id"]} v{processor[
                    "component_version"
                  ]}
                </p>
              </div>
              <p
                :if={@route.current_revision.processors == []}
                class="text-sm text-base-content/55"
              >
                No Extension Processors configured.
              </p>
            </div>
            <details
              :if={@can_edit?}
              class="collapse-arrow collapse mt-4 border border-base-300 bg-base-100"
            >
              <summary class="collapse-title font-semibold">Edit Extension Processors</summary>
              <div class="collapse-content">
                <.form
                  :if={@selected_processor_definition}
                  for={@processor_builder_form}
                  id="processor-builder-form"
                  phx-change="validate-processor-builder"
                  phx-submit="add-draft-processor"
                  class="mb-5 rounded-xl border border-base-300 bg-base-200/40 p-4"
                >
                  <.input field={@processor_builder_form[:edit_index]} type="hidden" />
                  <h4 class="font-semibold">Add a Processor to the draft</h4>
                  <p class="mt-1 text-xs text-base-content/55">
                    Configuration fields are declared and validated by the installed Extension.
                  </p>
                  <div class="mt-3 grid gap-3 lg:grid-cols-3">
                    <.input
                      field={@processor_builder_form[:reference]}
                      type="select"
                      label="Processor"
                      options={processor_options(@processor_definitions)}
                    />
                    <.input
                      field={@processor_builder_form[:input_path]}
                      label="Input payload path"
                      placeholder="body.value"
                    />
                    <.input
                      field={@processor_builder_form[:output_path]}
                      label="Output payload path"
                      placeholder="body.value"
                    />
                  </div>
                  <div class="mt-3 rounded-lg border border-base-300 bg-base-100 p-3">
                    <p class="text-sm font-semibold">{@selected_processor_definition.label}</p>
                    <p class="mt-1 text-xs text-base-content/55">
                      {@selected_processor_definition.description}
                    </p>
                    <div
                      :if={ProcessorDefinition.fields(@selected_processor_definition) != []}
                      class="mt-3 grid gap-3 md:grid-cols-2"
                    >
                      <div
                        :for={field <- ProcessorDefinition.fields(@selected_processor_definition)}
                        class={field.type == :json_object && "md:col-span-2"}
                      >
                        <.input
                          field={@processor_config_form[field.key]}
                          type={processor_input_type(field)}
                          label={field.label}
                          rows={field.type == :json_object && "5"}
                          class={field.type == :json_object && "font-mono text-xs"}
                        />
                        <p :if={field[:description]} class="mt-1 text-xs text-base-content/50">
                          {field.description}
                        </p>
                      </div>
                    </div>
                    <p
                      :if={ProcessorDefinition.fields(@selected_processor_definition) == []}
                      class="mt-3 text-xs text-base-content/50"
                    >
                      This Processor has no configuration fields.
                    </p>
                  </div>
                  <div class="mt-3 flex justify-end">
                    <.button type="submit" class="btn btn-secondary">Add to draft</.button>
                  </div>
                </.form>
                <div id="processor-draft-steps" class="mb-5 space-y-2">
                  <div class="flex items-center justify-between">
                    <h4 class="font-semibold">Ordered draft</h4>
                    <span class="badge badge-outline">{length(@draft_processors)} steps</span>
                  </div>
                  <p :if={@draft_processors == []} class="text-sm text-base-content/55">
                    No Processors in this draft.
                  </p>
                  <div
                    :for={{processor, index} <- Enum.with_index(@draft_processors)}
                    id={"draft-processor-#{index}"}
                    class="flex flex-col gap-2 rounded-xl border border-base-300 bg-base-100 p-3 sm:flex-row sm:items-center sm:justify-between"
                  >
                    <div class="min-w-0 text-xs">
                      <p class="font-semibold">
                        {index + 1}. {processor["extension_id"]}/{processor["component_id"]}
                      </p>
                      <p class="mt-1 break-all text-base-content/50">
                        {processor["input_path"]} → {processor["output_path"]}
                      </p>
                    </div>
                    <div class="flex shrink-0 gap-1">
                      <button
                        type="button"
                        class="btn btn-ghost btn-xs"
                        phx-click="move-draft-processor"
                        phx-value-index={index}
                        phx-value-direction="up"
                        disabled={index == 0}
                      >Up</button>
                      <button
                        type="button"
                        class="btn btn-ghost btn-xs"
                        phx-click="move-draft-processor"
                        phx-value-index={index}
                        phx-value-direction="down"
                        disabled={index == length(@draft_processors) - 1}
                      >Down</button>
                      <button
                        type="button"
                        class="btn btn-ghost btn-xs"
                        phx-click="edit-draft-processor"
                        phx-value-index={index}
                      >Edit</button>
                      <button
                        type="button"
                        class="btn btn-ghost btn-xs text-error"
                        phx-click="remove-draft-processor"
                        phx-value-index={index}
                      >Remove</button>
                    </div>
                  </div>
                </div>
                <.form
                  for={@processors_form}
                  id="processors-form"
                  phx-change="validate-processors"
                  phx-submit="save-processors"
                >
                  <.input
                    field={@processors_form[:definitions]}
                    type="textarea"
                    rows="6"
                    label="Ordered draft definition"
                    placeholder={"title=title|com.example.content/title_cleanup|{\"mode\":\"portable\"}"}
                    class="textarea textarea-bordered w-full font-mono text-xs"
                  />
                  <p class="mt-2 text-xs font-semibold">Advanced representation</p>
                  <p class="mt-2 text-xs text-base-content/55">
                    The guided editor appends validated entries here. Advanced users may edit the format directly: output=input|extension/component|JSON.
                  </p>
                  <div :if={@processor_definitions != []} class="mt-2 text-xs text-base-content/55">
                    Installed: {Enum.map_join(@processor_definitions, ", ", fn definition ->
                      "#{definition.extension_id}/#{definition.component_id}"
                    end)}
                  </div>
                  <div class="mt-3 flex justify-end gap-2">
                    <button
                      type="button"
                      phx-click="preview-draft-processors"
                      class="btn btn-outline"
                    >Preview draft (no target write)</button>
                    <.button type="submit" class="btn btn-primary">Validate and save</.button>
                  </div>
                </.form>
              </div>
            </details>
          </div>
        </section>
        <section class="card border border-base-300 bg-base-100 shadow-sm">
          <div class="card-body">
            <h2 class="card-title">Ownership</h2>
            <p class="text-sm text-base-content/60">
              This Route exclusively owns its current Destination.
            </p>
            <div class="mt-3 rounded-xl bg-neutral p-4 text-neutral-content">
              <p class="font-semibold">{@route.current_destination.name}</p>
              <p class="mt-1 break-all font-mono text-xs">{@route.current_destination.id}</p>
            </div>
            <div class="mt-3 flex items-center justify-between">
              <span class="text-sm">Destination lifecycle</span><span class="badge badge-outline">{@route.current_destination.lifecycle_status}</span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-sm">Validation</span><span class="badge badge-outline">{@route.current_destination.validation_status}</span>
            </div>
            <div class="mt-3 flex items-center justify-between">
              <span class="text-sm">Revision</span><span class="badge badge-outline">{@route.current_revision.revision_number}</span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-sm">Contract</span><span class="badge badge-outline">v{@route.current_revision.contract_version}</span>
            </div>
            <div class="mt-4 border-t border-base-300 pt-4">
              <p class="text-sm font-semibold">Delivery Item naming</p>
              <.form
                :if={@can_edit?}
                for={@delivery_name_form}
                id="delivery-name-form"
                phx-change="validate-delivery-name"
                phx-submit="save-delivery-name"
                class="mt-3 space-y-3"
              >
                <.input
                  field={@delivery_name_form[:path]}
                  label="Canonical document path"
                  placeholder="payload.title"
                />
                <p class="text-xs text-base-content/55">
                  The target Adapter sanitizes this value and appends a stable short identity suffix.
                </p>
                <.button type="submit" class="btn btn-primary w-full">Save naming</.button>
              </.form>
            </div>
            <details
              :if={@can_edit? && @available_destinations != []}
              class="collapse-arrow collapse mt-4 border border-warning/40"
            >
              <summary class="collapse-title font-semibold">Move Destination</summary>
              <div class="collapse-content">
                <.form
                  for={@move_destination_form}
                  id="move-destination-form"
                  phx-submit="move-destination"
                  class="space-y-3"
                >
                  <.input
                    field={@move_destination_form[:destination_id]}
                    type="select"
                    label="New Destination"
                    prompt="Choose available Destination"
                    options={Enum.map(@available_destinations, &{&1.name, &1.id})}
                  />
                  <p class="text-xs text-base-content/55">
                    Existing target content is not deleted. An active old Destination is retired, historical bindings remain, and the new Destination requires a full delivery.
                  </p>
                  <.button type="submit" class="btn btn-warning w-full">Move Destination</.button>
                </.form>
              </div>
            </details>
            <details :if={@can_edit?} class="collapse-arrow collapse mt-4 border border-base-300">
              <summary class="collapse-title font-semibold">Edit Route details</summary>
              <div class="collapse-content">
                <.form
                  for={@route_form}
                  id="route-details-form"
                  phx-submit="save-route"
                  class="space-y-3"
                >
                  <.input field={@route_form[:name]} label="Route name" />
                  <.input field={@route_form[:enabled]} type="checkbox" label="Active" />
                  <p class="text-xs text-base-content/55">
                    Deactivating prevents new manual, scheduled, and event-triggered Runs. Existing history is preserved.
                  </p>
                  <.button type="submit" class="btn btn-primary w-full">Save Route details</.button>
                </.form>
              </div>
            </details>
            <.button
              :if={@can_edit? && is_nil(@route.archived_at)}
              id="archive-route"
              type="button"
              phx-click="archive-route"
              data-confirm="Archive this Route? CourierCMS will not delete target content."
              class="btn btn-outline btn-error mt-4 w-full"
            >
              Archive Route
            </.button>
          </div>
        </section>
      </div>

      <section class="card border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body">
          <div class="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <h2 class="card-title">Canonical intake and projections</h2>
              <p class="mt-1 text-sm text-base-content/60">
                Every item retains the complete canonical JSON. Projections are typed target fields derived from it for efficient queries and hooks.
              </p>
            </div>
            <span class="badge badge-outline">Contract v{@route.current_revision.contract_version}</span>
          </div>
          <div class="mt-4 grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            <div
              :for={projection <- @route.current_revision.projections}
              class="rounded-xl border border-base-300 bg-base-200 p-3 text-xs"
            >
              <code class="font-semibold text-primary">{projection["source_path"]}</code>
              <p class="my-1 text-base-content/35">→</p>
              <code>{projection["target_field"]}</code>
              <span class="badge badge-ghost badge-xs ml-2">{projection["type"]}</span>
            </div>
            <p :if={@route.current_revision.projections == []} class="text-sm text-base-content/55">
              No projections configured. The canonical document is still delivered in full.
            </p>
          </div>
          <details
            :if={@can_edit?}
            class="collapse-arrow collapse mt-4 border border-base-300 bg-base-100"
          >
            <summary class="collapse-title font-semibold">Configure projection fields</summary>
            <div class="collapse-content">
              <.form
                for={@projections_form}
                id="projections-form"
                phx-change="validate-projections"
                phx-submit="save-projections"
              >
                <.input
                  field={@projections_form[:definitions]}
                  type="textarea"
                  rows="6"
                  label="One projection per line"
                  class="textarea textarea-bordered w-full font-mono text-xs"
                />
                <p class="mt-2 text-xs text-base-content/55">
                  Format: targetField=payload.path:type. Add :required to reject items with no value. Saving validates the target Intake Schema and creates a new Route Revision.
                </p>
                <div class="mt-3 flex justify-end">
                  <.button type="submit" class="btn btn-primary">Validate and save</.button>
                </div>
              </.form>
            </div>
          </details>
          <div class="mt-4 flex justify-end">
            <button
              :if={@can_edit?}
              id="preview-delivery"
              type="button"
              phx-click="preview-delivery"
              class="btn btn-outline btn-sm"
            >Preview first matching item</button>
          </div>
          <div :if={@delivery_preview} id="delivery-preview" class="mt-4 grid gap-4 lg:grid-cols-2">
            <div class="lg:col-span-2">
              <h3 class="mb-2 text-xs font-bold uppercase tracking-widest text-base-content/45">
                Content Bundle
              </h3>
              <div id="content-bundle-summary" class="grid gap-2 sm:grid-cols-2 lg:grid-cols-5">
                <.bundle_metric
                  label="Root"
                  value={@delivery_preview.content_bundle.root_source_item_id}
                />
                <.bundle_metric
                  label="Included content"
                  value={@delivery_preview.content_bundle.included_content_count}
                />
                <.bundle_metric
                  label="Relationships"
                  value={@delivery_preview.content_bundle.relationship_count}
                />
                <.bundle_metric
                  label="Delivery Assets"
                  value={@delivery_preview.content_bundle.asset_count}
                />
                <.bundle_metric
                  label="Declared asset bytes"
                  value={bundle_bytes(@delivery_preview.content_bundle)}
                />
              </div>
            </div>
            <div>
              <h3 class="mb-2 text-xs font-bold uppercase tracking-widest text-base-content/45">
                Canonical delivery document
              </h3>
              <pre class="max-h-96 overflow-auto rounded-xl bg-neutral p-4 text-xs text-neutral-content">{json(@delivery_preview.canonical_document)}</pre>
            </div>
            <div>
              <h3 class="mb-2 text-xs font-bold uppercase tracking-widest text-base-content/45">
                Resolved projections
              </h3>
              <pre class="max-h-96 overflow-auto rounded-xl bg-neutral p-4 text-xs text-neutral-content">{json(@delivery_preview.projections)}</pre>
            </div>
          </div>
        </div>
      </section>

      <section class="card border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body">
          <div class="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <h2 class="card-title">Periodic delivery</h2>
              <p class="mt-1 text-sm text-base-content/60">
                Incremental polling retrieves recently modified content when supported. The first Run, configured reconciliations, and any fallback use a full scan.
              </p>
            </div>
            <span :if={@next_scheduled_at} class="badge badge-outline">
              Next check {Calendar.strftime(@next_scheduled_at, "%Y-%m-%d %H:%M UTC")}
            </span>
          </div>
          <.form
            for={@schedule_form}
            id="schedule-form"
            phx-change="validate-schedule"
            phx-submit="save-schedule"
            class="mt-4 grid items-end gap-3 md:grid-cols-2 xl:grid-cols-[auto_1fr_1fr_1fr_auto]"
          >
            <.input
              field={@schedule_form[:enabled]}
              type="checkbox"
              label="Enable periodic delivery"
              disabled={!@can_edit?}
            />
            <.input
              field={@schedule_form[:interval_minutes]}
              type="select"
              label="Run interval"
              options={[
                {"Every 5 minutes", "5"},
                {"Every 15 minutes", "15"},
                {"Every 30 minutes", "30"},
                {"Hourly", "60"},
                {"Every 6 hours", "360"},
                {"Daily", "1440"}
              ]}
              disabled={!@can_edit?}
            />
            <.input
              field={@schedule_form[:polling_mode]}
              type="select"
              label="Polling strategy"
              options={[
                {"Incremental with full fallback", "incremental"},
                {"Full scan every run", "full"}
              ]}
              disabled={!@can_edit?}
            />
            <.input
              field={@schedule_form[:reconciliation_interval_minutes]}
              type="select"
              label="Full reconciliation"
              options={[
                {"Daily", "1440"},
                {"Weekly", "10080"},
                {"Every 30 days", "43200"}
              ]}
              disabled={!@can_edit?}
            />
            <.button type="submit" class="btn btn-primary" disabled={!@can_edit?}>
              Save schedule
            </.button>
          </.form>
        </div>
      </section>

      <section class="card border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body">
          <div class="flex items-center justify-between">
            <div>
              <h2 class="card-title">Run history</h2>
              <p class="text-sm text-base-content/55">Updates live while this page is open.</p>
            </div>
            <span class="flex items-center gap-2 text-xs text-base-content/50">
              <span class="status status-success animate-pulse"></span> Live
            </span>
          </div>
          <p :if={@runs == []} class="text-sm text-base-content/60">No Runs yet.</p>
          <div :if={@runs != []} id="route-run-history" class="overflow-x-auto">
            <table class="table mt-3">
              <thead>
                <tr>
                  <th>Run</th>
                  <th>Progress</th>
                  <th>Delivered</th>
                  <th>Unchanged</th>
                  <th>Failed</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={run <- @runs} id={"route-run-#{run.id}"}>
                  <td>
                    <.link
                      navigate={~p"/runs/#{run.id}"}
                      class="font-semibold capitalize hover:text-primary"
                    >
                      {run.trigger_kind} Run
                    </.link>
                    <span
                      :if={run.trigger_metadata["delivery_mode"] == "force"}
                      class="badge badge-warning badge-xs ml-1"
                    >
                      forced
                    </span>
                    <span
                      :if={run.trigger_kind == :schedule && run.trigger_metadata["retrieval_mode"]}
                      class="badge badge-outline badge-xs ml-1"
                    >
                      {run.trigger_metadata["retrieval_mode"]}
                    </span>
                    <p class="whitespace-nowrap text-xs text-base-content/50">
                      {Calendar.strftime(run.inserted_at, "%Y-%m-%d %H:%M:%S")}
                    </p>
                  </td>
                  <td class="min-w-36">
                    <div class="flex items-center gap-2">
                      <progress
                        class="progress progress-primary w-20"
                        value={run_progress(run)}
                        max="100"
                      ></progress>
                      <span class="text-xs">{run_progress(run)}%</span>
                    </div>
                    <p class="mt-1 text-xs text-base-content/45">
                      {terminal_count(run)} / {run.items_discovered} items
                    </p>
                  </td>
                  <td class="text-success">{run.items_succeeded}</td>
                  <td>{run.items_skipped}</td>
                  <td class={run.items_failed > 0 && "text-error"}>{run.items_failed}</td>
                  <td><.run_status status={run.status} /></td>
                </tr>
              </tbody>
            </table>
          </div>
          <div :if={@runs_page.total_pages > 1} class="mt-4 flex items-center justify-between">
            <button
              phx-click="runs-page"
              phx-value-page={@runs_page.page - 1}
              disabled={@runs_page.page == 1}
              class="btn btn-outline btn-sm"
            >Previous</button>
            <span class="text-sm text-base-content/60">
              Page {@runs_page.page} of {@runs_page.total_pages}
            </span>
            <button
              phx-click="runs-page"
              phx-value-page={@runs_page.page + 1}
              disabled={@runs_page.page == @runs_page.total_pages}
              class="btn btn-outline btn-sm"
            >Next</button>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp bundle_metric(assigns) do
    ~H"""
    <div class="rounded-lg border border-base-300 bg-base-200/40 px-3 py-2">
      <p class="text-xs text-base-content/55">{@label}</p>
      <p class="mt-1 font-mono text-sm font-semibold">{@value}</p>
    </div>
    """
  end

  defp bundle_bytes(%{declared_asset_bytes: bytes, assets_with_unknown_size: 0}),
    do: Integer.to_string(bytes)

  defp bundle_bytes(%{declared_asset_bytes: bytes, assets_with_unknown_size: unknown}),
    do: "#{bytes} + #{unknown} unknown"

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp fact(assigns) do
    ~H"""
    <div class="rounded-xl bg-base-200 p-4">
      <p class="text-xs font-bold uppercase tracking-wider text-base-content/45">{@label}</p><p class="mt-1 font-semibold">
        {@value}
      </p>
    </div>
    """
  end

  defp terminal_count(run),
    do: run.items_succeeded + run.items_skipped + run.items_failed

  defp run_progress(%{items_discovered: 0, status: status})
       when status in [:succeeded, :failed, :cancelled],
       do: 100

  defp run_progress(%{items_discovered: 0}), do: 0

  defp run_progress(run), do: round(terminal_count(run) / run.items_discovered * 100)

  defp json(value), do: Jason.encode!(value, pretty: true)

  attr :status, :atom, required: true

  defp run_status(assigns) do
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
