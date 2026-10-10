defmodule CourierCMS.Connections.ConnectionTest do
  use ExUnit.Case, async: true

  alias CourierCMS.Connections.Connection
  alias CourierCMS.Adapters.Definition

  test "accepts a named adapter endpoint" do
    changeset =
      Connection.changeset(%Connection{}, %{
        name: "Corporate WordPress",
        adapter_key: "wordpress",
        extension_id: "com.couriercms.wordpress",
        component_id: "wordpress",
        endpoint: "https://cms.example.test",
        workspace_id: Ecto.UUID.generate()
      })

    assert changeset.valid?
  end

  test "rejects unsafe or incomplete endpoint values" do
    changeset =
      Connection.changeset(%Connection{}, %{
        name: "Corporate WordPress",
        adapter_key: "WordPress Adapter",
        endpoint: "file:///etc/passwd"
      })

    refute changeset.valid?
    assert "has invalid format" in errors_on(changeset).adapter_key
    assert "must be an absolute HTTP or HTTPS URL" in errors_on(changeset).endpoint
  end

  test "redacts encrypted credentials from inspection" do
    inspected = inspect(%Connection{credentials: "encrypted-secret"})

    refute inspected =~ "encrypted-secret"
    refute inspected =~ "credentials:"
    assert inspected =~ "..."
  end

  test "derives a Sanity endpoint and stores project settings" do
    assert {:ok, attrs} =
             Definition.prepare_connection_attrs(%{
               "name" => "Sanity target",
               "adapter_key" => "sanity",
               "configuration" => %{
                 "organization_id" => "org-example",
                 "project_id" => "abc123xy",
                 "dataset" => "production",
                 "api_version" => "v2026-09-24"
               },
               "credential_values" => %{"token" => "write-token"}
             })

    assert attrs["endpoint"] == "https://abc123xy.api.sanity.io"

    assert attrs["settings"] == %{
             "api_version" => "v2026-09-24",
             "dataset" => "production",
             "organization_id" => "org-example",
             "project_id" => "abc123xy"
           }

    assert attrs["credentials"] == %{"token" => "write-token"}
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
