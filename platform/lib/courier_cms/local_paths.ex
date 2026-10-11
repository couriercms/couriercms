defmodule CourierCMS.LocalPaths do
  @moduledoc "Stable operating-system paths used by the Local release."

  def data_dir do
    System.get_env("COURIERCMS_LOCAL_DATA_PATH")
    |> present_or(default_data_dir())
    |> Path.expand()
  end

  def database_path, do: configured_path("COURIERCMS_SQLITE_PATH", "couriercms.db")
  def extensions_dir, do: configured_path("COURIERCMS_EXTENSIONS_PATH", "extensions")

  def extension_cache_dir,
    do: configured_path("COURIERCMS_EXTENSION_CACHE_DIR", "extension-cache")

  def logs_dir, do: Path.join(data_dir(), "logs")
  def temporary_dir, do: Path.join(data_dir(), "tmp")
  def backups_dir, do: Path.join(data_dir(), "backups")
  def secrets_path, do: Path.join(data_dir(), "installation-secrets.json")

  def prepare! do
    for path <- [
          data_dir(),
          extensions_dir(),
          extension_cache_dir(),
          logs_dir(),
          temporary_dir(),
          backups_dir()
        ] do
      File.mkdir_p!(path)
    end

    :ok
  end

  defp configured_path(environment_name, default_name) do
    System.get_env(environment_name)
    |> present_or(Path.join(data_dir(), default_name))
    |> Path.expand()
  end

  defp default_data_dir do
    cond do
      windows?() -> Path.join(System.get_env("LOCALAPPDATA") || System.user_home!(), "CourierCMS")
      value = System.get_env("XDG_DATA_HOME") -> Path.join(value, "couriercms")
      true -> Path.join([System.user_home!(), ".local", "share", "couriercms"])
    end
  end

  defp windows?, do: match?({:win32, _name}, :os.type())
  defp present_or(value, fallback) when value in [nil, ""], do: fallback
  defp present_or(value, _fallback), do: value
end
