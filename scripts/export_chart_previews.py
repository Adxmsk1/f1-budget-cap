# quick static png versions of the main charts (matplotlib), handy before the pbi pages exist

from pathlib import Path

import duckdb
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

DB_PATH = Path("f1.duckdb")
OUT_DIR = Path("output/chart_previews")

ACCENT = "#A3661F"
ACCENT2 = "#2F5C55"
GOOD = "#3F6E46"
BAD = "#9A3B28"
MUTED = "#8C96A0"
GRID = "#E3DCCB"
BG = "#FBF8F1"
INK = "#1C2B3A"

plt.rcParams.update({
    "font.family": "sans-serif", "font.size": 11, "text.color": INK,
    "axes.edgecolor": GRID, "axes.labelcolor": INK, "xtick.color": INK, "ytick.color": INK,
    "figure.facecolor": BG, "axes.facecolor": BG, "savefig.facecolor": BG,
})


def style_ax(fig, ax, title, subtitle=None):
    fig.suptitle(title, fontsize=14, fontweight="bold", color=INK, x=0.02, y=0.98, ha="left")
    if subtitle:
        fig.text(0.02, 0.91, subtitle, fontsize=10, color=MUTED, ha="left")
    fig.subplots_adjust(top=0.82)
    ax.spines[["top", "right"]].set_visible(False)
    ax.spines[["left", "bottom"]].set_color(GRID)
    ax.grid(axis="y", color=GRID, linewidth=0.8, zorder=0)
    ax.set_axisbelow(True)
    ax.tick_params(length=0)


def main():
    con = duckdb.connect(str(DB_PATH), read_only=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # championship margin
    margin = con.execute("""
        with ranked as (
            select season, points, row_number() over (partition by season order by points desc) as rnk
            from constructor_standings)
        select a.season, a.points - b.points as margin
        from ranked a join ranked b on a.season = b.season and b.rnk = 2
        where a.rnk = 1 order by a.season
    """).df()
    fig, ax = plt.subplots(figsize=(9.5, 5))
    colors = [MUTED if s < 2021 else ACCENT for s in margin.season]
    ax.bar(margin.season.astype(str), margin.margin, color=colors, zorder=3)
    ax.axvline(6.5, color=BAD, linewidth=1.2, linestyle="--")
    ax.text(6.6, ax.get_ylim()[1] * 0.92, "Budget cap\nstarts 2021", fontsize=9, color=BAD)
    style_ax(fig, ax, "Did the budget cap close the championship fight?",
             "Points gap between 1st and 2nd in the final constructor standings")
    fig.savefig(OUT_DIR / "01_championship_margin.png", dpi=150)
    plt.close(fig)

    # mclaren
    mcl = con.execute("""
        select season, position from constructor_standings
        where constructor_id = 'mclaren' order by season
    """).df()
    fig, ax = plt.subplots(figsize=(9.5, 5))
    colors = [GOOD if p == 1 else ACCENT for p in mcl.position]
    ax.bar(mcl.season.astype(str), mcl.position, color=colors, zorder=3)
    ax.invert_yaxis()
    ax.set_yticks(range(1, 10))
    for x, y in zip(mcl.season.astype(str), mcl.position):
        ax.annotate(f"P{y}", (x, y), textcoords="offset points", xytext=(0, -14 if y < 5 else 8),
                    ha="center", fontsize=8.5, color=MUTED)
    style_ax(fig, ax, "McLaren: 9th to back-to-back champions",
             "Final constructor championship position, by season")
    fig.savefig(OUT_DIR / "02_mclaren_trajectory.png", dpi=150)
    plt.close(fig)

    # pit crews since the cap
    pits = con.execute("""
        with reasonable_stops as (
            select p.*, r.constructor_id
            from pitstops p join results r using (season, round, driver_id)
            where p.duration_sec is not null and p.duration_sec < 60 and p.season >= 2021)
        select constructor_id, avg(duration_sec) as avg_dur, count(*) as n
        from reasonable_stops group by constructor_id having count(*) > 50 order by avg_dur
    """).df()
    fig, ax = plt.subplots(figsize=(9.5, 6.5))
    colors = [GOOD if i < 3 else (BAD if i >= len(pits) - 3 else MUTED) for i in range(len(pits))]
    ax.barh(pits.constructor_id[::-1], pits.avg_dur[::-1], color=colors[::-1], zorder=3)
    ax.set_xlim(23, pits.avg_dur.max() + 0.5)
    style_ax(fig, ax, "The pit crew league table",
             "Average pit stop duration, post-cap era (2021-2026), stops under 60s only")
    fig.subplots_adjust(left=0.18)
    fig.savefig(OUT_DIR / "03_pit_crew_league_table.png", dpi=150)
    plt.close(fig)

    # HHI + number of winners, before/after
    hhi = con.execute("select season, hhi from constructor_hhi_by_season order by season").df()
    winners = con.execute("""
        select season, count(distinct constructor_id) as n
        from fact_results where position_order = 1 group by season order by season
    """).df()
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11, 5))
    ax1.bar(hhi.season.astype(str), hhi.hhi, color=[MUTED if s < 2021 else ACCENT for s in hhi.season], zorder=3)
    ax1.axhline(2500, color=BAD, linewidth=1, linestyle=":")
    ax1.text(0, 2540, "Antitrust 'highly concentrated' threshold (2,500)", fontsize=8, color=BAD)
    ax1.set_title("Constructor points HHI", fontsize=11, loc="left", color=INK)
    ax1.spines[["top", "right"]].set_visible(False)
    ax1.spines[["left", "bottom"]].set_color(GRID)
    ax1.grid(axis="y", color=GRID, linewidth=0.8, zorder=0)
    ax1.set_axisbelow(True)
    ax1.tick_params(length=0, axis="x", rotation=90)

    ax2.bar(winners.season.astype(str), winners.n, color=[MUTED if s < 2021 else ACCENT2 for s in winners.season], zorder=3)
    ax2.set_title("Distinct race winners", fontsize=11, loc="left", color=INK)
    ax2.spines[["top", "right"]].set_visible(False)
    ax2.spines[["left", "bottom"]].set_color(GRID)
    ax2.grid(axis="y", color=GRID, linewidth=0.8, zorder=0)
    ax2.set_axisbelow(True)
    ax2.tick_params(length=0, axis="x", rotation=90)

    fig.suptitle("Market concentration, two ways", fontsize=14, fontweight="bold", color=INK, x=0.02, y=0.98, ha="left")
    fig.text(0.02, 0.90, "Herfindahl-Hirschman Index on points share (left) vs. how many teams actually won a race (right)",
              fontsize=10, color=MUTED, ha="left")
    fig.subplots_adjust(top=0.78, bottom=0.18, wspace=0.25)
    fig.savefig(OUT_DIR / "04_hhi_and_winners.png", dpi=150)
    plt.close(fig)

    # fastest to slowest gap
    gap = con.execute("""
        select season, round(100.0*(max(points)-min(points))/nullif(max(points),0),1) as gap_pct
        from constructor_standings where points > 0 group by season order by season
    """).df()
    fig, ax = plt.subplots(figsize=(9.5, 5))
    ax.plot(gap.season.astype(str), gap.gap_pct, marker="o", color=BAD, linewidth=2, zorder=3)
    ax.set_ylim(90, 101)
    ax.yaxis.set_major_formatter(mticker.PercentFormatter())
    ax.axvline(6.5, color=INK, linewidth=1, linestyle="--", alpha=0.4)
    style_ax(fig, ax, "What the cap DIDN'T fix: the back of the grid",
             "Gap between the top and bottom constructor's points, as % of the leader's total")
    fig.savefig(OUT_DIR / "05_fastest_to_slowest_gap.png", dpi=150)
    plt.close(fig)

    con.close()
    print(f"Wrote 5 chart previews to {OUT_DIR}/")


if __name__ == "__main__":
    main()
