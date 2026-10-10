defmodule CourierCMS.ExtensionSDK.AdapterError do
  @moduledoc "Normalized, secret-safe failure returned by an Adapter or Processor."

  @categories [
    :authentication,
    :authorization,
    :rate_limited,
    :temporarily_unavailable,
    :timeout,
    :invalid_selection,
    :source_not_found,
    :invalid_content,
    :mapping_failed,
    :transformation_failed,
    :contract_validation_failed,
    :ownership_violation,
    :target_rejected,
    :unsupported,
    :internal
  ]

  @enforce_keys [:category, :retryable, :message]
  defstruct [:category, :retryable, :message, :external_code, :retry_after_ms]

  @type category ::
          :authentication
          | :authorization
          | :rate_limited
          | :temporarily_unavailable
          | :timeout
          | :invalid_selection
          | :source_not_found
          | :invalid_content
          | :mapping_failed
          | :transformation_failed
          | :contract_validation_failed
          | :ownership_violation
          | :target_rejected
          | :unsupported
          | :internal
  @type t :: %__MODULE__{
          category: category(),
          retryable: boolean(),
          message: String.t(),
          external_code: String.t() | nil,
          retry_after_ms: non_neg_integer() | nil
        }

  @spec new(category(), String.t(), keyword()) :: t()
  def new(category, message, opts \\ []) when category in @categories and is_binary(message) do
    %__MODULE__{
      category: category,
      message: message,
      retryable: Keyword.get(opts, :retryable, false),
      external_code: Keyword.get(opts, :external_code),
      retry_after_ms: Keyword.get(opts, :retry_after_ms)
    }
  end
end
