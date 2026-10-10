defmodule CourierCMS.Connections.CredentialsTest do
  use CourierCMS.DataCase, async: true

  import CourierCMS.AccountsFixtures

  alias CourierCMS.Connections
  alias CourierCMS.Repo

  test "encrypts WordPress credentials at rest" do
    scope = user_fixture() |> CourierCMS.Accounts.scope_for_user()
    secret = "abcd efgh ijkl mnop qrst uvwx"

    assert {:ok, connection} =
             Connections.create_connection(scope, %{
               "name" => "Encrypted WordPress",
               "adapter_key" => "wordpress",
               "endpoint" => "https://wordpress.example",
               "configuration" => %{"default_locale" => "en-CA"},
               "credential_values" => %{
                 "username" => "couriercms-reader",
                 "application_password" => secret
               }
             })

    assert connection.credentials == %{
             "username" => "couriercms-reader",
             "application_password" => secret
           }

    %{rows: [[ciphertext]]} =
      Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT credentials FROM connections WHERE id = $1",
        [Ecto.UUID.dump!(connection.id)]
      )

    refute ciphertext =~ secret
    refute ciphertext =~ "couriercms-reader"

    reloaded = Connections.get_connection!(scope, connection.id)
    assert reloaded.credentials["application_password"] == secret
    assert reloaded.settings["default_locale"] == "en-CA"
  end

  test "encrypts a Sanity project token at rest" do
    scope = user_fixture() |> CourierCMS.Accounts.scope_for_user()
    secret = "sanity-project-robot-token"

    assert {:ok, connection} =
             Connections.create_connection(scope, %{
               "name" => "Encrypted Sanity",
               "adapter_key" => "sanity",
               "configuration" => %{
                 "organization_id" => "org-example",
                 "project_id" => "abc123xy",
                 "dataset" => "production",
                 "api_version" => "v2026-09-24"
               },
               "credential_values" => %{"token" => secret}
             })

    assert connection.credentials == %{"token" => secret}

    %{rows: [[ciphertext]]} =
      Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT credentials FROM connections WHERE id = $1",
        [Ecto.UUID.dump!(connection.id)]
      )

    refute ciphertext =~ secret

    reloaded = Connections.get_connection!(scope, connection.id)
    assert reloaded.credentials["token"] == secret
    assert reloaded.settings["project_id"] == "abc123xy"
    assert reloaded.settings["dataset"] == "production"

    assert CourierCMS.Security.VaultRotation.rotate!() == 1

    %{rows: [[rotated_ciphertext]]} =
      Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT credentials FROM connections WHERE id = $1",
        [Ecto.UUID.dump!(connection.id)]
      )

    refute rotated_ciphertext == ciphertext
    assert Connections.get_connection!(scope, connection.id).credentials["token"] == secret
  end

  test "an administrator can set the cluster-wide Connection concurrency limit" do
    scope = user_fixture() |> CourierCMS.Accounts.scope_for_user()

    assert {:ok, connection} =
             Connections.create_connection(scope, %{
               "name" => "Rate-limited WordPress",
               "adapter_key" => "wordpress",
               "endpoint" => "https://wordpress.example"
             })

    assert {:ok, updated} = Connections.update_concurrency_limit(scope, connection, "3")
    assert updated.settings["max_concurrency"] == 3

    assert {:error, :invalid_concurrency_limit} =
             Connections.update_concurrency_limit(scope, updated, "0")
  end

  test "an administrator can rotate credentials without losing connector configuration" do
    scope = user_fixture() |> CourierCMS.Accounts.scope_for_user()

    assert {:ok, connection} =
             Connections.create_connection(scope, %{
               "name" => "Rotating WordPress",
               "adapter_key" => "wordpress",
               "endpoint" => "https://wordpress.example",
               "configuration" => %{"default_locale" => "und"},
               "credential_values" => %{
                 "username" => "old-user",
                 "application_password" => "old-password"
               }
             })

    assert {:ok, connection, connector_secret} =
             Connections.configure_connector(scope, connection)

    assert {:ok, rotated} =
             Connections.rotate_credentials(scope, connection, %{
               "username" => "new-user",
               "application_password" => "new-password"
             })

    assert rotated.credentials["username"] == "new-user"
    assert rotated.credentials["application_password"] == "new-password"
    assert rotated.credentials["connector_secret"] == connector_secret
  end
end
