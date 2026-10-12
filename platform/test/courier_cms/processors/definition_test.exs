defmodule CourierCMS.Processors.DefinitionTest do
  use ExUnit.Case, async: true

  alias CourierCMS.ExtensionSDK.AdapterError
  alias CourierCMS.Processors.Definition

  @definition %{
    label: "Example",
    description: "Example Processor",
    config_fields: [
      %{key: :title, label: "Title", type: :text, required: true},
      %{key: :count, label: "Count", type: :integer, default: 2},
      %{key: :enabled, label: "Enabled", type: :checkbox, default: true},
      %{key: :values, label: "Values", type: :json_object, default: %{}}
    ]
  }

  test "validates and casts generic Processor configuration metadata" do
    assert :ok = Definition.validate(@definition)

    assert Definition.defaults(@definition) == %{
             "title" => "",
             "count" => "2",
             "enabled" => "true",
             "values" => "{}"
           }

    assert {:ok, config} =
             Definition.cast_config(@definition, %{
               "title" => "Content",
               "count" => "3",
               "enabled" => "false",
               "values" => ~s({"old":"new"})
             })

    assert config == %{
             "title" => "Content",
             "count" => 3,
             "enabled" => false,
             "values" => %{"old" => "new"}
           }
  end

  test "rejects malformed metadata and values without executing the Processor" do
    assert {:error, "configuration field type is unsupported"} =
             Definition.validate(%{
               label: "Unsafe",
               description: "",
               config_fields: [%{key: :code, label: "Code", type: :script}]
             })

    assert {:error, %AdapterError{message: "Values must be a JSON object"}} =
             Definition.cast_config(@definition, %{
               "title" => "Content",
               "count" => "3",
               "enabled" => "true",
               "values" => "[]"
             })
  end
end
