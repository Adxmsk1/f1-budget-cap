-- data checks, run by scripts/check_data.py after build_db.py.
-- each query returns the rows that break the rule, so an empty result is a pass.
-- each check starts with an @check comment, same idea as the @name blocks in 02_analysis.sql

-- @check: results_one_row_per_driver_per_race
select season, round, driver_id, count(*) as n
from results
group by all
having count(*) > 1;

-- @check: results_keys_not_null
select *
from results
where season is null or round is null or driver_id is null or constructor_id is null;

-- @check: every_season_loaded
select s.season
from range(2014, 2027) as s(season)
anti join (select distinct season from results) r using (season);

-- @check: every_race_has_a_full_grid
-- smallest grid in the period is 18 cars; fewer means a page went missing during ingest
select season, round, count(*) as drivers
from results
group by all
having count(*) < 18;

-- @check: points_not_negative
select 'results' as source, season, points from results where points < 0
union all
select 'driver_standings', season, points from driver_standings where points < 0
union all
select 'constructor_standings', season, points from constructor_standings where points < 0;

-- @check: grid_and_finish_in_range
-- grid 0 means a pit lane start, so it's allowed
select season, round, driver_id, grid, position_order
from fact_results
where grid not between 0 and 26 or position_order not between 1 and 26;

-- @check: one_constructors_leader_per_season
select season, count(*) as leaders
from constructor_standings
where position = 1
group by season
having count(*) <> 1;

-- @check: qualifying_times_plausible
-- best_sec is 1e9 when a driver set no time at all, so those are skipped
select season, round, driver_id, best_sec
from qualifying_clean
where best_sec < 1e9 and best_sec not between 50 and 200;

-- @check: pitstops_belong_to_a_result
select p.season, p.round, p.driver_id
from pitstops p
anti join results r using (season, round, driver_id);

-- @check: pitstop_durations_mostly_present
-- a handful of stops have no time in the source (listed in the data dictionary). more than that means parsing broke
select count(*) as missing
from pitstops
where duration_sec is null
having count(*) > 10;
