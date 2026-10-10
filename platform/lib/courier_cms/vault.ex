defmodule CourierCMS.Vault do
  @moduledoc "Encryption vault for Connection credentials stored in PostgreSQL."

  use Cloak.Vault, otp_app: :couriercms
end
