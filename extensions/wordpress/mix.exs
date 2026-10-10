defmodule CourierCMSWordPress.MixProject do
  use Mix.Project

  def project do
    [
      app: :couriercms_wordpress,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [mod: {CourierCMSExtension.WordPress.Application, []}, extra_applications: [:logger]]
  end

  defp deps do
    [
      {:couriercms_extension_sdk, path: "../sdk"},
      {:req, "~> 0.7"},
      {:jason, "~> 1.2"},
      {:plug, "~> 1.18", only: :test}
    ]
  end
end
