-- views on top of the raw tables: pre/post cap flag per season, qualifying times parsed from M:SS.sss,
-- and each team's share of the season's points (for the HHI)

create or replace macro parse_laptime(t) as
    case
        when t is null or t = '' then null
        when contains(t, ':') then
            cast(split_part(t, ':', 1) as double) * 60
            + cast(split_part(t, ':', 2) as double)
        else cast(t as double)
    end;

create or replace view dim_season as
select
    season,
    season >= 2021 as is_post_cap,
    case
        when season = 2021 then 145.0
        when season = 2022 then 140.0
        when season >= 2023 then 135.0
        else null
    end as cap_usd_m,  -- cost cap as reported by the FIA; no cap before 2021
    count(distinct round) as num_races
from results
group by season;

create or replace view qualifying_clean as
select
    season, round, race_name, driver_id, constructor_id, position,
    parse_laptime(q1) as q1_sec,
    parse_laptime(q2) as q2_sec,
    parse_laptime(q3) as q3_sec,
    least(
        coalesce(parse_laptime(q1), 1e9),
        coalesce(parse_laptime(q2), 1e9),
        coalesce(parse_laptime(q3), 1e9)
    ) as best_sec
from qualifying;

create or replace view fact_results as
select
    r.*,
    grid - position_order as places_gained,
    s.is_post_cap, s.cap_usd_m
from results r
join dim_season s using (season)
where position_order is not null;  -- excludes DNS/DNQ entries with no classified finish

create or replace view constructor_season_share as
select
    season, constructor_id, constructor_name, points, wins, position,
    round(100.0 * points / sum(points) over (partition by season), 2) as points_share_pct
from constructor_standings
where points > 0;

create or replace view constructor_hhi_by_season as
select
    season,
    round(sum(power(points_share_pct, 2)), 0) as hhi,
    count(*) as n_constructors_with_points
from constructor_season_share
group by season;
