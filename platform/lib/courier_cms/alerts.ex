defmodule CourierCMS.Alerts do
  @moduledoc "Terminal delivery failure notifications with safe operational context."

  import Ecto.Query
  import Swoosh.Email, except: [from: 2]

  alias CourierCMS.Accounts.User
  alias CourierCMS.Execution.{FailureAlertWorker, RunItem}
  alias CourierCMS.Mailer
  alias CourierCMS.Repo
  alias CourierCMS.Workspaces.Membership

  def enqueue_terminal_failure(%RunItem{} = run_item) do
    if Application.get_env(:couriercms, :failure_email_alerts, true) do
      case run_item.id
           |> then(
             &FailureAlertWorker.new(CourierCMS.Execution.JobArgs.put(%{"run_item_id" => &1}))
           )
           |> Oban.insert() do
        {:ok, _job} ->
          :ok

        {:error, _reason} ->
          :telemetry.execute([:couriercms, :alert, :enqueue_failed], %{count: 1}, %{})
      end
    end

    :ok
  end

  def deliver_terminal_failure(run_item_id) do
    run_item =
      RunItem
      |> Repo.get!(run_item_id)
      |> Repo.preload(run: :route)

    recipients =
      from(membership in Membership,
        join: user in User,
        on: user.id == membership.user_id,
        where:
          membership.workspace_id == ^run_item.run.route.workspace_id and
            membership.status == :active and membership.role in [:owner, :admin],
        select: user.email,
        distinct: true
      )
      |> Repo.all()

    result =
      Enum.reduce_while(recipients, :ok, fn recipient, :ok ->
        case recipient |> failure_email(run_item) |> Mailer.deliver() do
          {:ok, _metadata} -> {:cont, :ok}
          {:error, _reason} -> {:halt, {:error, "Failure alert email could not be delivered"}}
        end
      end)

    if result == :ok do
      :telemetry.execute(
        [:couriercms, :alert, :delivered],
        %{count: length(recipients)},
        %{kind: :terminal_delivery_failure}
      )
    end

    result
  end

  defp failure_email(recipient, run_item) do
    run_url = CourierCMSWeb.Endpoint.url() <> "/runs/#{run_item.run_id}"

    new()
    |> to(recipient)
    |> Swoosh.Email.from({
      System.get_env("MAIL_FROM_NAME", "CourierCMS"),
      System.get_env("MAIL_FROM_ADDRESS", "couriercms@localhost")
    })
    |> subject("CourierCMS delivery failed")
    |> text_body("""
    CourierCMS could not deliver an item after its configured attempts.

    Route: #{run_item.run.route.name}
    Run: #{run_item.run_id}
    Source item: #{run_item.source_item_key}
    Locale: #{run_item.locale_key}
    Error category: #{run_item.error_category || "unknown"}

    Review and retry the delivery in CourierCMS:
    #{run_url}
    """)
  end
end
