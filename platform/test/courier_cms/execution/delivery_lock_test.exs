defmodule CourierCMS.Execution.DeliveryLockTest do
  use CourierCMS.DataCase

  alias CourierCMS.Execution.DeliveryLock

  test "only one owner holds a delivery lease until it is released" do
    first_owner = Ecto.UUID.generate()
    second_owner = Ecto.UUID.generate()

    assert :ok = DeliveryLock.acquire("route:item:locale", first_owner, 60_000)
    assert :busy = DeliveryLock.acquire("route:item:locale", second_owner, 60_000)
    assert :ok = DeliveryLock.release("route:item:locale", first_owner)
    assert :ok = DeliveryLock.acquire("route:item:locale", second_owner, 60_000)
  end

  test "an expired lease can be recovered after a worker terminates" do
    first_owner = Ecto.UUID.generate()
    second_owner = Ecto.UUID.generate()

    assert :ok = DeliveryLock.acquire("recoverable", first_owner, 60_000)

    DeliveryLock
    |> Repo.get!("recoverable")
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1, :second))
    |> Repo.update!()

    assert :ok = DeliveryLock.acquire("recoverable", second_owner, 60_000)
  end
end
