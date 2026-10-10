defmodule CourierCMS.Transport.DeliveryNameTest do
  use ExUnit.Case, async: true

  alias CourierCMS.Transport.DeliveryName

  test "resolves a configured canonical path and a stable short suffix" do
    assert DeliveryName.resolve(
             %{"payload" => %{"title" => "Mountain Bike"}},
             "payload.title",
             "source-42",
             "74bd2191remaining-key"
           ) == %{value: "Mountain Bike", suffix: "74bd2191"}
  end

  test "falls back to the source item key for missing or unusable values" do
    assert DeliveryName.resolve(
             %{"payload" => %{"title" => %{}}},
             "payload.title",
             "source-42",
             "a82f14c9remaining-key"
           ) == %{value: "source-42", suffix: "a82f14c9"}
  end
end
