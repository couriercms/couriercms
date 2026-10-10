defmodule CourierCMS.Installation do
  @moduledoc "Provides the stable identity of this CourierCMS installation."

  def id do
    Application.get_env(:couriercms, :installation_id, "00000000-0000-4000-8000-000000000001")
  end
end
