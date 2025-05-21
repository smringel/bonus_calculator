defmodule BonusCalculatorWeb.BonusController do
  use BonusCalculatorWeb, :controller

  def index(conn, _params) do
    render(conn, :index, layout: false)
  end

  def calculate(conn, params) do
    # Extract parameters from form submission
    business_unit_modifier = parse_float(params["business_unit_modifier"])
    enterprise_modifier = parse_float(params["enterprise_modifier"])
    nfs_modifier = parse_float(params["nfs_modifier"])
    individual_modifier = parse_float(params["individual_modifier"])
    bonus_target = parse_float(params["bonus_target"])
    salary = parse_float(params["salary"])

    # Calculate bonus (placeholder calculation)
    bonus = calculate_bonus(business_unit_modifier, enterprise_modifier, nfs_modifier, 
                           individual_modifier, bonus_target, salary)

    # Render the result
    render(conn, :result, layout: false, 
           business_unit_modifier: business_unit_modifier,
           enterprise_modifier: enterprise_modifier,
           nfs_modifier: nfs_modifier,
           individual_modifier: individual_modifier,
           bonus_target: bonus_target,
           salary: salary,
           bonus: bonus)
  end

  # Helper function to parse float values from form inputs
  defp parse_float(nil), do: 0.0
  defp parse_float(""), do: 0.0
  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> 0.0
    end
  end
  defp parse_float(value), do: value

  # Bonus calculation logic based on the screenshot formula
  defp calculate_bonus(business_unit_modifier, enterprise_modifier, nfs_modifier, 
                      individual_modifier, bonus_target, salary) do
    # Calculate MIP Target Value
    mip_target_value = salary * (bonus_target / 100.0)
    
    # Convert all percentage modifiers to decimal form for calculation
    business_unit_decimal = business_unit_modifier / 100.0
    enterprise_decimal = enterprise_modifier / 100.0
    nfs_decimal = nfs_modifier / 100.0
    individual_decimal = individual_modifier / 100.0
    
    # Calculate Financial Performance Result (70% BU + 30% Enterprise)
    financial_performance = (0.7 * business_unit_decimal) + (0.3 * enterprise_decimal)
    
    # Calculate FY25 MIP Award
    # MIP Target Value × Financial Performance × NFS Modifier × Individual Modifier
    mip_award = mip_target_value * financial_performance * nfs_decimal * individual_decimal
    
    mip_award
  end
end
