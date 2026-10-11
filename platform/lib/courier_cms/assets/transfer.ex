defmodule CourierCMS.Assets.Transfer do
  @moduledoc "Materializes one bounded asset stream for a single target attempt."

  alias CourierCMS.ExtensionSDK.{AdapterError, AssetContent, AssetDescriptor}

  @chunk_size 64 * 1_024

  @spec with_materialized(AssetContent.t(), AssetDescriptor.t(), (AssetContent.t() -> term())) ::
          term()
  def with_materialized(%AssetContent{} = content, %AssetDescriptor{} = descriptor, callback)
      when is_function(callback, 1) do
    directory = temporary_directory()
    File.mkdir_p!(directory)
    path = Path.join(directory, "#{Ecto.UUID.generate()}.asset")

    try do
      with {:ok, metadata} <- write_stream(path, content.chunks),
           :ok <- verify_size(metadata.byte_size, content.byte_size, descriptor.size),
           :ok <- verify_checksum(metadata.checksum, content.checksum, descriptor.checksum) do
        callback.(%AssetContent{
          chunks: File.stream!(path, @chunk_size, []),
          byte_size: metadata.byte_size,
          checksum: metadata.checksum,
          media_type: content.media_type || descriptor.media_type
        })
      end
    after
      File.rm(path)
    end
  end

  def with_materialized(_content, _descriptor, _callback),
    do:
      {:error,
       AdapterError.new(:invalid_content, "Source Adapter returned invalid asset content")}

  defp write_stream(path, chunks) do
    max_bytes = Application.fetch_env!(:couriercms, :max_asset_bytes)

    try do
      File.open(path, [:write, :binary, :exclusive], fn io ->
        chunks
        |> Enum.reduce_while({0, :crypto.hash_init(:sha256)}, fn
          chunk, {size, hash} when is_binary(chunk) ->
            next_size = size + byte_size(chunk)

            if next_size <= max_bytes do
              :ok = IO.binwrite(io, chunk)
              {:cont, {next_size, :crypto.hash_update(hash, chunk)}}
            else
              {:halt, {:error, :too_large}}
            end

          _chunk, _state ->
            {:halt, {:error, :invalid_chunk}}
        end)
      end)
      |> case do
        {:ok, {:error, :too_large}} ->
          {:error,
           AdapterError.new(:invalid_content, "Delivery Asset exceeds the configured size limit")}

        {:ok, {:error, :invalid_chunk}} ->
          {:error,
           AdapterError.new(:invalid_content, "Source Adapter returned a non-binary asset chunk")}

        {:ok, {byte_size, hash}} ->
          checksum = hash |> :crypto.hash_final() |> Base.encode16(case: :lower)
          {:ok, %{byte_size: byte_size, checksum: "sha256:#{checksum}"}}

        {:error, _reason} ->
          {:error,
           AdapterError.new(:temporarily_unavailable, "CourierCMS could not buffer the asset",
             retryable: true
           )}
      end
    rescue
      _exception ->
        {:error,
         AdapterError.new(
           :temporarily_unavailable,
           "Source Adapter asset stream could not be read",
           retryable: true
         )}
    catch
      _kind, _reason ->
        {:error,
         AdapterError.new(:temporarily_unavailable, "Source Adapter asset stream failed",
           retryable: true
         )}
    end
  end

  defp verify_size(actual, declared, descriptor_size) do
    expected = Enum.reject([declared, descriptor_size], &is_nil/1)

    if Enum.all?(expected, &(&1 == actual)) do
      :ok
    else
      {:error,
       AdapterError.new(:invalid_content, "Delivery Asset size does not match its descriptor")}
    end
  end

  defp verify_checksum(actual, content_checksum, descriptor_checksum) do
    expected =
      [content_checksum, descriptor_checksum]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&normalize_checksum/1)

    if Enum.all?(expected, &(&1 == normalize_checksum(actual))) do
      :ok
    else
      {:error,
       AdapterError.new(:invalid_content, "Delivery Asset checksum does not match its descriptor")}
    end
  end

  defp normalize_checksum(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace_prefix("sha256:", "")
  end

  defp temporary_directory do
    Application.get_env(:couriercms, :asset_temp_dir) ||
      Path.join(System.tmp_dir!(), "couriercms-assets")
  end
end
