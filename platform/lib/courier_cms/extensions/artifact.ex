defmodule CourierCMS.Extensions.Artifact do
  @moduledoc "Immutable evidence identifying the exact Extension component code used by a Run."

  alias CourierCMS.ExtensionSDK.Component

  @required_keys ~w(extension_id component_id version checksum sdk_version runtime)

  def from_entry(entry) do
    entry.artifact
  end

  def packaged(%Component{} = component, package_checksum) do
    build(component, package_checksum, "package")
  end

  def bundled(%Component{} = component, modules) do
    checksum =
      modules
      |> Enum.sort_by(&Atom.to_string/1)
      |> Enum.map(&module_evidence/1)
      |> :erlang.term_to_binary([:deterministic])
      |> sha256()

    build(component, checksum, "bundled")
  end

  def validate(artifact) when is_map(artifact) do
    if Enum.all?(@required_keys, &(is_binary(artifact[&1]) and artifact[&1] != "")),
      do: :ok,
      else: {:error, "Extension artifact evidence is incomplete"}
  end

  def validate(_artifact), do: {:error, "Extension artifact evidence is incomplete"}

  def matches?(left, right) when is_map(left) and is_map(right) do
    Enum.all?(@required_keys, &(left[&1] == right[&1]))
  end

  def reference(artifact) when is_map(artifact) do
    %{
      extension_id: artifact["extension_id"],
      component_id: artifact["component_id"]
    }
  end

  defp build(component, checksum, provenance) do
    %{
      "extension_id" => component.extension_id,
      "component_id" => component.component_id,
      "version" => component.version,
      "checksum" => checksum,
      "sdk_version" => CourierCMS.ExtensionSDK.version(),
      "runtime" => "beam",
      "provenance" => provenance
    }
  end

  defp module_evidence(module) do
    case :code.get_object_code(module) do
      {^module, beam, _path} -> {module, beam}
      :error -> {module, module.module_info(:md5)}
    end
  end

  defp sha256(value),
    do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
