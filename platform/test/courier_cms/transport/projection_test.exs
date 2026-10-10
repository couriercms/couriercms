defmodule CourierCMS.Transport.ProjectionTest do
  use ExUnit.Case, async: true

  alias CourierCMS.Transport.Projection

  test "parses, formats, and resolves typed projections" do
    text = """
    projectedTitle=payload.title:string:required
    projectedPublishedAt=payload.published_at:datetime
    projectedBoolean=payload.featured:boolean
    projectedNumber=payload.score:number
    """

    assert {:ok, definitions} = Projection.parse(text)
    assert Projection.format(definitions) =~ "projectedTitle=payload.title:string:required"

    document = %{
      "couriercms" => %{"contractVersion" => 1},
      "payload" => %{
        "title" => "Canonical title",
        "published_at" => "2026-09-24T18:40:00Z",
        "featured" => true,
        "score" => 12.5
      }
    }

    assert {:ok, projected} = Projection.project(document, definitions)
    assert projected["projectedTitle"] == document["payload"]["title"]
    assert projected["projectedPublishedAt"] == document["payload"]["published_at"]
    assert projected["projectedBoolean"] == true
    assert projected["projectedNumber"] == 12.5
  end

  test "retains optional missing fields as nil so targets can unset stale values" do
    definitions = [
      %{
        "target_field" => "projectedTitle",
        "source_path" => "payload.title",
        "type" => "string"
      }
    ]

    assert {:ok, %{"projectedTitle" => nil}} =
             Projection.project(%{"couriercms" => %{}, "payload" => %{}}, definitions)
  end

  test "rejects missing required values and incompatible values" do
    required = [
      %{
        "target_field" => "projectedTitle",
        "source_path" => "payload.title",
        "type" => "string",
        "required" => true
      }
    ]

    assert {:error, error} =
             Projection.project(%{"couriercms" => %{}, "payload" => %{}}, required)

    assert error.category == :mapping_failed

    assert {:error, error} =
             Projection.project(
               %{"couriercms" => %{}, "payload" => %{"title" => 42}},
               required
             )

    assert error.message =~ "not a valid string"
  end
end
