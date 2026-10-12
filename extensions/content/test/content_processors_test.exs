defmodule CourierCMSExtension.Content.ProcessorsTest do
  use ExUnit.Case, async: true

  alias CourierCMS.ExtensionSDK.AdapterError
  alias CourierCMSExtension.Content.{ExactTokenReplacer, HtmlTextNormalizer}

  test "HTML text normalization is conservative and configurable" do
    input = "  <p>First\r\nline\u0000\u00A0</p>  "

    assert :ok = HtmlTextNormalizer.validate_config(%{"replace_non_breaking_spaces" => true})

    assert {:ok, "<p>First\nline </p>"} =
             HtmlTextNormalizer.process(input, %{"replace_non_breaking_spaces" => true})

    assert {:ok, ^input} =
             HtmlTextNormalizer.process(input, %{
               "normalize_line_endings" => false,
               "remove_control_characters" => false,
               "replace_non_breaking_spaces" => false,
               "trim" => false
             })
  end

  test "HTML text normalization rejects unknown or non-boolean options" do
    assert {:error, %AdapterError{category: :invalid_content}} =
             HtmlTextNormalizer.validate_config(%{"sanitize" => true})

    assert {:error, %AdapterError{category: :invalid_content}} =
             HtmlTextNormalizer.validate_config(%{"trim" => "yes"})

    assert {:error, %AdapterError{category: :transformation_failed}} =
             HtmlTextNormalizer.process(%{}, %{})
  end

  test "exact replacements handle known complete shortcode forms in one pass" do
    config = %{
      "replacements" => %{
        "[gallery ids=\"1,2\"]" => "<div data-gallery=\"1,2\"></div>",
        "[year]" => "2026",
        "2026" => "must not cascade"
      }
    }

    assert :ok = ExactTokenReplacer.validate_config(config)

    assert {:ok, "Copyright 2026 <div data-gallery=\"1,2\"></div>"} =
             ExactTokenReplacer.process("Copyright [year] [gallery ids=\"1,2\"]", config)
  end

  test "exact replacements require a bounded non-empty string map" do
    assert {:error, %AdapterError{category: :invalid_content}} =
             ExactTokenReplacer.validate_config(%{"replacements" => %{}})

    assert {:error, %AdapterError{category: :invalid_content}} =
             ExactTokenReplacer.validate_config(%{"replacements" => %{1 => "one"}})

    assert {:error, %AdapterError{category: :transformation_failed}} =
             ExactTokenReplacer.process([], %{"replacements" => %{"x" => "y"}})
  end

  test "components expose stable Processor identities" do
    assert HtmlTextNormalizer.component().component_id == "html_text_normalizer"
    assert ExactTokenReplacer.component().component_id == "exact_token_replacer"
    assert HtmlTextNormalizer.component().extension_id == "com.couriercms.content"
    assert ExactTokenReplacer.component().capabilities == [:processor]

    assert Enum.map(HtmlTextNormalizer.definition().config_fields, & &1.type) ==
             [:checkbox, :checkbox, :checkbox, :checkbox]

    assert [%{key: :replacements, type: :json_object}] =
             ExactTokenReplacer.definition().config_fields
  end
end
