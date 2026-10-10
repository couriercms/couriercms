defmodule CourierCMS.DeploymentTest do
  use ExUnit.Case, async: true

  alias CourierCMS.Deployment

  @base_options [
    queues: [route_planning: 2, delivery: 10, webhooks: 5, maintenance: 1],
    plugins: [
      {Oban.Plugins.Cron,
       crontab: [{"* * * * *", CourierCMS.Execution.ScheduleWorker, queue: :maintenance}]}
    ]
  ]

  test "all role preserves the local combined-process defaults" do
    options = Deployment.oban_options!(@base_options, :all, %{})

    assert options[:queues] == @base_options[:queues]
    assert options[:plugins] == @base_options[:plugins]
  end

  test "web role retains Oban for insertion but disables execution and plugins" do
    options = Deployment.oban_options!(@base_options, :web, %{})

    assert options[:queues] == false
    assert options[:plugins] == false
  end

  test "worker role accepts an explicit queue allocation and disables scheduling by default" do
    options =
      Deployment.oban_options!(@base_options, :worker, %{
        "COURIERCMS_QUEUES" => "delivery:24, route_planning:3"
      })

    assert options[:queues] == [delivery: 24, route_planning: 3]
    assert options[:plugins] == false
  end

  test "one worker can explicitly own periodic scheduling" do
    options =
      Deployment.oban_options!(@base_options, :worker, %{
        "COURIERCMS_SCHEDULER_ENABLED" => "true"
      })

    assert [{Oban.Plugins.Cron, cron_options}] = options[:plugins]

    assert {"* * * * *", CourierCMS.Execution.ScheduleWorker, queue: :maintenance} in cron_options[
             :crontab
           ]
  end

  test "shutdown grace period is configurable for executing nodes" do
    options =
      Deployment.oban_options!(@base_options, :worker, %{
        "COURIERCMS_SHUTDOWN_GRACE_PERIOD_MS" => "45000"
      })

    assert options[:shutdown_grace_period] == 45_000
  end

  test "queue names are allowlisted without creating runtime atoms" do
    assert_raise ArgumentError, ~r/unsupported queue/, fn ->
      Deployment.parse_queues!("arbitrary:2")
    end
  end

  test "queue configuration rejects duplicates and invalid limits" do
    assert_raise ArgumentError, ~r/duplicate/, fn ->
      Deployment.parse_queues!("delivery:2,delivery:3")
    end

    assert_raise ArgumentError, ~r/positive integer/, fn ->
      Deployment.parse_queues!("delivery:0")
    end
  end
end
