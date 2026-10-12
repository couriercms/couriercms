defmodule CourierCMSContent.MixProject do
  use Mix.Project

  def project do
    [
      app: :couriercms_content,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [mod: {CourierCMSExtension.Content.Application, []}, extra_applications: [:logger]]
  end

  defp deps do
    [{:couriercms_extension_sdk, path: "../sdk"}]
  end
end
