defmodule CourierCMS.Transport.ContentBundleValidator do
  @moduledoc "Validates generic ContentBundle limits before mapping or delivery."

  alias CourierCMS.ExtensionSDK.{AdapterError, ContentBundle}

  @spec validate(ContentBundle.t()) :: :ok | {:error, AdapterError.t()}
  def validate(%ContentBundle{} = bundle) do
    limits = [
      max_nodes: Application.fetch_env!(:couriercms, :max_content_bundle_nodes),
      max_relationships: Application.fetch_env!(:couriercms, :max_content_bundle_relationships),
      max_assets: Application.fetch_env!(:couriercms, :max_content_bundle_assets)
    ]

    case ContentBundle.validate(bundle, limits) do
      :ok ->
        :ok

      {:error, errors} ->
        {:error,
         AdapterError.new(
           :invalid_content,
           "Source Content Bundle is invalid: #{Enum.join(errors, "; ")}"
         )}
    end
  end

  def validate(_bundle) do
    {:error,
     AdapterError.new(:invalid_content, "Source Adapter returned an invalid Content Bundle")}
  end
end
