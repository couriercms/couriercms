defmodule CourierCMSExtension.Fake.Source do
  @moduledoc "A deterministic in-process source Adapter for the walking skeleton."

  @behaviour CourierCMS.ExtensionSDK.SourceAdapter

  alias CourierCMS.ExtensionSDK.{
    AdapterError,
    AssetContent,
    AssetDescriptor,
    Component,
    ContentBundle,
    ContentNode,
    SourceIdentity
  }

  @impl true
  def component do
    Component.new!(
      extension_id: "com.couriercms.fake",
      component_id: "fake_source",
      kind: :adapter,
      version: "0.1.0",
      capabilities: [
        :source,
        :connection_test,
        :native_filtering,
        :incremental_changes,
        :authoritative_change_token,
        :assets
      ]
    )
  end

  @impl true
  def definition do
    %{
      key: "fake_source",
      label: "Fake source",
      description: "Deterministic development source Adapter",
      connection: %{
        endpoint: %{mode: :input, label: "Endpoint", placeholder: "https://fake-source.example"},
        fields: []
      },
      source: %{
        content_label: "content items",
        description: "Every matching root item is delivered independently.",
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
      }
    }
  end

  @posts [
    %{
      id: "101",
      revision: "7",
      title: "Reliable content delivery with CourierCMS",
      slug: "reliable-content-delivery",
      excerpt: "Why delivery history and idempotency matter.",
      body: "<p>CMS integrations should be observable, replayable, and safe.</p>",
      category: "Engineering",
      tags: ["elixir", "architecture"],
      author: %{"source_id" => "12", "name" => "Maya Chen"},
      published_at: ~U[2026-02-12 14:00:00Z],
      modified_at: ~U[2026-02-14 10:30:00Z],
      featured_image: %{
        "source_id" => "501",
        "filename" => "delivery-pipeline.jpg",
        "media_type" => "image/jpeg",
        "alt" => "A content delivery pipeline"
      }
    },
    %{
      id: "102",
      revision: "3",
      title: "Designing bounded content graphs",
      slug: "bounded-content-graphs",
      excerpt: "Aggregate references without crawling an entire CMS.",
      body: "<p>Explicit relationship rules keep content aggregation predictable.</p>",
      category: "Engineering",
      tags: ["content", "architecture"],
      author: %{"source_id" => "18", "name" => "Noah Williams"},
      published_at: ~U[2026-05-04 09:15:00Z],
      modified_at: ~U[2026-05-05 16:45:00Z],
      featured_image: nil
    },
    %{
      id: "103",
      revision: "11",
      title: "Operating CMS integrations at scale",
      slug: "operating-cms-integrations",
      excerpt: "Practical monitoring for content platform teams.",
      body: "<p>Item-level status makes partial failures understandable.</p>",
      category: "Engineering",
      tags: ["operations", "elixir"],
      author: %{"source_id" => "12", "name" => "Maya Chen"},
      published_at: ~U[2025-11-20 17:00:00Z],
      modified_at: ~U[2026-01-08 11:20:00Z],
      featured_image: %{
        "source_id" => "503",
        "filename" => "run-history.png",
        "media_type" => "image/png",
        "alt" => "Run history dashboard"
      }
    },
    %{
      id: "201",
      revision: "4",
      title: "Autumn campaign launch",
      slug: "autumn-campaign",
      excerpt: "A Marketing post excluded by the demo Route.",
      body: "<p>This post demonstrates source-side category filtering.</p>",
      category: "Marketing",
      tags: ["campaign"],
      author: %{"source_id" => "21", "name" => "Sofia Patel"},
      published_at: ~U[2026-09-01 12:00:00Z],
      modified_at: ~U[2026-09-02 12:00:00Z],
      featured_image: nil
    }
  ]

  @impl true
  def capabilities(_connection) do
    %{
      "source" => true,
      "connection_test" => true,
      "selection_preview" => true,
      "native_filtering" => true,
      "incremental_changes" => true,
      "authoritative_change_token" => true,
      "locales" => true,
      "revisions" => true
    }
  end

  @impl true
  def test_connection(connection) do
    if setting(connection, "simulate_connection_failure", false) do
      {:error, AdapterError.new(:authentication, "Fake source rejected the connection")}
    else
      :ok
    end
  end

  @impl true
  def enumerate(connection, selection, cursor) do
    failure_cursor = setting(connection, "fail_enumeration_at_cursor", nil)

    if !is_nil(failure_cursor) && failure_cursor == cursor do
      {:error,
       AdapterError.new(:temporarily_unavailable, "Fake source enumeration failed",
         retryable: true
       )}
    else
      enumerate_available(connection, selection, cursor)
    end
  end

  defp enumerate_available(
         %{settings: %{"synthetic_item_count" => total}} = connection,
         _selection,
         cursor
       )
       when is_integer(total) and total > 0 do
    page_size = min(setting(connection, "synthetic_page_size", 500), 1_000)
    offset = cursor || 0

    items =
      offset
      |> Range.new(min(offset + page_size - 1, total - 1))
      |> Enum.map(&synthetic_identity/1)

    next_cursor = if offset + page_size < total, do: offset + page_size, else: nil
    {:ok, %{items: if(offset >= total, do: [], else: items), cursor: next_cursor}}
  end

  defp enumerate_available(connection, selection, cursor) do
    page_size = 2
    offset = cursor || 0
    matching = connection |> posts() |> Enum.filter(&matches?(&1, selection))

    items =
      matching
      |> Enum.slice(offset, page_size)
      |> Enum.map(&identity/1)

    next_cursor = if offset + page_size < length(matching), do: offset + page_size, else: nil
    {:ok, %{items: items, cursor: next_cursor}}
  end

  @impl true
  def changes_since(connection, selection, checkpoint, cursor) do
    if setting(connection, "reject_incremental", false) do
      {:error, AdapterError.new(:invalid_selection, "Fake source rejected incremental filters")}
    else
      selection =
        selection
        |> Map.put("modified_after", checkpoint["after"])
        |> Map.put("modified_before", checkpoint["before"])

      enumerate(connection, selection, cursor)
    end
  end

  @impl true
  def read_root(connection, %SourceIdentity{} = identity, _aggregation_rules) do
    cond do
      identity.item_key in setting(connection, "fail_read_for", []) ->
        {:error, AdapterError.new(:temporarily_unavailable, "Fake source read was not expected")}

      is_integer(setting(connection, "synthetic_item_count", nil)) ->
        content_bundle(synthetic_node(identity))

      true ->
        read_fixture_root(connection, identity)
    end
  end

  @impl true
  def read_asset(connection, %AssetDescriptor{source_key: source_key} = descriptor) do
    if source_key in setting(connection, "fail_asset_for", []) do
      {:error,
       AdapterError.new(:temporarily_unavailable, "Fake asset read failed", retryable: true)}
    else
      version =
        connection
        |> setting("asset_content_versions", %{})
        |> Map.get(source_key, "v1")

      content = "fake-asset:#{source_key}:#{descriptor.variant_key}:#{version}"

      {:ok,
       %AssetContent{
         chunks: [content],
         byte_size: byte_size(content),
         checksum: Base.encode16(:crypto.hash(:sha256, content), case: :lower),
         media_type: descriptor.media_type || "application/octet-stream"
       }}
    end
  end

  defp read_fixture_root(connection, identity) do
    case Enum.find(
           posts(connection),
           &(&1.id == identity.item_key && &1.revision == identity.revision_key)
         ) do
      nil ->
        {:error, AdapterError.new(:source_not_found, "Fake source item no longer exists")}

      post ->
        normalized_identity = identity(post)

        root = %ContentNode{
          identity: normalized_identity,
          source_type: "post",
          name: post.title,
          path: "/posts/#{post.slug}",
          fields: %{
            "title" => post.title,
            "slug" => post.slug,
            "excerpt" => post.excerpt,
            "body" => %{"format" => "html", "value" => post.body},
            "canonical_url" => "https://source.example/posts/#{post.slug}",
            "published_at" => DateTime.to_iso8601(post.published_at),
            "modified_at" => DateTime.to_iso8601(post.modified_at),
            "author" => post.author,
            "categories" => [
              %{
                "source_id" => String.downcase(post.category),
                "name" => post.category,
                "slug" => String.downcase(post.category)
              }
            ],
            "tags" => Enum.map(post.tags, &%{"source_id" => &1, "name" => &1, "slug" => &1}),
            "featured_image" => post.featured_image
          },
          metadata: %{"adapter" => "fake_source"}
        }

        content_bundle(root)
    end
  end

  defp synthetic_identity(index) do
    {:ok, identity} =
      SourceIdentity.new(%{
        item_key: "synthetic-#{index}",
        locale_key: "en",
        revision_key: "1",
        state: :published,
        modified_at: ~U[2026-01-01 00:00:00Z],
        change_token: "synthetic-#{index}-1"
      })

    identity
  end

  defp synthetic_node(identity) do
    %ContentNode{
      identity: identity,
      source_type: "synthetic",
      name: identity.item_key,
      path: "/synthetic/#{identity.item_key}",
      fields: %{"title" => identity.item_key, "body" => "Synthetic load-test content"},
      metadata: %{"adapter" => "fake_source", "synthetic" => true}
    }
  end

  defp content_bundle(%ContentNode{} = root) do
    featured_image = root.fields["featured_image"]

    assets =
      if is_map(featured_image) do
        [
          %AssetDescriptor{
            source_key: featured_image["source_id"],
            field_path: "fields.featured_image",
            filename: featured_image["filename"],
            media_type: featured_image["media_type"],
            required: true,
            retrieval: %{"kind" => "fake"},
            metadata: Map.take(featured_image, ["alt"])
          }
        ]
      else
        []
      end

    ContentBundle.new(%{
      root: root,
      assets: assets,
      metadata: %{"adapter" => "fake_source"}
    })
  end

  defp identity(post) do
    {:ok, identity} =
      SourceIdentity.new(%{
        item_key: post.id,
        locale_key: "en-CA",
        revision_key: post.revision,
        state: :published,
        modified_at: post.modified_at,
        change_token: "#{post.id}:#{post.revision}"
      })

    identity
  end

  defp matches?(post, selection) do
    category = value(selection, "category")
    year = value(selection, "published_year")
    tags = value(selection, "tags", [])
    source_item_ids = value(selection, "source_item_ids", [])
    modified_after = parse_datetime(value(selection, "modified_after"))
    modified_before = parse_datetime(value(selection, "modified_before"))

    category_matches =
      blank?(category) || String.downcase(category) == String.downcase(post.category)

    year_matches = blank?(year) || to_string(post.published_at.year) == to_string(year)
    tags_match = tags == [] || Enum.any?(List.wrap(tags), &(&1 in post.tags))

    item_matches = source_item_ids == [] || post.id in Enum.map(source_item_ids, &to_string/1)

    modified_matches =
      (is_nil(modified_after) || DateTime.after?(post.modified_at, modified_after)) &&
        (is_nil(modified_before) || DateTime.before?(post.modified_at, modified_before))

    category_matches && year_matches && tags_match && item_matches && modified_matches
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _other -> nil
    end
  end

  defp blank?(value), do: value in [nil, "", []]

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, String.to_atom(key), default))

  defp setting(connection, key, default) do
    settings = Map.get(connection, :settings, %{})
    Map.get(settings, key, default)
  end

  defp posts(connection) do
    revision_overrides = setting(connection, "revision_overrides", %{})
    title_overrides = setting(connection, "title_overrides", %{})
    modified_at_overrides = setting(connection, "modified_at_overrides", %{})
    featured_image_overrides = setting(connection, "featured_image_overrides", %{})

    Enum.map(@posts, fn post ->
      post
      |> Map.put(:revision, Map.get(revision_overrides, post.id, post.revision))
      |> Map.put(:title, Map.get(title_overrides, post.id, post.title))
      |> Map.put(
        :featured_image,
        Map.get(featured_image_overrides, post.id, post.featured_image)
      )
      |> Map.put(
        :modified_at,
        modified_at_override(modified_at_overrides, post.id, post.modified_at)
      )
    end)
  end

  defp modified_at_override(overrides, id, default) do
    case Map.get(overrides, id, default) do
      %DateTime{} = datetime -> datetime
      value when is_binary(value) -> parse_datetime(value) || default
      _other -> default
    end
  end

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
