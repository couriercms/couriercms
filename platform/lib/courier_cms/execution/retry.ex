defmodule CourierCMS.Execution.Retry do
  @moduledoc false

  def backoff(attempt, cap_seconds) do
    base = min(round(:math.pow(2, attempt)), cap_seconds)
    jitter = max(1, div(base, 4))
    max(1, base - jitter + :rand.uniform(jitter * 2 + 1) - 1)
  end

  def short_snooze, do: :rand.uniform(3)

  def after_ms(milliseconds) when is_integer(milliseconds) and milliseconds > 0 do
    base = max(1, ceil(milliseconds / 1_000))
    base + :rand.uniform(max(1, ceil(base / 4))) - 1
  end
end
