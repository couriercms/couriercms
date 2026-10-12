defmodule CourierCMS.Integration.WordPressToSanityHTTPClient do
  @behaviour CourierCMS.ExtensionSDK.HTTPClient

  @name __MODULE__

  def child_spec(fixture) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [fixture]}}
  end

  def start_link(fixture), do: Agent.start_link(fn -> initial_state(fixture) end, name: @name)

  def state, do: Agent.get(@name, & &1)

  @impl true
  def request(_connection, method, options) do
    Agent.get_and_update(@name, &dispatch(&1, method, options))
  end

  defp dispatch(state, :get, options) do
    url = Keyword.fetch!(options, :url)

    cond do
      String.ends_with?(url, "/wp-json/wp/v2/posts") ->
        body = [Map.take(state.fixture, ["id", "modified_gmt", "status"])]
        {response(200, body, [{"x-wp-totalpages", "1"}]), state}

      String.ends_with?(url, "/wp-json/wp/v2/posts/101") ->
        {response(200, state.fixture), state}

      String.ends_with?(url, "/wp-content/uploads/delivery-pipeline.jpg") ->
        next = %{state | wordpress_asset_auth: Keyword.get(options, :auth)}
        {response(200, ["image-", "bytes"], [{"content-type", "image/jpeg"}]), next}

      true ->
        {response(404, %{}), state}
    end
  end

  defp dispatch(state, :post, options) do
    url = Keyword.fetch!(options, :url)

    cond do
      String.contains?(url, "/assets/images/") and state.upload_attempts == 0 ->
        {response(503, %{"error" => "temporary"}), %{state | upload_attempts: 1}}

      String.contains?(url, "/assets/images/") ->
        bytes = options |> Keyword.fetch!(:body) |> Enum.to_list() |> IO.iodata_to_binary()

        {response(200, %{"document" => %{"_id" => "image-asset-id"}}),
         %{state | upload_attempts: state.upload_attempts + 1, uploaded_bytes: bytes}}

      String.contains?(url, "/data/mutate/") ->
        mutation = options |> Keyword.fetch!(:json) |> get_in(["mutations", Access.at(0)])
        created = mutation["create"]
        document_id = created["_id"] || "created-document"

        next =
          cond do
            created["_type"] == "couriercmsAsset" -> %{state | asset_receipt: created}
            created["_type"] == "couriercmsDelivery" -> %{state | delivery_document: created}
            true -> state
          end

        {response(200, %{"results" => [%{"documentId" => document_id}]}), next}

      true ->
        {response(404, %{}), state}
    end
  end

  defp dispatch(state, _method, _options), do: {response(405, %{}), state}

  defp response(status, body, headers \\ []),
    do: {:ok, Req.Response.new(status: status, body: body, headers: headers)}

  defp initial_state(fixture) do
    %{
      fixture: fixture,
      upload_attempts: 0,
      uploaded_bytes: nil,
      wordpress_asset_auth: nil,
      asset_receipt: nil,
      delivery_document: nil
    }
  end
end

defmodule CourierCMS.Integration.WordPressToSanityTest do
  use ExUnit.Case, async: false

  alias CourierCMS.Assets.Transfer
  alias CourierCMS.ExtensionSDK.DeliveryEnvelope
  alias CourierCMS.Extensions.Gateway
  alias CourierCMS.Integration.WordPressToSanityHTTPClient, as: HTTPClient

  @wordpress %{extension_id: "com.couriercms.wordpress", component_id: "wordpress"}
  @sanity %{extension_id: "com.couriercms.sanity", component_id: "sanity"}

  setup do
    fixture_path =
      Path.expand(
        "../../../extensions/wordpress/test/fixtures/wordpress/post-101.json",
        __DIR__
      )

    fixture = fixture_path |> File.read!() |> Jason.decode!()
    start_supervised!({HTTPClient, fixture})

    previous = Application.get_env(:couriercms_extension_sdk, :http_client)
    Application.put_env(:couriercms_extension_sdk, :http_client, HTTPClient)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:couriercms_extension_sdk, :http_client, previous),
        else: Application.delete_env(:couriercms_extension_sdk, :http_client)
    end)

    :ok
  end

  test "official packages preserve WordPress content and retry a Sanity asset upload" do
    wordpress_connection = %{
      endpoint: "https://wordpress.example",
      settings: %{"default_locale" => "en-CA"},
      credentials: %{
        "username" => "couriercms-reader",
        "application_password" => "application-password"
      }
    }

    sanity_connection = %{
      endpoint: "https://project.api.sanity.io",
      settings: %{"dataset" => "production", "api_version" => "v2026-09-24"},
      credentials: %{"token" => "sanity-token"}
    }

    assert {:ok, %{items: [identity], cursor: nil}} =
             Gateway.source(@wordpress, :enumerate, [wordpress_connection, %{}, nil])

    assert {:ok, bundle} =
             Gateway.source(@wordpress, :read_root, [wordpress_connection, identity, %{}])

    descriptor = Enum.find(bundle.assets, &(&1.source_key == "501"))
    assert bundle.root.fields["title"] == "Reliable content & delivery"

    asset_delivery = fn materialized ->
      Gateway.target(@sanity, :create_asset, [
        sanity_connection,
        %{
          asset_key: "asset-key-501",
          descriptor: descriptor,
          content: materialized,
          destination: %{id: "destination-1", scope: %{}},
          ownership: %{
            installation_id: "installation-1",
            route_id: "route-1",
            destination_id: "destination-1",
            couriercms_asset_key: "asset-key-501"
          }
        }
      ])
    end

    assert {:ok, first_content} =
             Gateway.source(@wordpress, :read_asset, [wordpress_connection, descriptor])

    assert {:error, first_error} =
             Transfer.with_materialized(first_content, descriptor, asset_delivery)

    assert first_error.retryable

    assert {:ok, retry_content} =
             Gateway.source(@wordpress, :read_asset, [wordpress_connection, descriptor])

    assert {:ok, asset_result} =
             Transfer.with_materialized(retry_content, descriptor, asset_delivery)

    payload =
      put_in(
        bundle.root.fields,
        ["featured_image", "target_reference"],
        asset_result.target_reference
      )

    envelope = %DeliveryEnvelope{
      installation_id: "installation-1",
      route_id: "route-1",
      destination_id: "destination-1",
      route_revision: 1,
      delivery_key: "wordpress-101-en-ca",
      source_connection_id: "wordpress-connection-1",
      source_identity: identity,
      source_type: bundle.root.source_type,
      contract_version: 1,
      delivered_at: ~U[2026-10-12 12:00:00Z],
      content_hash: "sha256:content"
    }

    delivery = %{
      envelope: envelope,
      payload: payload,
      canonical_document: %{
        "couriercms" => %{"deliveryKey" => envelope.delivery_key},
        "payload" => payload
      },
      projections: %{"projectedTitle" => payload["title"]},
      name: %{value: payload["title"], suffix: "101abcde"},
      destination: %{id: "destination-1", scope: %{}}
    }

    assert {:ok, _delivery_result} =
             Gateway.target(@sanity, :create_delivery, [sanity_connection, delivery])

    state = HTTPClient.state()
    assert state.upload_attempts == 2
    assert state.uploaded_bytes == "image-bytes"
    assert state.wordpress_asset_auth == {:basic, "couriercms-reader:application-password"}
    assert state.asset_receipt["asset"]["_ref"] == "image-asset-id"
    assert state.delivery_document["projectedTitle"] == "Reliable content & delivery"
    assert state.delivery_document["featuredImage"]["asset"]["_ref"] == "image-asset-id"
  end
end
