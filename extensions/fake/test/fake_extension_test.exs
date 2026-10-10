defmodule CourierCMSExtension.FakeTest do
  use ExUnit.Case, async: false

  alias CourierCMS.ExtensionSDK.{DeliveryEnvelope, SourceIdentity}
  alias CourierCMSExtension.Fake.{Source, Target}

  test "declares development source and target components" do
    assert Source.component().extension_id == "com.couriercms.fake"
    assert Target.component().extension_id == "com.couriercms.fake"
    assert Target.idempotency_strategy() == :deterministic_id
  end

  test "creates, finds, and updates a deterministic delivery" do
    connection = %{id: "connection-#{System.unique_integer([:positive])}", settings: %{}}
    delivery = delivery("hash-1")

    assert {:ok, created} = Target.create_delivery(connection, delivery)
    assert created.target_reference == "fake:destination-1:key-1"

    assert {:ok, found} = Target.find_delivery(connection, delivery.destination, "key-1")
    assert found == created

    updated = delivery("hash-2")

    assert {:ok, result} =
             Target.update_delivery(
               connection,
               created.target_reference,
               updated,
               created.ownership
             )

    assert result == created
  end

  test "scopes the same Delivery Item key independently by Destination" do
    connection = %{id: "connection-#{System.unique_integer([:positive])}", settings: %{}}

    assert {:ok, first} = Target.create_delivery(connection, delivery("hash-1"))

    assert {:ok, second} =
             Target.create_delivery(connection, delivery("hash-1", "destination-2"))

    assert first.target_reference == "fake:destination-1:key-1"
    assert second.target_reference == "fake:destination-2:key-1"
    refute first.target_reference == second.target_reference
  end

  defp delivery(hash, destination_id \\ "destination-1") do
    identity = %SourceIdentity{
      item_key: "101",
      locale_key: "en-CA",
      revision_key: hash,
      state: :published
    }

    envelope = %DeliveryEnvelope{
      installation_id: "installation-1",
      route_id: "route-1",
      destination_id: destination_id,
      route_revision: 1,
      delivery_key: "key-1",
      source_connection_id: "source-1",
      source_identity: identity,
      source_type: "post",
      contract_version: 1,
      delivered_at: ~U[2026-01-01 00:00:00Z],
      content_hash: hash
    }

    %{
      envelope: envelope,
      payload: %{"title" => "Delivery"},
      canonical_document: %{"couriercms" => %{"deliveryKey" => "key-1"}},
      projections: %{},
      name: %{value: "Delivery", suffix: "abc12345"},
      destination: %{id: destination_id, scope: %{}}
    }
  end
end
