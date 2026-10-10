defmodule CourierCMSExtensionSDK.MixProject do
  use Mix.Project

  def project do
    [
      app: :couriercms_extension_sdk,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: [{:jason, "~> 1.2"}]
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end
end
