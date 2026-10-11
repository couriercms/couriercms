defmodule CourierCMS.Assets do
  @moduledoc "Durable planning and lookup for Delivery Assets."

  import Ecto.Query

  alias CourierCMS.Assets.{DeliveryAsset, DeliveryAssetBinding, RunAsset, RunItemAsset}
  alias CourierCMS.Execution.{AssetWorker, JobArgs, RunItem}
  alias CourierCMS.ExtensionSDK.AssetDescriptor
  alias CourierCMS.Repo

  @doc """
  Persists all asset identities and item dependencies discovered in one bundle.

  The operation is idempotent and atomic. Re-reading the same item after a
  worker restart cannot create duplicate Delivery Assets, Run Assets, or
  dependency edges.
  """
  @spec plan_dependencies(RunItem.t(), [AssetDescriptor.t()], keyword()) ::
          {:ok, [RunAsset.t()]} | {:error, term()}
  def plan_dependencies(%RunItem{} = run_item, descriptors, opts \\ [])
      when is_list(descriptors) do
    schedule_jobs? = Keyword.get(opts, :schedule_jobs, true)

    Repo.transaction(fn ->
      Enum.map(descriptors, &persist_dependency!(run_item, &1, schedule_jobs?))
    end)
  end

  @spec binding(DeliveryAsset.t(), Ecto.UUID.t()) :: DeliveryAssetBinding.t() | nil
  def binding(%DeliveryAsset{id: asset_id}, destination_id) do
    Repo.get_by(DeliveryAssetBinding,
      delivery_asset_id: asset_id,
      destination_id: destination_id
    )
  end

  @spec dependencies(Ecto.UUID.t()) :: [RunItemAsset.t()]
  def dependencies(run_item_id) do
    RunItemAsset
    |> where([dependency], dependency.run_item_id == ^run_item_id)
    |> preload(run_asset: [delivery_asset: :bindings])
    |> Repo.all()
  end

  defp persist_dependency!(run_item, %AssetDescriptor{} = descriptor, schedule_jobs?) do
    asset = upsert_asset!(run_item.run.route_id, descriptor)
    asset_key = DeliveryAsset.key(asset.route_id, asset.source_asset_key, asset.variant_key)

    %RunAsset{}
    |> RunAsset.changeset(%{
      run_id: run_item.run_id,
      delivery_asset_id: asset.id,
      asset_key: asset_key
    })
    |> Repo.insert!(
      on_conflict: :nothing,
      conflict_target: [:run_id, :asset_key]
    )

    run_asset = Repo.get_by!(RunAsset, run_id: run_item.run_id, asset_key: asset_key)

    %RunItemAsset{}
    |> RunItemAsset.changeset(%{
      run_item_id: run_item.id,
      run_asset_id: run_asset.id,
      field_path: descriptor.field_path || "$assets",
      required: descriptor.required
    })
    |> Repo.insert!(
      on_conflict: :nothing,
      conflict_target: [:run_item_id, :run_asset_id, :field_path]
    )

    if schedule_jobs? and run_asset.status in [:pending, :retrying] do
      job =
        AssetWorker.new(JobArgs.put(%{"run_asset_id" => run_asset.id}),
          max_attempts: Application.fetch_env!(:couriercms, :asset_delivery_max_attempts)
        )

      case Oban.insert(job) do
        {:ok, _job} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end

    run_asset
  end

  defp upsert_asset!(route_id, descriptor) do
    %DeliveryAsset{}
    |> DeliveryAsset.changeset(%{
      route_id: route_id,
      source_asset_key: descriptor.source_key,
      variant_key: descriptor.variant_key,
      filename: descriptor.filename,
      media_type: descriptor.media_type,
      byte_size: descriptor.size,
      source_checksum: descriptor.checksum,
      metadata: descriptor.metadata
    })
    |> Repo.insert!(
      on_conflict:
        {:replace, [:filename, :media_type, :byte_size, :source_checksum, :metadata, :updated_at]},
      conflict_target: [:route_id, :source_asset_key, :variant_key],
      returning: true
    )
  end
end
