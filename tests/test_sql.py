# sql/01_schema.sql and sql/03_checks.sql run against a few hand-made rows in an in-memory duckdb

from pathlib import Path

import duckdb
import pytest

import check_data


@pytest.fixture
def con():
    con = duckdb.connect()
    con.execute("""
        create table results as select * from (values
            (2020, 1, 'Austrian Grand Prix', 'hamilton',   'mercedes', 5, 4,    12.0),
            (2021, 1, 'Bahrain Grand Prix',  'verstappen', 'red_bull', 1, 2,    18.0),
            (2021, 1, 'Bahrain Grand Prix',  'mazepin',    'haas',     20, null, 0.0)
        ) t(season, round, race_name, driver_id, constructor_id, grid, position_order, points)
    """)
    con.execute("""
        create table qualifying as select * from (values
            (2021, 1, 'Bahrain Grand Prix', 'verstappen', 'red_bull', 1, '1:30.499', '1:30.318', '1:28.997')
        ) t(season, round, race_name, driver_id, constructor_id, position, q1, q2, q3)
    """)
    con.execute("""
        create table constructor_standings as select * from (values
            (2021, 'mercedes', 'Mercedes', 613.5, 9, 1),
            (2021, 'red_bull', 'Red Bull', 585.5, 11, 2)
        ) t(season, constructor_id, constructor_name, points, wins, position)
    """)
    con.execute(Path("sql/01_schema.sql").read_text())
    yield con
    con.close()


def test_parse_laptime(con):
    got = con.execute("select parse_laptime('1:23.456'), parse_laptime('75.1'), parse_laptime('')").fetchone()
    assert got[0] == pytest.approx(83.456)
    assert got[1] == pytest.approx(75.1)
    assert got[2] is None


def test_dim_season_flags_the_cap_from_2021(con):
    rows = dict(con.execute("select season, is_post_cap from dim_season").fetchall())
    assert rows == {2020: False, 2021: True}
    assert con.execute("select cap_usd_m from dim_season where season = 2021").fetchone()[0] == 145.0


def test_fact_results_drops_unclassified_finishes(con):
    drivers = {r[0] for r in con.execute("select driver_id from fact_results").fetchall()}
    assert "mazepin" not in drivers
    assert con.execute("select places_gained from fact_results where driver_id = 'hamilton'").fetchone()[0] == 1


def test_best_qualifying_time_is_the_fastest_session(con):
    assert con.execute("select best_sec from qualifying_clean").fetchone()[0] == pytest.approx(88.997)


def test_checks_file_parses():
    checks = check_data.load_checks()
    assert len(checks) >= 10
    assert "results_one_row_per_driver_per_race" in checks


def test_duplicate_check_catches_a_duplicate(con):
    con.execute("insert into results select * from results where driver_id = 'verstappen'")
    sql = check_data.load_checks()["results_one_row_per_driver_per_race"]
    assert len(con.execute(sql).fetchall()) == 1
