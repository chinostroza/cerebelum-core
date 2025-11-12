defmodule Cerebelum.Repo do
  use Ecto.Repo,
    otp_app: :cerebelum_core,
    adapter: Ecto.Adapters.Postgres
end
