defmodule CourierCMS.ExtensionSDK do
  @moduledoc """
  Public compile-time contract between CourierCMS and trusted native OTP Extensions.

  Extension projects may depend on this package. They must not depend on the
  CourierCMS Phoenix application or its internal contexts.
  """

  @version "0.1.0"

  @spec version() :: String.t()
  def version, do: @version
end
