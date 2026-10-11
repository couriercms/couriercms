defmodule CourierCMSExtension.WordPress.Source do
  @moduledoc "WordPress REST API source Adapter for published blog posts."

  @behaviour CourierCMS.ExtensionSDK.SourceAdapter

  alias CourierCMSExtension.WordPress.Client

  alias CourierCMS.ExtensionSDK.{
    AdapterError,
    AssetDescriptor,
    Component,
    ContentBundle,
    ContentNode,
    SourceIdentity
  }

  @default_page_size 50

  @impl true
  def component do
    Component.new!(
      extension_id: "com.couriercms.wordpress",
      component_id: "wordpress",
      kind: :adapter,
      version: "0.1.0",
      capabilities: [
        :source,
        :connection_test,
        :native_filtering,
        :incremental_changes,
        :publish_events,
        :revisions,
        :assets
      ]
    )
  end

  @impl true
  def definition do
    %{
      key: "wordpress",
      label: "WordPress",
      description: "WordPress REST API source Adapter",
      connection: %{
        description:
          "Public posts need no credentials; edit-context reads may use an Application Password.",
        endpoint: %{mode: :input, label: "Site URL", placeholder: "https://wordpress.example"},
        fields: [
          %{
            key: :default_locale,
            label: "Default locale",
            type: :text,
            storage: :setting,
            default: "und",
            required: true,
            pattern: ~r/^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/,
            pattern_message: "must be a locale such as en or en-CA"
          },
          %{
            key: :username,
            label: "Username",
            type: :text,
            storage: :credential,
            autocomplete: "username",
            help: "Optional for publicly readable published posts."
          },
          %{
            key: :application_password,
            label: "Application Password",
            type: :password,
            storage: :credential,
            min_length: 8,
            autocomplete: "new-password",
            help: "Use a dedicated, revocable WordPress Application Password."
          }
        ]
      },
      source: %{
        content_label: "posts",
        description:
          "Every matching published post is delivered independently, including future matches.",
        selection_fields: [
          %{
            key: :content_type,
            label: "Content type",
            type: :select,
            required: true,
            default: "post",
            options: [{"Posts", "post"}]
          },
          %{
            key: :state,
            label: "State",
            type: :select,
            required: true,
            default: "published",
            options: [{"Published", "published"}]
          },
          %{key: :category, label: "Category", type: :text, placeholder: "Any category"},
          %{key: :tags, label: "Tags", type: :list, placeholder: "Comma-separated"},
          %{
            key: :published_year,
            label: "Published year",
            type: :text,
            placeholder: "Any year",
            pattern: ~r/^\d{4}$/,
            pattern_message: "must be a four-digit year"
          }
        ],
        default_mapping: blog_mapping(),
        default_aggregation_rules: %{
          "include" => ["author", "categories", "tags", "featured_image"]
        },
        delivery_contract: %{"name" => "blog_delivery", "version" => 1}
      },
      connector: %{
        label: "WordPress publish Connector",
        setup_label: "Set up publish Connector",
        rotate_label: "Rotate Connector secret",
        path_template: "/api/connectors/{connection_id}/events"
      }
    }
  end

  @impl true
  def capabilities(_connection) do
    %{
      "source" => true,
      "connection_test" => true,
      "selection_preview" => false,
      "native_filtering" => true,
      "incremental_changes" => true,
      "publish_events" => true,
      "locales" => false,
      "revisions" => "published_modified_timestamp",
      "assets" => "featured_image_descriptor"
    }
  end

  @impl true
  def test_connection(connection), do: client(connection).test_connection(connection)

  @impl true
  def enumerate(connection, selection, cursor) do
    with :ok <- validate_selection(selection),
         {:ok, state} <- cursor_state(connection, selection, cursor) do
      if state.empty? do
        {:ok, %{items: [], cursor: nil}}
      else
        enumerate_page(connection, selection, state)
      end
    end
  end

  @impl true
  def changes_since(connection, selection, checkpoint, cursor) do
    selection =
      selection
      |> Map.put("modified_after", checkpoint["after"])
      |> Map.put("modified_before", checkpoint["before"])

    enumerate(connection, selection, cursor)
  end

  @impl true
  def read_root(connection, %SourceIdentity{} = expected_identity, _aggregation_rules) do
    with {:ok, post} <- client(connection).get_post(connection, expected_identity.item_key),
         {:ok, actual_identity} <- identity(connection, post),
         :ok <- ensure_revision(expected_identity, actual_identity) do
      content_bundle(post, actual_identity)
    end
  end

  defp enumerate_page(connection, selection, state) do
    params =
      [
        context: request_context(connection),
        status: "publish",
        page: state.page,
        per_page: page_size(connection),
        order: "asc",
        orderby: order_by(selection),
        _fields: "id,modified_gmt,status"
      ]
      |> put_source_item_ids(value(selection, "source_item_ids", []))
      |> put_ids(:categories, state.category_ids)
      |> put_ids(:tags, state.tag_ids)
      |> put_date_range(value(selection, "published_year"))
      |> put_modified_range(
        value(selection, "modified_after"),
        value(selection, "modified_before")
      )

    with {:ok, %{posts: posts, total_pages: total_pages}} <-
           client(connection).list_posts(connection, params),
         {:ok, identities} <- identities(connection, posts) do
      next_cursor =
        if state.page < total_pages do
          Map.put(state, :page, state.page + 1)
        end

      {:ok, %{items: identities, cursor: next_cursor}}
    end
  end

  defp cursor_state(connection, selection, nil) do
    categories = value(selection, "category") |> list_value()
    tags = value(selection, "tags", []) |> list_value()

    with {:ok, category_ids} <- resolve_ids(connection, "categories", categories),
         {:ok, tag_ids} <- resolve_ids(connection, "tags", tags) do
      empty? = category_ids == :not_found or tag_ids == :not_found

      {:ok,
       %{
         page: 1,
         category_ids: normalize_ids(category_ids),
         tag_ids: normalize_ids(tag_ids),
         empty?: empty?
       }}
    end
  end

  defp cursor_state(_connection, _selection, cursor) when is_map(cursor) do
    {:ok,
     %{
       page: Map.get(cursor, :page, Map.get(cursor, "page", 1)),
       category_ids: Map.get(cursor, :category_ids, Map.get(cursor, "category_ids", [])),
       tag_ids: Map.get(cursor, :tag_ids, Map.get(cursor, "tag_ids", [])),
       empty?: Map.get(cursor, :empty?, Map.get(cursor, "empty?", false))
     }}
  end

  defp cursor_state(_connection, _selection, _cursor),
    do: {:error, AdapterError.new(:invalid_selection, "WordPress cursor is invalid")}

  defp resolve_ids(_connection, _resource, []), do: {:ok, []}

  defp resolve_ids(connection, resource, slugs),
    do: client(connection).resolve_term_ids(connection, resource, slugs)

  defp normalize_ids(:not_found), do: []
  defp normalize_ids(ids), do: ids

  defp identities(connection, posts) do
    Enum.reduce_while(posts, {:ok, []}, fn post, {:ok, identities} ->
      case identity(connection, post) do
        {:ok, identity} -> {:cont, {:ok, [identity | identities]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, identities} -> {:ok, Enum.reverse(identities)}
      error -> error
    end
  end

  defp identity(connection, post) do
    with id when is_integer(id) <- post["id"],
         modified when is_binary(modified) <- post["modified_gmt"],
         {:ok, modified_at} <- parse_wordpress_datetime(modified),
         {:ok, identity} <-
           SourceIdentity.new(%{
             item_key: Integer.to_string(id),
             locale_key: default_locale(connection),
             revision_key: modified,
             state: :published,
             modified_at: modified_at
           }) do
      {:ok, identity}
    else
      _other ->
        {:error,
         AdapterError.new(:invalid_content, "WordPress post identity is incomplete or invalid")}
    end
  end

  defp content_bundle(post, identity) do
    embedded = post["_embedded"] || %{}
    author = embedded |> Map.get("author", []) |> List.first() |> normalize_author()
    terms = embedded |> Map.get("wp:term", []) |> List.flatten()
    media = embedded |> Map.get("wp:featuredmedia", []) |> List.first() |> normalize_media()

    root = %ContentNode{
      identity: identity,
      source_type: "post",
      name: rendered(post, "title") |> plain_text(),
      path: post["link"],
      fields: %{
        "title" => rendered(post, "title") |> plain_text(),
        "slug" => post["slug"],
        "excerpt" => rendered(post, "excerpt") |> plain_text(),
        "body" => %{"format" => "html", "value" => content_value(post)},
        "canonical_url" => post["link"],
        "published_at" => iso_datetime(post["date_gmt"]),
        "modified_at" => DateTime.to_iso8601(identity.modified_at),
        "author" => author,
        "categories" => normalize_terms(terms, "category"),
        "tags" => normalize_terms(terms, "post_tag"),
        "featured_image" => media
      },
      metadata: %{
        "adapter" => "wordpress",
        "wordpress_status" => post["status"],
        "wordpress_format" => post["format"]
      }
    }

    ContentBundle.new(%{
      root: root,
      assets: asset_descriptors(media),
      metadata: %{"adapter" => "wordpress"}
    })
  end

  defp asset_descriptors(nil), do: []

  defp asset_descriptors(media) do
    [
      %AssetDescriptor{
        source_key: media["source_id"],
        field_path: "fields.featured_image",
        filename: media["filename"],
        media_type: media["media_type"],
        required: true,
        retrieval: %{"kind" => "url", "url" => media["source_url"]},
        metadata: Map.take(media, ["width", "height", "alt", "caption"])
      }
    ]
  end

  defp validate_selection(selection) do
    cond do
      value(selection, "content_type", "post") != "post" ->
        {:error, AdapterError.new(:invalid_selection, "WordPress V0 supports only post content")}

      value(selection, "state", "published") not in ["publish", "published"] ->
        {:error,
         AdapterError.new(:invalid_selection, "WordPress V0 delivers published posts only")}

      invalid_year?(value(selection, "published_year")) ->
        {:error, AdapterError.new(:invalid_selection, "Published year must contain four digits")}

      true ->
        :ok
    end
  end

  defp ensure_revision(%SourceIdentity{revision_key: revision}, %SourceIdentity{
         revision_key: revision
       }),
       do: :ok

  defp ensure_revision(_expected, _actual),
    do:
      {:error,
       AdapterError.new(
         :invalid_content,
         "WordPress post changed after discovery; start a new Run to deliver the newer revision"
       )}

  defp normalize_author(%{"id" => id} = author) when is_integer(id) do
    %{
      "source_id" => Integer.to_string(id),
      "name" => plain_text(author["name"]),
      "url" => author["link"]
    }
    |> compact()
  end

  defp normalize_author(_author), do: nil

  defp normalize_terms(terms, taxonomy) do
    terms
    |> Enum.filter(&(&1["taxonomy"] == taxonomy and is_integer(&1["id"])))
    |> Enum.map(fn term ->
      %{
        "source_id" => Integer.to_string(term["id"]),
        "name" => plain_text(term["name"]),
        "slug" => term["slug"]
      }
      |> compact()
    end)
  end

  defp normalize_media(%{"id" => id, "source_url" => source_url} = media)
       when is_integer(id) and is_binary(source_url) and source_url != "" do
    details = media["media_details"] || %{}

    %{
      "source_id" => Integer.to_string(id),
      "source_url" => source_url,
      "filename" => filename(source_url),
      "media_type" => media["mime_type"],
      "width" => details["width"],
      "height" => details["height"],
      "alt" => media["alt_text"] |> plain_text(),
      "caption" => rendered(media, "caption") |> plain_text()
    }
    |> compact()
  end

  defp normalize_media(_media), do: nil

  defp rendered(map, field) do
    case map[field] do
      %{"raw" => raw} when is_binary(raw) -> raw
      %{"rendered" => rendered} when is_binary(rendered) -> rendered
      value when is_binary(value) -> value
      _other -> ""
    end
  end

  defp content_value(post) do
    case post["content"] do
      %{"rendered" => rendered} when is_binary(rendered) -> rendered
      _other -> ""
    end
  end

  defp plain_text(nil), do: nil

  defp plain_text(value) do
    value
    |> to_string()
    |> String.replace(~r/<[^>]*>/u, " ")
    |> decode_entities()
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp decode_entities(value) do
    value
    |> String.replace("&nbsp;", " ")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#039;", "'")
    |> String.replace("&apos;", "'")
  end

  defp compact(map),
    do: Map.reject(map, fn {_key, value} -> value in [nil, "", []] end)

  defp filename(url) do
    url
    |> URI.parse()
    |> Map.get(:path)
    |> case do
      nil -> nil
      path -> Path.basename(path)
    end
  end

  defp iso_datetime(nil), do: nil

  defp iso_datetime(value) do
    case parse_wordpress_datetime(value) do
      {:ok, datetime} -> DateTime.to_iso8601(datetime)
      _other -> nil
    end
  end

  defp parse_wordpress_datetime(value) do
    DateTime.from_iso8601(value <> "Z")
    |> case do
      {:ok, datetime, 0} -> {:ok, datetime}
      _other -> :error
    end
  end

  defp put_ids(params, _key, []), do: params
  defp put_ids(params, key, ids), do: Keyword.put(params, key, Enum.join(ids, ","))

  defp put_source_item_ids(params, ids) do
    case list_value(ids) do
      [] -> params
      values -> Keyword.put(params, :include, Enum.join(values, ","))
    end
  end

  defp put_date_range(params, year) when year in [nil, ""], do: params

  defp put_date_range(params, year) do
    year = String.to_integer(to_string(year))

    params
    |> Keyword.put(:after, "#{year}-01-01T00:00:00Z")
    |> Keyword.put(:before, "#{year + 1}-01-01T00:00:00Z")
  end

  defp put_modified_range(params, after_value, before_value) do
    params
    |> maybe_put(:modified_after, after_value)
    |> maybe_put(:modified_before, before_value)
  end

  defp maybe_put(params, _key, value) when value in [nil, ""], do: params
  defp maybe_put(params, key, value), do: Keyword.put(params, key, value)

  defp order_by(selection) do
    if value(selection, "modified_after") || value(selection, "modified_before"),
      do: "modified",
      else: "id"
  end

  defp invalid_year?(year) when year in [nil, ""], do: false
  defp invalid_year?(year), do: not Regex.match?(~r/^\d{4}$/, to_string(year))

  defp list_value(nil), do: []
  defp list_value(""), do: []
  defp list_value(value) when is_list(value), do: Enum.reject(value, &(&1 in [nil, ""]))
  defp list_value(value), do: [value]

  defp page_size(connection) do
    case setting(connection, "page_size", @default_page_size) do
      size when is_integer(size) -> min(max(size, 1), 100)
      _other -> @default_page_size
    end
  end

  defp default_locale(connection), do: setting(connection, "default_locale", "und")

  defp request_context(%{
         credentials: %{"username" => username, "application_password" => password}
       })
       when is_binary(username) and username != "" and is_binary(password) and password != "",
       do: "edit"

  defp request_context(_connection), do: "view"

  defp client(connection), do: setting(connection, :client, Client)

  defp setting(%{settings: settings}, key, default) when is_map(settings),
    do: Map.get(settings, key, Map.get(settings, to_string(key), default))

  defp setting(_connection, _key, default), do: default

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, String.to_atom(key), default))

  defp blog_mapping do
    %{
      "title" => "fields.title",
      "slug" => "fields.slug",
      "excerpt" => "fields.excerpt",
      "body" => "fields.body",
      "canonical_url" => "fields.canonical_url",
      "published_at" => "fields.published_at",
      "modified_at" => "fields.modified_at",
      "author" => "fields.author",
      "categories" => "fields.categories",
      "tags" => "fields.tags",
      "featured_image" => "fields.featured_image"
    }
  end
end
