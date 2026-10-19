-- F1 cost cap - did it make it a fair fight? 2014-20 before the cap, 2021-26 under it.
-- each query has an '-- @name:' tag so run_analysis.py can pick them out

-- @name: championship_margin_by_season
-- gap between 1st and 2nd in the constructors' championship
with ranked as (
    select season, constructor_name, points,
           row_number() over (partition by season order by points desc) as rnk
    from constructor_standings
)
select
    a.season, a.constructor_name as champion, a.points as champion_points,
    b.points as runner_up_points, round(a.points - b.points, 1) as margin
from ranked a
join ranked b on a.season = b.season and b.rnk = 2
where a.rnk = 1
order by a.season;

-- @name: hhi_by_season
-- HHI on points share (over 2,500 = 'highly concentrated' in US antitrust terms)
select season, hhi, n_constructors_with_points
from constructor_hhi_by_season
order by season;

-- @name: distinct_winners_by_season
-- how many different teams won at least one race
select
    season,
    count(distinct constructor_id) as distinct_race_winners,
    count(*) as total_races
from fact_results
where position_order = 1
group by season
order by season;

-- @name: mclaren_trajectory
-- mclaren's finishing position each year
select cs.season, cs.position, cs.points, cs.wins
from constructor_standings cs
where cs.constructor_id = 'mclaren'
order by cs.season;

-- @name: fastest_to_slowest_gap
-- best vs worst team, as % of the champion's points (so seasons with more races still compare)
select
    season,
    max(points) as top_team_points,
    min(points) as bottom_team_points,
    round(100.0 * (max(points) - min(points)) / nullif(max(points), 0), 1) as gap_pct_of_leader
from constructor_standings
where points > 0
group by season
order by season;

-- @name: pit_crew_league_table
-- average stop time per team before/after the cap
with reasonable_stops as (
    select p.*, r.constructor_id, r.season >= 2021 as is_post_cap
    from pitstops p
    join results r using (season, round, driver_id)
    where p.duration_sec is not null and p.duration_sec < 60
)
select
    constructor_id,
    round(avg(case when not is_post_cap then duration_sec end), 2) as avg_duration_pre_cap,
    round(avg(case when is_post_cap then duration_sec end), 2) as avg_duration_post_cap,
    count(*) as n_stops
from reasonable_stops
group by constructor_id
order by avg_duration_post_cap;

-- @name: pre_post_cap_summary
-- before vs after in one table
select
    case when m.season < 2021 then 'Pre-cap (2014-2020)' else 'Post-cap (2021-2026)' end as era,
    round(avg(m.margin), 1) as avg_championship_margin,
    round(avg(h.hhi), 0) as avg_hhi,
    round(avg(w.distinct_race_winners), 1) as avg_distinct_winners_per_season
from (
    with ranked as (
        select season, points, row_number() over (partition by season order by points desc) as rnk
        from constructor_standings
    )
    select a.season, a.points - b.points as margin
    from ranked a join ranked b on a.season = b.season and b.rnk = 2
    where a.rnk = 1
) m
join constructor_hhi_by_season h using (season)
join (
    select season, count(distinct constructor_id) as distinct_race_winners
    from fact_results where position_order = 1 group by season
) w using (season)
group by case when m.season < 2021 then 'Pre-cap (2014-2020)' else 'Post-cap (2021-2026)' end
order by era desc;
