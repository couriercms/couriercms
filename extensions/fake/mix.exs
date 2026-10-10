defmodule CourierCMSFake.MixProject do
  use Mix.Project

  def project do
    [
      app: :couriercms_fake,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: [{:couriercms_extension_sdk, path: "../sdk"}]
    ]
  end

  def application do
    [mod: {CourierCMSExtension.Fake.Application, []}, extra_applications: [:logger]]
  end
end
