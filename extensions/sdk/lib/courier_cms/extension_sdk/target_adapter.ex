defmodule CourierCMS.ExtensionSDK.TargetAdapter do
  @moduledoc "Behaviour implemented by a target Adapter component."

  alias CourierCMS.ExtensionSDK.{Component, Types}

  @callback component() :: Component.t()
  @callback definition() :: map()
  @callback capabilities(Types.connection()) :: map()
  @callback idempotency_strategy() :: :deterministic_id | :recovery_lookup
  @callback test_connection(Types.connection()) :: :ok | {:error, Types.adapter_error()}
  @callback validate_projections(Types.connection(), [map()]) ::
              :ok | {:error, Types.adapter_error()}
  @callback validate_destination(Types.connection(), map()) ::
              :ok | {:error, Types.adapter_error()}
  @callback find_delivery(Types.connection(), map(), String.t()) ::
              {:ok, :not_found | %{target_reference: String.t(), ownership: map()}}
              | {:error, Types.adapter_error()}
  @callback create_delivery(Types.connection(), Types.delivery()) ::
              {:ok, %{target_reference: String.t(), ownership: map()}}
              | {:error, Types.adapter_error()}
  @callback update_delivery(Types.connection(), String.t(), Types.delivery(), map()) ::
              {:ok, %{target_reference: String.t(), ownership: map()}}
              | {:error, Types.adapter_error()}
  @callback find_asset(Types.connection(), map(), String.t()) ::
              {:ok, :not_found | %{target_reference: String.t(), ownership: map()}}
              | {:error, Types.adapter_error()}
  @callback create_asset(Types.connection(), Types.asset_delivery()) ::
              {:ok, %{target_reference: String.t(), ownership: map()}}
              | {:error, Types.adapter_error()}
  @callback update_asset(Types.connection(), String.t(), Types.asset_delivery(), map()) ::
              {:ok, %{target_reference: String.t(), ownership: map()}}
              | {:error, Types.adapter_error()}

  @optional_callbacks validate_destination: 2,
                      find_asset: 3,
                      create_asset: 2,
                      update_asset: 4
end
