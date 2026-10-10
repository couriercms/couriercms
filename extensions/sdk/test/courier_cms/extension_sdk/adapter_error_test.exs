defmodule CourierCMS.ExtensionSDK.AdapterErrorTest do
  use ExUnit.Case, async: true

  alias CourierCMS.ExtensionSDK.AdapterError

  test "captures normalized retry guidance without raw response data" do
    error =
      AdapterError.new(:rate_limited, "Target rate limit reached",
        retryable: true,
        retry_after_ms: 5_000,
        external_code: "429"
      )

    assert error.category == :rate_limited
    assert error.retryable
    assert error.retry_after_ms == 5_000
    assert error.external_code == "429"
  end
end
