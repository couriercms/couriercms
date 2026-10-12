defmodule CourierCMS.Extensions.GatewayTest do
  use ExUnit.Case, async: false

  alias CourierCMS.Extensions.{ComponentRegistry, Gateway}

  test "resolves packaged components through stable identifiers" do
    assert {:ok, entry} = ComponentRegistry.fetch("com.couriercms.wordpress", "wordpress")
    assert entry.adapter_key == "wordpress"
    assert entry.component.version == "0.1.0"

    assert {:ok, component} = Gateway.fetch_component("wordpress")
    assert component.extension_id == "com.couriercms.wordpress"
    assert :source in component.capabilities

    reference = %{extension_id: "com.couriercms.wordpress", component_id: "wordpress"}
    assert {:ok, artifact} = Gateway.artifact(reference)
    assert artifact["runtime"] == "beam"
    assert artifact["provenance"] == "package"
    assert {:ok, ^reference} = Gateway.validate_artifact(artifact, :source)

    mismatched = Map.put(artifact, "checksum", "different")
    assert {:error, error} = Gateway.validate_artifact(mismatched, :source)
    assert error.category == :unsupported
  end

  test "invokes only declared source and target operations" do
    assert %{"source" => true} =
             Gateway.source("fake_source", :capabilities, [%{}])

    assert :deterministic_id = Gateway.target("fake_target", :idempotency_strategy, [])
    assert :error = Gateway.source("fake_source", :not_a_callback, [])
    assert :error = Gateway.target("missing", :idempotency_strategy, [])
  end

  test "discovers, validates, and invokes Processor components" do
    reference = %{extension_id: "com.couriercms.fake", component_id: "fake_prefix"}

    assert Gateway.processor_available?(reference)
    assert {:ok, definition} = Gateway.processor_definition(reference)
    assert definition.label == "Fake prefix"
    assert {:ok, artifact} = Gateway.artifact(reference)
    assert {:ok, ^reference} = Gateway.validate_artifact(artifact, :processor)
    assert :ok = Gateway.processor(reference, :validate_config, [%{"prefix" => "CMS: "}])

    assert {:ok, "CMS: title"} =
             Gateway.processor(reference, :process, ["title", %{"prefix" => "CMS: "}])
  end

  test "invokes the official target-independent Content Processors" do
    normalizer = %{
      extension_id: "com.couriercms.content",
      component_id: "html_text_normalizer"
    }

    replacer = %{
      extension_id: "com.couriercms.content",
      component_id: "exact_token_replacer"
    }

    assert {:ok, "<p>Line one\nline two</p>"} =
             Gateway.processor(normalizer, :process, [" <p>Line one\r\nline two</p> ", %{}])

    assert {:ok, "Copyright 2026"} =
             Gateway.processor(replacer, :process, [
               "Copyright [year]",
               %{"replacements" => %{"[year]" => "2026"}}
             ])
  end

  test "reports source and target availability without exposing modules" do
    assert Gateway.source_available?("wordpress")
    refute Gateway.target_available?("wordpress")
    assert Gateway.target_available?("sanity")
    refute Gateway.source_available?("sanity")
    assert Gateway.source_supports?("wordpress", :changes_since)
  end

  test "rebuilds the node-local registry after its owner restarts" do
    previous = Process.whereis(ComponentRegistry)
    :ok = GenServer.stop(previous)

    restarted = wait_for_restart(previous, 20)
    assert is_pid(restarted)
    assert {:ok, _component} = wait_for_component("wordpress", 50)
  end

  defp wait_for_restart(_previous, 0), do: nil

  defp wait_for_restart(previous, attempts) do
    case Process.whereis(ComponentRegistry) do
      pid when is_pid(pid) and pid != previous ->
        pid

      _other ->
        Process.sleep(10)
        wait_for_restart(previous, attempts - 1)
    end
  end

  defp wait_for_component(_key, 0), do: :error

  defp wait_for_component(key, attempts) do
    case Gateway.fetch_component(key) do
      {:ok, _component} = result ->
        result

      :error ->
        Process.sleep(10)
        wait_for_component(key, attempts - 1)
    end
  end
end
