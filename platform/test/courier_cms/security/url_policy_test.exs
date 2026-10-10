defmodule CourierCMS.Security.URLPolicyTest do
  use ExUnit.Case, async: false

  alias CourierCMS.Security.URLPolicy

  setup do
    previous = %{
      http: Application.get_env(:couriercms, :allow_http_cms_endpoints),
      private: Application.get_env(:couriercms, :allow_private_cms_networks),
      local: Application.get_env(:couriercms, :allow_unsafe_local_cms_endpoints)
    }

    on_exit(fn ->
      Application.put_env(:couriercms, :allow_http_cms_endpoints, previous.http)
      Application.put_env(:couriercms, :allow_private_cms_networks, previous.private)
      Application.put_env(:couriercms, :allow_unsafe_local_cms_endpoints, previous.local)
    end)

    Application.put_env(:couriercms, :allow_http_cms_endpoints, false)
    Application.put_env(:couriercms, :allow_private_cms_networks, false)
    Application.put_env(:couriercms, :allow_unsafe_local_cms_endpoints, false)
    :ok
  end

  test "requires HTTPS by default" do
    assert {:error, :insecure_scheme} = URLPolicy.validate("http://203.0.113.10")
  end

  test "blocks local and metadata ranges even when private networks are enabled" do
    Application.put_env(:couriercms, :allow_private_cms_networks, true)

    assert {:error, :local_network_blocked} = URLPolicy.validate("https://127.0.0.1")
    assert {:error, :local_network_blocked} = URLPolicy.validate("https://169.254.169.254")
  end

  test "private networks require explicit deployment permission" do
    assert {:error, :private_network_blocked} = URLPolicy.validate("https://10.0.0.10")

    Application.put_env(:couriercms, :allow_private_cms_networks, true)
    assert :ok = URLPolicy.validate("https://10.0.0.10")
  end

  test "unsafe local development endpoints require their own permission" do
    Application.put_env(:couriercms, :allow_unsafe_local_cms_endpoints, true)
    assert :ok = URLPolicy.validate("https://127.0.0.1")
  end
end
