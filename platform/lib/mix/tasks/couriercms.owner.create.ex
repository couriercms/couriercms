defmodule Mix.Tasks.Couriercms.Owner.Create do
  @shortdoc "Creates the first active CourierCMS workspace owner"
  @moduledoc """
  Creates the initial owner for an installation.

      mix couriercms.owner.create owner@example.com

  After creation, start CourierCMS and request a magic link from the login page.
  This task refuses to create another owner after the workspace has one.
  """

  use Mix.Task

  @impl Mix.Task
  def run([email]) do
    Mix.Task.run("app.start")

    case CourierCMS.Accounts.bootstrap_owner(email) do
      {:ok, _membership} ->
        Mix.shell().info("Owner created. Start CourierCMS and request a magic link for #{email}.")

      {:error, :owner_already_exists} ->
        Mix.raise("An owner already exists. Use the Users page to manage access.")

      {:error, reason} ->
        Mix.raise("Owner could not be created: #{inspect(reason)}")
    end
  end

  def run(_args), do: Mix.raise("Usage: mix couriercms.owner.create owner@example.com")
end
