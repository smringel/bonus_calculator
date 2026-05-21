defmodule BonusCalculatorWeb.PageControllerTest do
  use BonusCalculatorWeb.ConnCase

  test "GET /old_home", %{conn: conn} do
    conn = get(conn, ~p"/old_home")
    assert html_response(conn, 200) =~ "Peace of mind from prototype to production"
  end
end
