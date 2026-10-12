defmodule CourierCMSExtension.WordPress.SourceTest do
  use ExUnit.Case, async: true

  alias CourierCMSExtension.WordPress.Source

  setup do
    test_pid = self()

    fixture =
      "test/fixtures/wordpress/post-101.json"
      |> File.read!()
      |> Jason.decode!()

    stub = {__MODULE__, self()}

    Req.Test.stub(stub, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      case conn.request_path do
        "/wp-json/wp/v2/categories" ->
          assert conn.query_params["slug"] == "engineering"
          Req.Test.json(conn, [%{"id" => 4, "slug" => "engineering"}])

        "/wp-json/wp/v2/tags" ->
          id = if conn.query_params["slug"] == "elixir", do: 8, else: 9
          Req.Test.json(conn, [%{"id" => id, "slug" => conn.query_params["slug"]}])

        "/wp-json/wp/v2/posts" ->
          send(test_pid, {:post_query, conn.query_params})
          page = String.to_integer(conn.query_params["page"] || "1")
          body = if page == 1, do: [Map.take(fixture, ["id", "modified_gmt", "status"])], else: []

          conn
          |> Plug.Conn.put_resp_header("x-wp-totalpages", "1")
          |> Req.Test.json(body)

        "/wp-json/wp/v2/posts/101" ->
          Req.Test.json(conn, fixture)

        "/wp-content/uploads/delivery-pipeline.jpg" ->
          conn
          |> Plug.Conn.put_resp_content_type("image/jpeg")
          |> Plug.Conn.put_resp_header("content-length", "11")
          |> Plug.Conn.send_resp(200, "image-bytes")

        "/wp-content/uploads/inline-diagram.png" ->
          conn
          |> Plug.Conn.put_resp_content_type("image/png")
          |> Plug.Conn.put_resp_header("content-length", "12")
          |> Plug.Conn.send_resp(200, "inline-image")
      end
    end)

    connection = %{
      endpoint: "https://wordpress.example",
      settings: %{
        "default_locale" => "en-CA",
        req_options: [plug: {Req.Test, stub}]
      }
    }

    %{connection: connection}
  end

  test "tests a public WordPress REST connection", %{connection: connection} do
    assert :ok = Source.test_connection(connection)
  end

  test "tests configured Application Password credentials using edit context" do
    stub = {__MODULE__, :authenticated, self()}

    Req.Test.expect(stub, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.query_params["context"] == "edit"

      expected = "Basic " <> Base.encode64("couriercms-reader:app-password")
      assert Plug.Conn.get_req_header(conn, "authorization") == [expected]
      Req.Test.json(conn, [])
    end)

    connection = %{
      endpoint: "https://wordpress.example",
      credentials: %{
        "username" => "couriercms-reader",
        "application_password" => "app-password"
      },
      settings: %{req_options: [plug: {Req.Test, stub}]}
    }

    assert :ok = Source.test_connection(connection)
  end

  test "connector signing secret does not require authenticated WordPress reads" do
    stub = {__MODULE__, :connector_secret_only, self()}

    Req.Test.expect(stub, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)

      assert conn.request_path == "/wp-json/wp/v2/posts"
      assert conn.query_params["context"] == "view"
      assert conn.query_params["include"] == "101"
      assert Plug.Conn.get_req_header(conn, "authorization") == []

      conn
      |> Plug.Conn.put_resp_header("x-wp-totalpages", "1")
      |> Req.Test.json([
        %{"id" => 101, "modified_gmt" => "2026-02-14T10:30:00", "status" => "publish"}
      ])
    end)

    connection = %{
      endpoint: "https://wordpress.example",
      credentials: %{"connector_secret" => String.duplicate("s", 32)},
      settings: %{req_options: [plug: {Req.Test, stub}]}
    }

    assert {:ok, %{items: [identity], cursor: nil}} =
             Source.enumerate(connection, %{"source_item_ids" => ["101"]}, nil)

    assert identity.item_key == "101"
  end

  test "normalizes WordPress rate limiting without leaking its response" do
    stub = {__MODULE__, :rate_limited, self()}

    Req.Test.expect(stub, fn conn ->
      conn
      |> Plug.Conn.put_status(429)
      |> Plug.Conn.put_resp_header("retry-after", "7")
      |> Req.Test.json(%{"message" => "response content must stay internal"})
    end)

    connection = %{
      endpoint: "https://wordpress.example",
      settings: %{req_options: [plug: {Req.Test, stub}]}
    }

    assert {:error, error} = Source.test_connection(connection)
    assert error.category == :rate_limited
    assert error.retryable
    assert error.retry_after_ms == 7_000
    refute error.message =~ "response content"
  end

  test "enumerates filtered posts with stable identities", %{connection: connection} do
    selection = %{
      "content_type" => "post",
      "state" => "published",
      "category" => "Engineering",
      "tags" => ["elixir", "architecture"],
      "published_year" => "2026"
    }

    assert {:ok, %{items: [identity], cursor: nil}} =
             Source.enumerate(connection, selection, nil)

    assert identity.item_key == "101"
    assert identity.locale_key == "en-CA"
    assert identity.revision_key == "2026-02-14T10:30:00"
    assert identity.state == :published
  end

  test "limits publish-event enumeration to the affected post", %{connection: connection} do
    assert {:ok, %{items: [_identity], cursor: nil}} =
             Source.enumerate(connection, %{"source_item_ids" => ["101"]}, nil)

    assert_receive {:post_query, params}
    assert params["include"] == "101"
  end

  test "incremental discovery uses the bounded WordPress modification window", %{
    connection: connection
  } do
    checkpoint = %{
      "after" => "2026-09-24T19:58:00Z",
      "before" => "2026-09-24T20:05:00Z"
    }

    assert {:ok, %{items: [_identity], cursor: nil}} =
             Source.changes_since(connection, %{}, checkpoint, nil)

    assert_receive {:post_query, params}
    assert params["modified_after"] == checkpoint["after"]
    assert params["modified_before"] == checkpoint["before"]
    assert params["orderby"] == "modified"
  end

  test "reads and assembles a post into a vendor-neutral Content Bundle", %{
    connection: connection
  } do
    {:ok, %{items: [identity]}} = Source.enumerate(connection, %{}, nil)
    assert {:ok, bundle} = Source.read_root(connection, identity, %{})
    node = bundle.root

    assert node.source_type == "post"
    assert node.name == "Reliable content & delivery"

    assert node.fields["author"] == %{
             "source_id" => "12",
             "name" => "Maya & Chen",
             "url" => "https://wordpress.example/author/maya/"
           }

    assert [%{"slug" => "engineering"}] = node.fields["categories"]
    assert Enum.map(node.fields["tags"], & &1["slug"]) == ["elixir", "architecture"]
    assert node.fields["body"]["format"] == "html"
    assert node.fields["body"]["value"] =~ "<strong>observable</strong>"

    assert node.fields["featured_image"] == %{
             "source_id" => "501",
             "source_url" => "https://wordpress.example/wp-content/uploads/delivery-pipeline.jpg",
             "filename" => "delivery-pipeline.jpg",
             "media_type" => "image/jpeg",
             "width" => 1600,
             "height" => 900,
             "alt" => "A content delivery pipeline",
             "caption" => "Delivery pipeline"
           }

    assert [asset, inline_asset] = bundle.assets
    assert asset.source_key == "501"
    assert asset.field_path == "fields.featured_image"
    assert asset.required
    assert asset.retrieval["url"] == node.fields["featured_image"]["source_url"]
    assert inline_asset.source_key == "777"
    assert inline_asset.variant_key =~ "inline-"
    assert inline_asset.field_path == nil
    assert inline_asset.required
    assert inline_asset.metadata["usage"] == "inline_html"
    assert inline_asset.metadata["source_url"] =~ "inline-diagram.png"
  end

  test "rejects unsupported source scope", %{connection: connection} do
    assert {:error, error} =
             Source.enumerate(connection, %{"content_type" => "page"}, nil)

    assert error.category == :invalid_selection
  end

  test "streams a featured image through the asset contract", %{connection: connection} do
    {:ok, %{items: [identity]}} = Source.enumerate(connection, %{}, nil)
    assert {:ok, bundle} = Source.read_root(connection, identity, %{})
    descriptor = Enum.find(bundle.assets, &(&1.source_key == "501"))

    assert {:ok, content} = Source.read_asset(connection, descriptor)
    assert content.byte_size == 11
    assert content.media_type == "image/jpeg"
    assert content.chunks |> Enum.to_list() |> IO.iodata_to_binary() == "image-bytes"
  end

  test "uses source credentials only for same-origin assets" do
    same_origin_stub = {__MODULE__, :same_origin_asset, self()}

    Req.Test.expect(same_origin_stub, fn conn ->
      expected = "Basic " <> Base.encode64("couriercms-reader:app-password")
      assert Plug.Conn.get_req_header(conn, "authorization") == [expected]
      Plug.Conn.send_resp(conn, 200, "protected-image")
    end)

    connection = %{
      endpoint: "https://wordpress.example",
      credentials: %{
        "username" => "couriercms-reader",
        "application_password" => "app-password"
      },
      settings: %{req_options: [plug: {Req.Test, same_origin_stub}]}
    }

    descriptor = %CourierCMS.ExtensionSDK.AssetDescriptor{
      source_key: "501",
      filename: "protected.jpg",
      media_type: "image/jpeg",
      retrieval: %{"kind" => "url", "url" => "https://wordpress.example/protected.jpg"}
    }

    assert {:ok, content} = Source.read_asset(connection, descriptor)
    assert content.chunks |> Enum.to_list() |> IO.iodata_to_binary() == "protected-image"

    external_stub = {__MODULE__, :external_asset, self()}

    Req.Test.expect(external_stub, fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == []
      Plug.Conn.send_resp(conn, 200, "cdn-image")
    end)

    external_connection =
      put_in(connection, [:settings, :req_options], plug: {Req.Test, external_stub})

    external_descriptor = put_in(descriptor.retrieval["url"], "https://cdn.example/protected.jpg")

    assert {:ok, external_content} = Source.read_asset(external_connection, external_descriptor)
    assert external_content.chunks |> Enum.to_list() |> IO.iodata_to_binary() == "cdn-image"
  end

  test "does not bind a changed post to an older discovered revision", %{connection: connection} do
    {:ok, %{items: [identity]}} = Source.enumerate(connection, %{}, nil)
    stale = %{identity | revision_key: "older-revision"}

    assert {:error, error} = Source.read_root(connection, stale, %{})
    assert error.category == :invalid_content
    assert error.message =~ "changed after discovery"
  end
end
