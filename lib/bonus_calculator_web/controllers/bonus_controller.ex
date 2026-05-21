defmodule BonusCalculatorWeb.BonusController do
  use BonusCalculatorWeb, :controller

  # FICA rates
  @social_security_rate 0.062
  @medicare_rate 0.0145

  # IRS supplemental wage federal withholding rate (bonuses under $1M/year)
  @supplemental_federal_rate 0.22

  # 2025 federal income tax brackets: list of {lower_threshold, marginal_rate}
  @federal_brackets %{
    single: [
      {0.0, 0.10},
      {11_925.0, 0.12},
      {48_475.0, 0.22},
      {103_350.0, 0.24},
      {197_300.0, 0.32},
      {250_525.0, 0.35},
      {626_350.0, 0.37}
    ],
    mfj: [
      {0.0, 0.10},
      {23_850.0, 0.12},
      {96_950.0, 0.22},
      {206_700.0, 0.24},
      {394_600.0, 0.32},
      {501_050.0, 0.35},
      {751_600.0, 0.37}
    ],
    mfs: [
      {0.0, 0.10},
      {11_925.0, 0.12},
      {48_475.0, 0.22},
      {103_350.0, 0.24},
      {197_300.0, 0.32},
      {250_525.0, 0.35},
      {375_800.0, 0.37}
    ],
    hoh: [
      {0.0, 0.10},
      {17_000.0, 0.12},
      {64_850.0, 0.22},
      {103_350.0, 0.24},
      {197_300.0, 0.32},
      {250_500.0, 0.35},
      {626_350.0, 0.37}
    ]
  }

  # Estimated state income tax rates (approximate top marginal / supplemental rates, 2025).
  # Order: {code, "label", rate_percent}. Used both for the dropdown and the calc.
  @state_options [
    {"AL", "AL — Alabama (5.00%)", 5.00},
    {"AK", "AK — Alaska (0.00%)", 0.00},
    {"AZ", "AZ — Arizona (2.50%)", 2.50},
    {"AR", "AR — Arkansas (4.40%)", 4.40},
    {"CA", "CA — California (10.23% bonus supp.)", 10.23},
    {"CO", "CO — Colorado (4.40%)", 4.40},
    {"CT", "CT — Connecticut (6.99%)", 6.99},
    {"DE", "DE — Delaware (6.60%)", 6.60},
    {"DC", "DC — District of Columbia (8.50%)", 8.50},
    {"FL", "FL — Florida (0.00%)", 0.00},
    {"GA", "GA — Georgia (5.39%)", 5.39},
    {"HI", "HI — Hawaii (11.00%)", 11.00},
    {"ID", "ID — Idaho (5.70%)", 5.70},
    {"IL", "IL — Illinois (4.95%)", 4.95},
    {"IN", "IN — Indiana (3.05%)", 3.05},
    {"IA", "IA — Iowa (3.80%)", 3.80},
    {"KS", "KS — Kansas (5.58%)", 5.58},
    {"KY", "KY — Kentucky (4.00%)", 4.00},
    {"LA", "LA — Louisiana (3.00%)", 3.00},
    {"ME", "ME — Maine (7.15%)", 7.15},
    {"MD", "MD — Maryland (5.75%)", 5.75},
    {"MA", "MA — Massachusetts (5.00%)", 5.00},
    {"MI", "MI — Michigan (4.25%)", 4.25},
    {"MN", "MN — Minnesota (9.85%)", 9.85},
    {"MS", "MS — Mississippi (4.70%)", 4.70},
    {"MO", "MO — Missouri (4.70%)", 4.70},
    {"MT", "MT — Montana (5.90%)", 5.90},
    {"NE", "NE — Nebraska (5.20%)", 5.20},
    {"NV", "NV — Nevada (0.00%)", 0.00},
    {"NH", "NH — New Hampshire (0.00%)", 0.00},
    {"NJ", "NJ — New Jersey (5.53%)", 5.53},
    {"NM", "NM — New Mexico (5.90%)", 5.90},
    {"NY", "NY — New York (11.70% bonus supp.)", 11.70},
    {"NC", "NC — North Carolina (4.25%)", 4.25},
    {"ND", "ND — North Dakota (1.50%)", 1.50},
    {"OH", "OH — Ohio (3.50% supp.)", 3.50},
    {"OK", "OK — Oklahoma (4.75%)", 4.75},
    {"OR", "OR — Oregon (8.00% supp.)", 8.00},
    {"PA", "PA — Pennsylvania (3.07%)", 3.07},
    {"RI", "RI — Rhode Island (5.99%)", 5.99},
    {"SC", "SC — South Carolina (6.20%)", 6.20},
    {"SD", "SD — South Dakota (0.00%)", 0.00},
    {"TN", "TN — Tennessee (0.00%)", 0.00},
    {"TX", "TX — Texas (0.00%)", 0.00},
    {"UT", "UT — Utah (4.55%)", 4.55},
    {"VT", "VT — Vermont (6.60%)", 6.60},
    {"VA", "VA — Virginia (5.75%)", 5.75},
    {"WA", "WA — Washington (0.00%)", 0.00},
    {"WV", "WV — West Virginia (4.82%)", 4.82},
    {"WI", "WI — Wisconsin (5.30%)", 5.30},
    {"WY", "WY — Wyoming (0.00%)", 0.00}
  ]

  def index(conn, _params) do
    render(conn, :index, layout: false, state_options: @state_options)
  end

  def calculate(conn, params) do
    business_unit_modifier = parse_float(params["business_unit_modifier"])
    enterprise_modifier = parse_float(params["enterprise_modifier"])
    nfs_modifier = parse_float(params["nfs_modifier"])
    individual_modifier = parse_float(params["individual_modifier"])
    bonus_target = parse_float(params["bonus_target"])
    salary = parse_float(params["salary"])
    weeks_worked = parse_weeks_worked(params["weeks_worked"])

    fed_method = parse_fed_method(params["fed_method"])
    filing_status = parse_filing_status(params["filing_status"])
    other_annual_income = parse_float(params["other_annual_income"])
    state_code = params["state"] || "OH"
    state_rate_pct = state_rate(state_code)
    local_tax_rate = parse_float(params["local_tax_rate"])
    traditional_401k_pct = parse_float(params["traditional_401k"])
    roth_401k_pct = parse_float(params["roth_401k"])
    hsa = parse_float(params["hsa"])

    prorated_salary = salary * (weeks_worked / 52.0)

    gross_bonus =
      calculate_bonus(
        business_unit_modifier,
        enterprise_modifier,
        nfs_modifier,
        individual_modifier,
        bonus_target,
        prorated_salary
      )

    breakdown =
      compute_deductions(gross_bonus, %{
        fed_method: fed_method,
        filing_status: filing_status,
        other_annual_income: other_annual_income,
        state_rate_pct: state_rate_pct,
        local_tax_rate_pct: local_tax_rate,
        traditional_401k_pct: traditional_401k_pct,
        roth_401k_pct: roth_401k_pct,
        hsa: hsa
      })

    render(conn, :result,
      layout: false,
      business_unit_modifier: business_unit_modifier,
      enterprise_modifier: enterprise_modifier,
      nfs_modifier: nfs_modifier,
      individual_modifier: individual_modifier,
      bonus_target: bonus_target,
      salary: salary,
      weeks_worked: weeks_worked,
      prorated_salary: prorated_salary,
      bonus: gross_bonus,
      breakdown: breakdown,
      fed_method: fed_method,
      filing_status: filing_status,
      other_annual_income: other_annual_income,
      state_code: state_code,
      state_rate_pct: state_rate_pct,
      local_tax_rate_pct: local_tax_rate,
      traditional_401k_pct: traditional_401k_pct,
      roth_401k_pct: roth_401k_pct,
      hsa: hsa
    )
  end

  # ----- Deduction math -----

  defp compute_deductions(gross, opts) do
    traditional_401k = gross * (opts.traditional_401k_pct / 100.0)
    roth_401k = gross * (opts.roth_401k_pct / 100.0)
    hsa = min(opts.hsa, gross)

    # FICA: HSA is pre-FICA; 401(k) (traditional or Roth) is NOT pre-FICA.
    fica_base = max(gross - hsa, 0.0)
    social_security = fica_base * @social_security_rate
    medicare = fica_base * @medicare_rate

    # Federal taxable: subtract traditional 401(k) and HSA (Roth is post-tax).
    fed_taxable = max(gross - traditional_401k - hsa, 0.0)

    federal_tax =
      case opts.fed_method do
        :supplemental ->
          fed_taxable * @supplemental_federal_rate

        :marginal ->
          marginal_federal_tax(fed_taxable, opts.other_annual_income, opts.filing_status)
      end

    # Most states piggyback on federal taxable wages for withholding purposes.
    state_tax = fed_taxable * (opts.state_rate_pct / 100.0)

    # Local taxes typically apply to gross wages (e.g., Ohio municipalities).
    local_tax = gross * (opts.local_tax_rate_pct / 100.0)

    total_deductions =
      traditional_401k + roth_401k + hsa +
        social_security + medicare + federal_tax + state_tax + local_tax

    net = gross - total_deductions

    %{
      gross: gross,
      traditional_401k: traditional_401k,
      roth_401k: roth_401k,
      hsa: hsa,
      fica_base: fica_base,
      social_security: social_security,
      medicare: medicare,
      fed_taxable: fed_taxable,
      federal_tax: federal_tax,
      state_tax: state_tax,
      local_tax: local_tax,
      total_deductions: total_deductions,
      net: net
    }
  end

  defp marginal_federal_tax(bonus_taxable, other_income, status) do
    brackets = Map.get(@federal_brackets, status, @federal_brackets.single)
    tax_on(other_income + bonus_taxable, brackets) - tax_on(other_income, brackets)
  end

  defp tax_on(income, _brackets) when income <= 0, do: 0.0

  defp tax_on(income, brackets) do
    brackets
    |> Enum.with_index()
    |> Enum.reduce(0.0, fn {{lower, rate}, idx}, acc ->
      upper =
        case Enum.at(brackets, idx + 1) do
          nil -> income
          {next_lower, _} -> min(income, next_lower)
        end

      if income > lower do
        acc + (upper - lower) * rate
      else
        acc
      end
    end)
  end

  defp state_rate(code) do
    case Enum.find(@state_options, fn {c, _, _} -> c == code end) do
      {_, _, rate} -> rate
      nil -> 0.0
    end
  end

  # ----- Input parsing -----

  defp parse_fed_method("marginal"), do: :marginal
  defp parse_fed_method(_), do: :supplemental

  defp parse_filing_status("mfj"), do: :mfj
  defp parse_filing_status("mfs"), do: :mfs
  defp parse_filing_status("hoh"), do: :hoh
  defp parse_filing_status(_), do: :single

  # Weeks worked defaults to 52 (full year) when blank; clamped to 0..52
  defp parse_weeks_worked(nil), do: 52.0
  defp parse_weeks_worked(""), do: 52.0

  defp parse_weeks_worked(value) do
    weeks = parse_float(value)

    cond do
      weeks < 0.0 -> 0.0
      weeks > 52.0 -> 52.0
      true -> weeks
    end
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
  defp calculate_bonus(
         business_unit_modifier,
         enterprise_modifier,
         nfs_modifier,
         individual_modifier,
         bonus_target,
         salary
       ) do
    mip_target_value = salary * (bonus_target / 100.0)

    business_unit_decimal = business_unit_modifier / 100.0
    enterprise_decimal = enterprise_modifier / 100.0
    nfs_decimal = nfs_modifier / 100.0
    individual_decimal = individual_modifier / 100.0

    financial_performance = 0.7 * business_unit_decimal + 0.3 * enterprise_decimal

    mip_target_value * financial_performance * nfs_decimal * individual_decimal
  end
end
