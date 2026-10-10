defmodule CourierCMSExtension.Sanity.TargetTest do
  use ExUnit.Case, async: true

  alias CourierCMSExtension.Sanity.{Client, Target}
  alias CourierCMS.ExtensionSDK.{DeliveryEnvelope, SourceIdentity}

  setup do
    stub = {__MODULE__, self()}

    connection = %{
      endpoint: "https://project.api.sanity.io",
      credentials: %{"token" => "secret-token"},
      settings: %{
        "dataset" => "production",
        "api_version" => "v2026-09-24",
        client: Client,
        req_options: [plug: {Req.Test, stub}]
      }
    }

    %{connection: connection, stub: stub}
  end

  test "tests authenticated query and dry-run write access", %{connection: connection, stub: stub} do
    Req.Test.stub(stub, fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer secret-token"]

      case {conn.method, conn.request_path} do
        {"GET", "/v2026-09-24/data/query/production"} ->
          conn = Plug.Conn.fetch_query_params(conn)
          assert conn.query_params["query"] == "count(*)"
          Req.Test.json(conn, %{"result" => 0})

        {"POST", "/v2026-09-24/data/mutate/production"} ->
          conn = Plug.Conn.fetch_query_params(conn)
          assert conn.query_params["dryRun"] == "true"

          assert %{"mutations" => [%{"create" => %{"_type" => "couriercmsDelivery"}}]} =
                   request_json(conn)

          Req.Test.json(conn, %{"results" => [%{"documentId" => "dry-run"}]})
      end
    end)

    assert :ok = Target.test_connection(connection)
  end

  test "finds an existing delivery by CourierCMS key", %{connection: connection, stub: stub} do
    Req.Test.expect(stub, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["$couriercmsKey"] == ~S|"key-1"|
      assert conn.query_params["$destinationId"] == ~S|"destination-1"|

      Req.Test.json(conn, %{
        "result" => %{
          "_id" => "generated-id",
          "installationId" => "installation-1",
          "routeId" => "route-1",
          "destinationId" => "destination-1",
          "couriercmsKey" => "key-1"
        }
      })
    end)

    assert {:ok, result} =
             Target.find_delivery(connection, %{id: "destination-1", scope: %{}}, "key-1")

    assert result.target_reference == "generated-id"

    assert result.ownership == %{
             "installation_id" => "installation-1",
             "route_id" => "route-1",
             "destination_id" => "destination-1",
             "couriercms_key" => "key-1"
           }
  end

  test "creates a delivery and uploads its public featured image", %{
    connection: connection,
    stub: stub
  } do
    Req.Test.stub(stub, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/v2026-09-24/assets/images/production/from-url"} ->
          assert request_json(conn)["url"] == "https://wordpress.example/image.jpg"
          Req.Test.json(conn, %{"document" => %{"_id" => "image-asset-id"}})

        {"POST", "/v2026-09-24/data/mutate/production"} ->
          %{"mutations" => [%{"create" => document}]} = request_json(conn)
          assert document["_type"] == "couriercmsDelivery"
          assert document["title"] == "a-delivery--abc12345"
          assert document["couriercmsKey"] == "key-1"
          assert document["destinationId"] == "destination-1"
          assert document["featuredImage"]["asset"]["_ref"] == "image-asset-id"
          canonical = Jason.decode!(document["deliveryJson"])
          assert canonical["couriercms"]["deliveryKey"] == "key-1"
          assert canonical["payload"]["title"] == "A delivery"
          refute Map.has_key?(document, "payloadJson")
          assert document["projectedTitle"] == "A delivery"
          assert document["_id"] =~ ~r/^couriercms\.[A-Za-z0-9_-]{43}$/

          Req.Test.json(conn, %{"results" => [%{"documentId" => document["_id"]}]})
      end
    end)

    assert {:ok, result} = Target.create_delivery(connection, delivery())
    assert result.target_reference =~ ~r/^couriercms\.[A-Za-z0-9_-]{43}$/
    assert result.ownership["couriercms_key"] == "key-1"
  end

  test "recovers an ambiguous deterministic create by looking up owned content", %{
    connection: connection,
    stub: stub
  } do
    delivery = delivery()
    delivery = %{delivery | payload: Map.delete(delivery.payload, "featured_image")}

    Req.Test.stub(stub, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/v2026-09-24/data/mutate/production"} ->
          Plug.Conn.send_resp(conn, 409, Jason.encode!(%{"error" => "already exists"}))

        {"GET", "/v2026-09-24/data/query/production"} ->
          Req.Test.json(conn, %{
            "result" => %{
              "_id" => "couriercms-existing",
              "installationId" => "installation-1",
              "routeId" => "route-1",
              "destinationId" => "destination-1",
              "couriercmsKey" => "key-1"
            }
          })
      end
    end)

    assert {:ok, result} = Target.create_delivery(connection, delivery)
    assert result.target_reference == "couriercms-existing"
    assert result.ownership["route_id"] == "route-1"
  end

  test "refuses to patch a document owned by another route", %{connection: connection} do
    ownership = %{
      "installation_id" => "installation-1",
      "route_id" => "another-route",
      "destination_id" => "destination-1",
      "couriercms_key" => "key-1"
    }

    assert {:error, error} =
             Target.update_delivery(connection, "generated-id", delivery(), ownership)

    assert error.category == :ownership_violation
  end

  test "validates projections against the shipped Intake Schema", %{connection: connection} do
    assert :ok =
             Target.validate_projections(connection, [
               %{
                 "target_field" => "projectedBoolean",
                 "source_path" => "payload.featured",
                 "type" => "boolean"
               }
             ])

    assert {:error, error} =
             Target.validate_projections(connection, [
               %{
                 "target_field" => "customTitle",
                 "source_path" => "payload.title",
                 "type" => "string"
               }
             ])

    assert error.category == :mapping_failed
    assert error.message =~ "does not define"

    assert {:error, error} =
             Target.validate_projections(connection, [
               %{
                 "target_field" => "projectedTitle",
                 "source_path" => "payload.score",
                 "type" => "number"
               }
             ])

    assert error.message =~ "is string, not number"
  end

  test "an update unsets absent projection slots", %{connection: connection, stub: stub} do
    Req.Test.expect(stub, fn conn ->
      %{"mutations" => [%{"patch" => patch}]} = request_json(conn)
      assert patch["id"] == "generated-id"
      assert "payloadJson" in patch["unset"]
      assert "projectedTitle" in patch["unset"]
      assert "featuredImage" in patch["unset"]
      refute Map.has_key?(patch["set"], "projectedTitle")
      Req.Test.json(conn, %{"results" => [%{"documentId" => "generated-id"}]})
    end)

    delivery = delivery()
    payload = Map.delete(delivery.payload, "featured_image")

    delivery = %{
      delivery
      | payload: payload,
        canonical_document: put_in(delivery.canonical_document, ["payload"], payload),
        projections: %{"projectedTitle" => nil}
    }

    ownership = %{
      "installation_id" => "installation-1",
      "route_id" => "route-1",
      "destination_id" => "destination-1",
      "couriercms_key" => "key-1"
    }

    assert {:ok, result} =
             Target.update_delivery(connection, "generated-id", delivery, ownership)

    assert result.target_reference == "generated-id"
  end

  defp delivery do
    identity = %SourceIdentity{
      item_key: "6",
      locale_key: "en-US",
      revision_key: "2026-09-24T18:36:44",
      state: :published,
      modified_at: ~U[2026-09-24 18:36:44Z]
    }

    envelope = %DeliveryEnvelope{
      installation_id: "installation-1",
      route_id: "route-1",
      destination_id: "destination-1",
      route_revision: 1,
      delivery_key: "key-1",
      source_connection_id: "source-1",
      source_identity: identity,
      source_type: "post",
      contract_version: 1,
      delivered_at: ~U[2026-09-24 18:40:00Z],
      content_hash: "sha256:content"
    }

    payload = %{
      "title" => "A delivery",
      "canonical_url" => "https://wordpress.example/a-delivery",
      "featured_image" => %{
        "source_id" => "9",
        "source_url" => "https://wordpress.example/image.jpg",
        "filename" => "image.jpg",
        "alt" => "Example image"
      }
    }

    %{
      envelope: envelope,
      payload: payload,
      canonical_document: %{
        "couriercms" => %{"deliveryKey" => envelope.delivery_key},
        "payload" => payload
      },
      projections: %{"projectedTitle" => "A delivery"},
      name: %{value: "A delivery", suffix: "abc12345"},
      destination: %{id: "destination-1", scope: %{}}
    }
  end

  defp request_json(conn) do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)
    Jason.decode!(body)
  end
end
