defmodule CourierCMS.Extensions.Package do
  @moduledoc false

  alias CourierCMS.ExtensionSDK.{Component, Manifest}
  alias CourierCMS.Extensions.{ComponentEntry, LoadedExtension}

  defmodule Candidate do
    @moduledoc false
    @enforce_keys [:path, :manifest, :checksum]
    defstruct @enforce_keys
  end

  @manifest_file "couriercms-extension.json"
  @checksums_file "CHECKSUMS"
  @signature_file "SIGNATURE"

  def inspect(package_path, opts) do
    with {:ok, verified} <- verify(package_path, opts) do
      {:ok,
       %Candidate{
         path: package_path,
         manifest: verified.manifest,
         checksum: verified.package_checksum
       }}
    end
  end

  def activate(%Candidate{} = candidate, opts) do
    with {:ok, verified} <- verify(candidate.path, opts),
         :ok <- same_candidate(candidate, verified),
         {:ok, cache_path} <- extract(verified, opts),
         {:ok, loaded} <- load_application(verified, cache_path) do
      {:ok, loaded}
    end
  end

  defp verify(package_path, opts) do
    with {:ok, stat} <- File.stat(package_path),
         :ok <- limit(stat.size, opts.max_package_bytes, "compressed package"),
         {:ok, entries} <- archive_entries(package_path),
         :ok <- validate_archive_entries(entries, opts),
         {:ok, extracted} <- extract_to_memory(package_path),
         {:ok, files} <- normalize_extracted(extracted),
         {:ok, manifest} <- decode_manifest(files),
         :ok <- validate_layout(files, manifest),
         :ok <- verify_checksums(files),
         :ok <- verify_signature(files, opts),
         :ok <- verify_compatibility(manifest) do
      {:ok,
       %{
         manifest: manifest,
         files: files,
         package_path: package_path,
         package_checksum: sha256_file!(package_path)
       }}
    else
      {:error, reason} -> {:error, format_reason(reason)}
    end
  rescue
    error -> {:error, Exception.message(error)}
  catch
    kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
  end

  defp archive_entries(package_path) do
    case :zip.list_dir(String.to_charlist(package_path)) do
      {:ok, entries} -> {:ok, Enum.reject(entries, &match?({:zip_comment, _}, &1))}
      {:error, reason} -> {:error, "cannot read ZIP directory: #{inspect(reason)}"}
    end
  end

  defp validate_archive_entries(entries, opts) do
    with :ok <- limit(length(entries), opts.max_entries, "archive entry count") do
      Enum.reduce_while(entries, {:ok, {MapSet.new(), 0}}, fn entry, {:ok, {names, total}} ->
        with {:ok, name, size, type} <- archive_entry(entry),
             :ok <- safe_path(name, type),
             false <- MapSet.member?(names, String.downcase(name)),
             :ok <- limit(total + size, opts.max_uncompressed_bytes, "uncompressed package") do
          {:cont, {:ok, {MapSet.put(names, String.downcase(name)), total + size}}}
        else
          true -> {:halt, {:error, "archive contains duplicate normalized paths"}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, _summary} -> :ok
        error -> error
      end
    end
  end

  defp archive_entry({:zip_file, name, info, _comment, _offset, _compressed_size}) do
    type = elem(info, 2)
    size = elem(info, 1)

    if type in [:regular, :directory] and is_integer(size) and size >= 0 do
      {:ok, List.to_string(name), size, type}
    else
      {:error, "archive contains an unsupported entry type"}
    end
  end

  defp archive_entry(_entry), do: {:error, "archive contains an unknown entry"}

  defp safe_path(name, type) do
    parts = String.split(name, "/", trim: true)
    canonical = Enum.join(parts, "/")
    expected = if type == :directory, do: canonical <> "/", else: canonical

    cond do
      not String.valid?(name) ->
        {:error, "archive path is not valid UTF-8"}

      name == "" or parts == [] or byte_size(name) > 512 ->
        {:error, "archive path is empty or too long"}

      String.contains?(name, "\\") ->
        {:error, "archive paths must use forward slashes"}

      Path.type(name) != :relative ->
        {:error, "archive contains an absolute path"}

      Enum.any?(parts, &(&1 in [".", ".."])) ->
        {:error, "archive contains path traversal"}

      String.contains?(hd(parts), ":") ->
        {:error, "archive contains a drive-qualified path"}

      expected != name ->
        {:error, "archive path is not canonical"}

      true ->
        :ok
    end
  end

  defp extract_to_memory(package_path) do
    case :zip.extract(String.to_charlist(package_path), [:memory]) do
      {:ok, files} -> {:ok, files}
      {:error, reason} -> {:error, "cannot extract ZIP: #{inspect(reason)}"}
    end
  end

  defp normalize_extracted(extracted) do
    files =
      Map.new(extracted, fn {name, contents} ->
        {List.to_string(name), IO.iodata_to_binary(contents)}
      end)

    {:ok, files}
  rescue
    _error -> {:error, "archive contains an unsupported extracted entry"}
  end

  defp decode_manifest(files) do
    with {:ok, json} <- Map.fetch(files, @manifest_file),
         {:ok, attrs} <- Jason.decode(json),
         {:ok, manifest} <- Manifest.parse(attrs) do
      {:ok, manifest}
    else
      :error -> {:error, "#{@manifest_file} is missing"}
      {:error, %Jason.DecodeError{}} -> {:error, "#{@manifest_file} is not valid JSON"}
      {:error, errors} when is_list(errors) -> {:error, Enum.join(errors, "; ")}
    end
  end

  defp validate_layout(files, manifest) do
    root = "lib/#{manifest.otp_application}-#{manifest.version}"
    app_file = "#{root}/ebin/#{manifest.otp_application}.app"
    paths = Map.keys(files)

    cond do
      not Map.has_key?(files, @checksums_file) ->
        {:error, "#{@checksums_file} is missing"}

      not Map.has_key?(files, app_file) ->
        {:error, "OTP application metadata is missing at #{app_file}"}

      not Enum.any?(paths, &String.starts_with?(&1, "#{root}/ebin/")) ->
        {:error, "package does not contain compiled BEAM files"}

      Enum.any?(paths, &source_file?/1) ->
        {:error, "source files are not allowed in production Extension packages"}

      Enum.any?(paths, &(not allowed_path?(&1, root))) ->
        {:error, "package contains files outside its declared OTP application"}

      true ->
        :ok
    end
  end

  defp source_file?(path), do: Path.extname(path) in [".ex", ".exs"]

  defp allowed_path?(path, root) do
    path in [@manifest_file, @checksums_file, @signature_file] or
      String.starts_with?(path, "#{root}/ebin/") or
      String.starts_with?(path, "#{root}/priv/")
  end

  defp verify_checksums(files) do
    with {:ok, raw} <- Map.fetch(files, @checksums_file),
         {:ok, declared} <- parse_checksums(raw) do
      actual_paths =
        files
        |> Map.keys()
        |> Enum.reject(&(&1 in [@checksums_file, @signature_file]))
        |> Enum.sort()

      cond do
        Enum.sort(Map.keys(declared)) != actual_paths ->
          {:error, "CHECKSUMS must list every package file exactly once"}

        Enum.any?(declared, fn {path, expected} ->
          sha256(Map.fetch!(files, path)) != expected
        end) ->
          {:error, "package checksum verification failed"}

        true ->
          :ok
      end
    else
      :error -> {:error, "#{@checksums_file} is missing"}
      error -> error
    end
  end

  defp parse_checksums(raw) do
    lines = String.split(raw, ~r/\r?\n/, trim: true)

    Enum.reduce_while(lines, {:ok, %{}}, fn line, {:ok, checksums} ->
      case Regex.run(~r/^([0-9a-f]{64})  ([^\r\n]+)$/, line, capture: :all_but_first) do
        [digest, path] ->
          with :ok <- safe_path(path, :regular),
               false <- Map.has_key?(checksums, path) do
            {:cont, {:ok, Map.put(checksums, path, digest)}}
          else
            true -> {:halt, {:error, "CHECKSUMS contains a duplicate path"}}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        _other ->
          {:halt, {:error, "CHECKSUMS has an invalid line"}}
      end
    end)
  end

  defp verify_signature(files, opts) do
    case Map.fetch(files, @signature_file) do
      :error when opts.signature_policy == :required ->
        {:error, "package signature is required"}

      :error ->
        :ok

      {:ok, signature_json} ->
        with {:ok, signature} <- Jason.decode(signature_json),
             %{"algorithm" => "ed25519", "keyId" => key_id, "signature" => encoded} <- signature,
             {:ok, public_key} <- Map.fetch(opts.trusted_keys, key_id),
             {:ok, decoded} <- Base.decode64(encoded),
             true <-
               :crypto.verify(
                 :eddsa,
                 :none,
                 Map.fetch!(files, @checksums_file),
                 decoded,
                 [public_key, :ed25519]
               ) do
          :ok
        else
          :error -> {:error, "package signature key is not trusted"}
          false -> {:error, "package signature verification failed"}
          _other -> {:error, "SIGNATURE must be valid Ed25519 signature JSON"}
        end
    end
  end

  defp verify_compatibility(manifest) do
    versions = [
      {"SDK", CourierCMS.ExtensionSDK.version(), manifest.sdk_requirement},
      {"CourierCMS", couriercms_version(), manifest.couriercms_requirement},
      {"Elixir", System.version(), manifest.elixir_requirement},
      {"OTP", otp_version(), manifest.otp_requirement}
    ]

    case Enum.find(versions, fn {_name, version, requirement} ->
           not Version.match?(version, requirement)
         end) do
      nil ->
        :ok

      {name, version, requirement} ->
        {:error, "#{name} #{version} does not satisfy #{requirement}"}
    end
  end

  defp couriercms_version do
    :couriercms
    |> Application.spec(:vsn)
    |> to_string()
  end

  defp otp_version do
    case String.split(System.otp_release(), ".") do
      [major] -> "#{major}.0.0"
      [major, minor] -> "#{major}.#{minor}.0"
      parts -> Enum.take(parts, 3) |> Enum.join(".")
    end
  end

  defp same_candidate(candidate, verified) do
    if candidate.checksum == verified.package_checksum and
         candidate.manifest == verified.manifest,
       do: :ok,
       else: {:error, "package changed after discovery"}
  end

  defp extract(verified, opts) do
    cache_name = "sha256-#{verified.package_checksum}"
    destination = Path.join(opts.cache_dir, cache_name)

    if File.dir?(destination) do
      with :ok <- verify_cache(destination, verified.files), do: {:ok, destination}
    else
      temporary = destination <> ".tmp-#{System.unique_integer([:positive])}"

      with :ok <- file_operation(File.mkdir_p(temporary), "create cache staging directory"),
           :ok <- file_operation(write_files(temporary, verified.files), "write cache files"),
           :ok <- file_operation(File.mkdir_p(opts.cache_dir), "create cache directory"),
           :ok <- rename_cache(temporary, destination, 5) do
        {:ok, destination}
      else
        {:error, :eexist} ->
          File.rm_rf(temporary)
          with :ok <- verify_cache(destination, verified.files), do: {:ok, destination}

        {:error, reason} when is_binary(reason) ->
          File.rm_rf(temporary)
          {:error, reason}

        {:error, reason} ->
          File.rm_rf(temporary)
          {:error, "cannot populate Extension cache: #{inspect(reason)}"}
      end
    end
  end

  defp rename_cache(source, destination, attempts) do
    case File.rename(source, destination) do
      :ok ->
        :ok

      {:error, :eacces} when attempts > 1 ->
        Process.sleep(20)
        rename_cache(source, destination, attempts - 1)

      {:error, :eexist} = error ->
        error

      error ->
        file_operation(error, "activate cache directory")
    end
  end

  defp file_operation(:ok, _operation), do: :ok

  defp file_operation({:error, reason}, operation),
    do: {:error, "cannot #{operation}: #{inspect(reason)}"}

  defp write_files(destination, files) do
    Enum.reduce_while(files, :ok, fn {relative, contents}, :ok ->
      path = Path.join([destination | String.split(relative, "/")])

      with :ok <- File.mkdir_p(Path.dirname(path)),
           :ok <- File.write(path, contents, [:binary, :exclusive]) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp verify_cache(destination, files) do
    Enum.reduce_while(files, :ok, fn {relative, expected}, :ok ->
      path = Path.join([destination | String.split(relative, "/")])

      case File.read(path) do
        {:ok, ^expected} -> {:cont, :ok}
        _other -> {:halt, {:error, "Extension cache does not match the installed package"}}
      end
    end)
  end

  defp load_application(verified, cache_path) do
    manifest = verified.manifest

    code_path =
      Path.join([cache_path, "lib", "#{manifest.otp_application}-#{manifest.version}", "ebin"])

    app = String.to_atom(manifest.otp_application)

    with :ok <- ensure_application_available(app) do
      do_load_application(verified, cache_path, app, code_path)
    end
  end

  defp do_load_application(verified, cache_path, app, code_path) do
    manifest = verified.manifest

    with {:ok, package_modules} <- package_modules(verified.files),
         :ok <- ensure_modules_available(package_modules),
         :ok <- add_code_path(code_path),
         :ok <- load_package_modules(package_modules, code_path),
         :ok <- load_otp_application(app),
         {:ok, _started} <- Application.ensure_all_started(app, :temporary),
         {:ok, entries} <-
           build_component_entries(
             manifest,
             package_modules,
             verified.package_checksum
           ) do
      {:ok,
       %LoadedExtension{
         manifest: manifest,
         package_path: verified.package_path,
         package_checksum: verified.package_checksum,
         cache_path: cache_path,
         otp_application: app,
         code_path: code_path,
         component_entries: entries
       }}
    else
      {:error, reason} ->
        deactivate(app, code_path)
        {:error, format_reason(reason)}
    end
  rescue
    error ->
      deactivate(app, code_path)
      {:error, Exception.message(error)}
  end

  defp ensure_application_available(app) do
    if Application.spec(app),
      do: {:error, "OTP application #{app} is already loaded"},
      else: :ok
  end

  defp add_code_path(code_path) do
    case Code.prepend_path(code_path) do
      result when result in [:ok, true] -> :ok
      other -> {:error, "could not add Extension code path: #{inspect(other)}"}
    end
  end

  # Releases use Erlang's embedded code-loading mode, where adding a path does
  # not make modules load automatically. Load every verified package module
  # explicitly before OTP starts the Extension application. Development and
  # test run in interactive mode, so release startup smoke tests are required
  # to protect this boundary.
  defp load_package_modules(modules, code_path) do
    Enum.reduce_while(modules, :ok, fn module, :ok ->
      beam = Path.join(code_path, Atom.to_string(module)) |> String.to_charlist()

      case :code.load_abs(beam) do
        {:module, ^module} ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, "cannot load #{inspect(module)}: #{inspect(reason)}"}}
      end
    end)
  end

  defp package_modules(files) do
    modules =
      files
      |> Enum.filter(fn {path, _contents} -> Path.extname(path) == ".beam" end)
      |> Enum.map(fn {_path, beam} ->
        case :beam_lib.info(beam) do
          info when is_list(info) -> Keyword.fetch!(info, :module)
          {:error, _module, reason} -> throw({:invalid_beam, reason})
        end
      end)

    if modules == [] or length(modules) != length(Enum.uniq(modules)),
      do: {:error, "package BEAM modules are missing or duplicated"},
      else: {:ok, modules}
  catch
    {:invalid_beam, reason} -> {:error, "package contains an invalid BEAM: #{inspect(reason)}"}
  end

  defp ensure_modules_available(modules) do
    case Enum.find(modules, &(&1 |> :code.which() |> Kernel.!=(:non_existing))) do
      nil -> :ok
      module -> {:error, "module collision: #{inspect(module)} is already available"}
    end
  end

  defp load_otp_application(app) do
    case Application.load(app) do
      :ok -> :ok
      {:error, reason} -> {:error, "cannot load OTP application #{app}: #{inspect(reason)}"}
    end
  end

  defp build_component_entries(manifest, package_modules, package_checksum) do
    entries =
      Enum.map(
        manifest.components,
        &build_component_entry!(manifest, &1, package_modules, package_checksum)
      )

    {:ok, entries}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp build_component_entry!(manifest, declaration, package_modules, package_checksum) do
    if declaration.kind != :adapter do
      raise ArgumentError, "Processor packages are not supported by this runtime milestone"
    end

    module = String.to_atom("Elixir." <> declaration.module)

    unless module in package_modules do
      raise ArgumentError, "declared component module is not included in the package"
    end

    unless Code.ensure_loaded?(module) do
      raise ArgumentError, "declared component module #{declaration.module} is not loadable"
    end

    component = module.component()
    declared_capabilities = Enum.sort(declaration.capabilities)
    actual_capabilities = component.capabilities |> Enum.map(&Atom.to_string/1) |> Enum.sort()

    expected = %Component{
      extension_id: manifest.extension_id,
      component_id: declaration.id,
      kind: declaration.kind,
      version: manifest.version,
      capabilities: component.capabilities
    }

    if actual_capabilities != declared_capabilities do
      raise ArgumentError, "component capabilities do not match its manifest"
    end

    source = if "source" in declaration.capabilities, do: module
    target = if "target" in declaration.capabilities, do: module

    if is_nil(source) and is_nil(target) do
      raise ArgumentError, "Adapter component must declare source or target capability"
    end

    ComponentEntry.build!(declaration.id, source, target, expected,
      artifact: CourierCMS.Extensions.Artifact.packaged(expected, package_checksum)
    )
  end

  defp deactivate(app, code_path) do
    if is_atom(app) do
      Application.stop(app)
      Application.unload(app)
    end

    if is_binary(code_path) do
      purge_modules_from(code_path)
      Code.delete_path(code_path)
    end

    :ok
  end

  defp purge_modules_from(code_path) do
    normalized = Path.expand(code_path)

    :code.all_loaded()
    |> Enum.each(fn
      {module, path} when is_list(path) ->
        if path |> List.to_string() |> Path.dirname() |> Path.expand() == normalized do
          :code.soft_purge(module)
          :code.delete(module)
        end

      _other ->
        :ok
    end)
  end

  defp sha256_file!(path), do: path |> File.read!() |> sha256()
  defp sha256(contents), do: :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower)

  defp limit(value, maximum, _label) when value <= maximum, do: :ok
  defp limit(_value, _maximum, label), do: {:error, "#{label} exceeds the configured limit"}

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
