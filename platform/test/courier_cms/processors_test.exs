defmodule CourierCMS.ProcessorsTest do
  use ExUnit.Case, async: false

  alias CourierCMS.ExtensionSDK.AdapterError
  alias CourierCMS.Processors

  @definition "title=title|com.couriercms.fake/fake_prefix|{\"prefix\":\"CMS: \"}"

  test "parses, version-pins, formats, and executes an installed Processor" do
    assert {:ok, [processor]} = Processors.parse(@definition)
    assert processor["component_version"] == "0.1.0"
    assert processor["failure_policy"] == "fail"
    assert Processors.format([processor]) == @definition

    assert {:ok, %{"title" => "CMS: Delivery"}} =
             Processors.apply(%{"title" => "Delivery"}, [processor])
  end

  test "ordered Processors may consume an earlier Processor output" do
    definitions =
      @definition <> "\ntitle=title|com.couriercms.fake/fake_prefix|{\"prefix\":\"Again: \"}"

    assert {:ok, processors} = Processors.parse(definitions)

    assert {:ok, %{"title" => "Again: CMS: Delivery"}} =
             Processors.apply(%{"title" => "Delivery"}, processors)
  end

  test "reports content-free execution evidence to an observer" do
    assert {:ok, processors} = Processors.parse(@definition)
    parent = self()

    observer = fn event, evidence ->
      send(parent, {event, evidence})
      :ok
    end

    assert {:ok, %{"title" => "CMS: Delivery"}} =
             Processors.apply(%{"title" => "Delivery"}, processors, nil, observer: observer)

    assert_receive {:started,
                    %{
                      position: 1,
                      component_id: "fake_prefix",
                      status: :processing,
                      input_bytes: input_bytes,
                      input_hash: "sha256:" <> _input_hash
                    }}

    assert input_bytes > 0

    assert_receive {:finished,
                    %{
                      position: 1,
                      status: :succeeded,
                      output_bytes: output_bytes,
                      output_hash: "sha256:" <> _output_hash,
                      duration_us: duration_us,
                      completed_at: %DateTime{}
                    }}

    assert output_bytes > 0
    assert duration_us >= 0
  end

  test "rejects unavailable components and invalid component configuration" do
    assert {:error, message} =
             Processors.parse("title=title|com.example.missing/cleanup|{}")

    assert message =~ "not installed"

    assert {:error, message} =
             Processors.parse("title=title|com.couriercms.fake/fake_prefix|{\"prefix\":123}")

    assert message =~ "prefix must be a short string"
  end

  test "rejects artifact evidence that does not match the pinned component" do
    assert {:ok, processors} = Processors.parse(@definition)

    assert {:error, %AdapterError{category: :unsupported}} =
             Processors.apply(%{"title" => "Delivery"}, processors, [])
  end

  test "returns a safe error when the input path is absent" do
    assert {:ok, processors} = Processors.parse(@definition)

    assert {:error, %AdapterError{category: :transformation_failed} = error} =
             Processors.apply(%{}, processors)

    refute error.message =~ "Delivery"
  end

  test "bounds Processor wall-clock execution" do
    previous = Application.fetch_env!(:couriercms, :processor_timeout_ms)
    Application.put_env(:couriercms, :processor_timeout_ms, 5)
    on_exit(fn -> Application.put_env(:couriercms, :processor_timeout_ms, previous) end)

    assert {:ok, processors} =
             Processors.parse("title=title|com.couriercms.fake/fake_prefix|{\"delay_ms\":25}")

    assert {:error, %AdapterError{category: :timeout, retryable: true}} =
             Processors.apply(%{"title" => "Delivery"}, processors)
  end
end
