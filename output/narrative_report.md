# Did the budget cap make F1 a fair fight?

### 2014-2026, data from the Jolpica F1 API

In 2021 Formula 1 capped team spending at $145m, stepping down to $135m by 2023, to stop the richest teams simply
outspending everyone else. Mercedes had just won seven constructors' championships in a row. Six seasons in, has it
worked? Partly - and not quite where you'd expect.

## Title fights: closer on average, but less predictable

The points gap between the champion and the runner-up in the constructors' championship:

| Era | Avg margin | Range |
|---|---|---|
| Before the cap (2014-2020) | 226.7 pts | 84 (2018) to 297 (2016) |
| Under the cap (2021-2026) | 199.3 pts | 14 (2024) to **451 (2023)** |

The average came down, but the range got wider. 2023 is the most one-sided season in the whole dataset - Red Bull's
451-point margin is bigger than any of Mercedes' wins. At the other end, 2021 and 2024 were the two closest title
fights (28 and 14 points). The cap hasn't stopped a team dominating a season, but nobody has dominated for years on end
the way Mercedes did.

## How concentrated are the points?

I used the Herfindahl-Hirschman Index (HHI), which competition regulators use to measure how concentrated a market is,
on each team's share of the points. It fell from 2,160 before the cap to 2,041 after - still "moderately concentrated"
(1,500-2,500) by US antitrust standards. F1 was never going to look like an evenly split market.

The number of different teams winning a race is easier to read: 2.7 a season before the cap, 3.3 after. Three of the
six cap seasons (2021, 2024 and 2026) had four different winners. Before the cap only 2020 did.

## McLaren

McLaren finished 9th in the constructors' championship in 2015 and 2017 - the worst seasons in the team's history -
and won it in 2024 and 2025, their first titles since 1998. No team has done better out of a capped field.

## What didn't change: the back of the grid

The gap between the best and worst team's points, as a share of the leader's total, has been between 96% and 100% in
every season, before and after the cap. The cap tightened things at the front without closing the gap to the back.
$135m still buys a much better car than the smallest teams can build - it just stops the biggest spender running away
from the next biggest.

## Pit crews

Average stop time by team under the cap (stops under 60 seconds only - anything longer is a penalty or a repair):
Mercedes (23.88s), Ferrari (23.89s) and RB (23.90s) are quickest; Haas (25.71s) and Cadillac (26.10s, new for 2026)
are slowest. It roughly follows the championship order, but not exactly - being quick in the pits and being quick on
track aren't the same thing.

## Data

[Jolpica F1 API](https://github.com/jolpica/jolpica-f1) (`api.jolpi.ca`): every race result, qualifying session, pit
stop and final standing from 2014 to the current, unfinished 2026 season. Column details are in
`data/processed/data_dictionary.md`.
