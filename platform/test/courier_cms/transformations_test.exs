defmodule CourierCMS.TransformationsTest do
  use ExUnit.Case, async: true

  alias CourierCMS.ExtensionSDK.AdapterError
  alias CourierCMS.Transformations

  test "parses, formats, and applies an ordered portable transformation chain" do
    text = "title=title|string.trim\nslug=title|string.slug\nurl=url|url.normalize"

    assert {:ok, transformations} = Transformations.parse(text)
    assert Transformations.format(transformations) == text

    assert {:ok, transformed} =
             Transformations.apply(
               %{
                 "title" => "  Reliable Content Delivery  ",
                 "url" => "HTTPS://Example.COM/articles/one?q=1"
               },
               transformations
             )

    assert transformed["title"] == "Reliable Content Delivery"
    assert transformed["slug"] == "reliable-content-delivery"
    assert transformed["url"] == "https://example.com/articles/one?q=1"
  end

  test "normalizes offset timestamps into canonical UTC ISO-8601" do
    assert {:ok, transformations} =
             Transformations.parse("published_at=published_at|datetime.iso8601")

    assert {:ok, transformed} =
             Transformations.apply(
               %{"published_at" => "2026-10-12T12:30:00-04:00"},
               transformations
             )

    assert transformed["published_at"] == "2026-10-12T16:30:00Z"
  end

  test "rejects unsupported operations and returns safe runtime errors" do
    assert {:error, message} = Transformations.parse("title=title|shell.execute")
    assert message =~ "unsupported operation"

    assert {:ok, transformations} = Transformations.parse("slug=missing|string.slug")

    assert {:error, %AdapterError{} = error} =
             Transformations.apply(%{"title" => "A title"}, transformations)

    assert error.category == :transformation_failed
    assert error.message == "Transformation string.slug could not find input path missing"
    refute error.message =~ "A title"
  end

  test "rejects a nested output that would overwrite through a scalar" do
    assert {:ok, transformations} = Transformations.parse("title.slug=title|string.slug")

    assert {:error, %AdapterError{} = error} =
             Transformations.apply(%{"title" => "A title"}, transformations)

    assert error.category == :transformation_failed
    assert error.message =~ "could not write output path"
  end
end
