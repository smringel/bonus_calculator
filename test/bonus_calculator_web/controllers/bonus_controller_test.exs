defmodule BonusCalculatorWeb.BonusControllerTest do
  use BonusCalculatorWeb.ConnCase, async: true

  # Baseline params produce a gross bonus of exactly $10,000:
  #   prorated_salary = 100_000
  #   mip_target = 100_000 * 0.10 = 10_000
  #   financial_perf = 0.7*1.0 + 0.3*1.0 = 1.0
  #   gross = 10_000 * 1.0 * 1.0 * 1.0 = 10_000
  defp base_params(overrides \\ %{}) do
    Map.merge(
      %{
        "business_unit_modifier" => "100",
        "enterprise_modifier" => "100",
        "nfs_modifier" => "100",
        "individual_modifier" => "100",
        "bonus_target" => "10",
        "salary" => "100000",
        "weeks_worked" => "52",
        "fed_method" => "supplemental",
        "filing_status" => "single",
        "other_annual_income" => "0",
        "state" => "OH",
        "local_tax_rate" => "0",
        "traditional_401k" => "0",
        "roth_401k" => "0",
        "hsa" => "0"
      },
      overrides
    )
  end

  describe "GET /" do
    test "renders the form with deduction inputs and state dropdown", %{conn: conn} do
      conn = get(conn, ~p"/")
      body = html_response(conn, 200)

      assert body =~ "Bonus Calculator"
      assert body =~ "Estimated Deductions"
      assert body =~ "Federal Tax Method"
      assert body =~ "Traditional 401(k)"
      assert body =~ "Roth 401(k)"
      assert body =~ "HSA"
      # State dropdown is populated and defaults to OH
      assert body =~ "OH — Ohio"
      assert body =~ ~s(selected value="OH") or body =~ ~s(value="OH" selected)
    end
  end

  describe "POST /calculate — supplemental federal, no deductions other than mandatory" do
    test "applies 22% federal, 6.2% SS, 1.45% Medicare, 3.5% Ohio state", %{conn: conn} do
      conn = post(conn, ~p"/calculate", base_params())
      body = html_response(conn, 200)

      # Gross bonus
      assert body =~ ~r/data-net-gross>\s*\$10000\.00/
      # SS: 10000 * 0.062 = 620.00
      assert body =~ "data-net-ss>620.00"
      # Medicare: 10000 * 0.0145 = 145.00
      assert body =~ "data-net-medicare>145.00"
      # Federal supplemental: 10000 * 0.22 = 2200.00
      assert body =~ "data-net-fed>2200.00"
      # Ohio state: 10000 * 0.035 = 350.00
      assert body =~ "data-net-state>350.00"
      # Local: 0
      assert body =~ "data-net-local>0.00"
      # Net: 10000 - 620 - 145 - 2200 - 350 = 6685
      assert body =~ "data-net-take-home>6685.00"
    end
  end

  describe "POST /calculate — traditional 401(k)" do
    test "reduces federal & state taxable but NOT FICA", %{conn: conn} do
      conn = post(conn, ~p"/calculate", base_params(%{"traditional_401k" => "10"}))
      body = html_response(conn, 200)

      # Traditional deferral: 10000 * 0.10 = 1000
      assert body =~ "data-net-trad>1000.00"
      # FICA still on full gross
      assert body =~ "data-net-ss>620.00"
      assert body =~ "data-net-medicare>145.00"
      # Federal taxable now 9000 -> 22% = 1980
      assert body =~ "data-net-fed>1980.00"
      # State on 9000 -> 3.5% = 315
      assert body =~ "data-net-state>315.00"
      # Net: 10000 - 1000 - 620 - 145 - 1980 - 315 = 5940
      assert body =~ "data-net-take-home>5940.00"
    end
  end

  describe "POST /calculate — Roth 401(k)" do
    test "reduces take-home but does NOT reduce federal/state taxable", %{conn: conn} do
      conn = post(conn, ~p"/calculate", base_params(%{"roth_401k" => "10"}))
      body = html_response(conn, 200)

      assert body =~ "data-net-roth>1000.00"
      # Federal and state are unchanged from the no-deduction case
      assert body =~ "data-net-fed>2200.00"
      assert body =~ "data-net-state>350.00"
      # Net: 10000 - 1000 - 620 - 145 - 2200 - 350 = 5685
      assert body =~ "data-net-take-home>5685.00"
    end
  end

  describe "POST /calculate — HSA" do
    test "reduces FICA and federal/state taxable", %{conn: conn} do
      conn = post(conn, ~p"/calculate", base_params(%{"hsa" => "500"}))
      body = html_response(conn, 200)

      assert body =~ "data-net-hsa>500.00"
      # FICA base = 9500
      # SS: 9500 * 0.062 = 589.00
      assert body =~ "data-net-ss>589.00"
      # Medicare: 9500 * 0.0145 = 137.75
      assert body =~ "data-net-medicare>137.75"
      # Federal taxable 9500 -> 22% = 2090
      assert body =~ "data-net-fed>2090.00"
      # State 9500 * 0.035 = 332.50
      assert body =~ "data-net-state>332.50"
      # Net: 10000 - 500 - 589 - 137.75 - 2090 - 332.50 = 6350.75
      assert body =~ "data-net-take-home>6350.75"
    end
  end

  describe "POST /calculate — local tax" do
    test "applies local tax to gross bonus", %{conn: conn} do
      conn = post(conn, ~p"/calculate", base_params(%{"local_tax_rate" => "2.5"}))
      body = html_response(conn, 200)

      # Local: 10000 * 0.025 = 250
      assert body =~ "data-net-local>250.00"
    end
  end

  describe "POST /calculate — state selection" do
    test "no-tax state (FL) yields 0 state tax", %{conn: conn} do
      conn = post(conn, ~p"/calculate", base_params(%{"state" => "FL"}))
      body = html_response(conn, 200)
      assert body =~ "data-net-state>0.00"
    end

    test "California uses its supplemental rate (10.23%)", %{conn: conn} do
      conn = post(conn, ~p"/calculate", base_params(%{"state" => "CA"}))
      body = html_response(conn, 200)
      # 10000 * 0.1023 = 1023.00
      assert body =~ "data-net-state>1023.00"
    end
  end

  describe "POST /calculate — marginal federal method" do
    test "computes incremental tax on top of other income (single, $200k base)", %{conn: conn} do
      # other_income = 200_000 (single) sits in the 32% bracket and
      # adding $10_000 stays in the 32% bracket, so federal == 3200.
      conn =
        post(
          conn,
          ~p"/calculate",
          base_params(%{
            "fed_method" => "marginal",
            "filing_status" => "single",
            "other_annual_income" => "200000"
          })
        )

      body = html_response(conn, 200)
      assert body =~ "data-net-fed>3200.00"
      assert body =~ "Marginal bracket estimate"
    end

    test "MFJ at modest income gets lower marginal rate", %{conn: conn} do
      # MFJ other_income = 50_000 is in the 12% bracket; adding $10k stays in 12%.
      # Federal = 10_000 * 0.12 = 1200
      conn =
        post(
          conn,
          ~p"/calculate",
          base_params(%{
            "fed_method" => "marginal",
            "filing_status" => "mfj",
            "other_annual_income" => "50000"
          })
        )

      body = html_response(conn, 200)
      assert body =~ "data-net-fed>1200.00"
    end

    test "marginal calc spans two brackets", %{conn: conn} do
      # Single, other_income = 45_000 (12% bracket, top 48_475).
      # Adding $10k -> 55_000, crosses into 22% bracket.
      # tax_on(45k) for single =
      #   11_925 * 0.10 + (45_000 - 11_925) * 0.12
      # = 1_192.50 + 3_969.00 = 5_161.50
      # tax_on(55k) =
      #   11_925 * 0.10 + (48_475 - 11_925) * 0.12 + (55_000 - 48_475) * 0.22
      # = 1_192.50 + 4_386.00 + 1_435.50 = 7_014.00
      # marginal = 7_014.00 - 5_161.50 = 1_852.50
      conn =
        post(
          conn,
          ~p"/calculate",
          base_params(%{
            "fed_method" => "marginal",
            "filing_status" => "single",
            "other_annual_income" => "45000"
          })
        )

      body = html_response(conn, 200)
      assert body =~ "data-net-fed>1852.50"
    end
  end

  describe "POST /calculate — weeks worked pro-ration still applies" do
    test "half a year halves the gross bonus", %{conn: conn} do
      conn = post(conn, ~p"/calculate", base_params(%{"weeks_worked" => "26"}))
      body = html_response(conn, 200)
      # Gross becomes 5000
      assert body =~ ~r/data-net-gross>\s*\$5000\.00/
    end
  end
end
