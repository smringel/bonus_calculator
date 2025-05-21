defmodule BonusCalculator.Repo do
  use Ecto.Repo,
    otp_app: :bonus_calculator,
    adapter: Ecto.Adapters.Postgres
end
