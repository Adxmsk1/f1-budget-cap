# F1 cost cap dashboard - adds the extra measures/columns to the model and writes the report pages.
# safe to re-run. afterwards run scripts/powerbi_tools/save_with_data.ps1 so it opens with data
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\scripts\powerbi_tools\pbir.ps1"
. "$PSScriptRoot\..\scripts\powerbi_tools\tmdl.ps1"

$def = Join-Path $PSScriptRoot 'F1 Budget Cap.SemanticModel\definition'
$rpt = Join-Path $PSScriptRoot 'F1 Budget Cap.Report'
# carbon + F1 red, team colours for the band along the top
$C.Ink = '#15151E'; $C.Muted = '#5E6470'; $C.Paper = '#EEF1F6'; $C.Rule = '#E1E1E6'
$C.Amber = '#E10600'   # F1 red - post-cap seasons / primary accent
$C.Accent = '#E10600'
$C.Teal = '#15151E'    # carbon - secondary series
$C.Grey = '#A7ADB5'    # pre-cap seasons
$C.Red = '#B3001B'; $C.Green = '#1E8E3E'
$Style.HeadFont = 'DIN'; $Style.Radius = 0; $Style.CardBar = '#E10600'
$Style.ContentsTitle = 'RUNNING ORDER'; $Style.ContentsNumber = 'L{0}   '
$TeamColours = [ordered]@{
    mercedes = '#27F4D2'; ferrari = '#E8002D'; red_bull = '#3671C6'; mclaren = '#FF8000'; aston_martin = '#229971'
    alpine = '#0093CC'; williams = '#005AFF'; rb = '#6692FF'; sauber = '#2BB24C'; haas = '#B6BABD'
    audi = '#6E6E6E'; cadillac = '#3A3A3A'; alphatauri = '#2B4562'; alfa = '#B12039'; toro_rosso = '#469BFF'
    racing_point = '#F596C8'; force_india = '#F596C8'; renault = '#FFD800'; lotus_f1 = '#B59410'
    caterham = '#0B6B3A'; manor = '#6E0000'; marussia = '#6E0000'
}
$Band = @('#E8002D', '#FF8000', '#27F4D2', '#3671C6', '#229971', '#0093CC', '#005AFF', '#6692FF', '#2BB24C', '#B6BABD')
$teamSwitch = ($TeamColours.Keys | ForEach-Object { "`"$_`", `"$($TeamColours[$_])`"" }) -join ', '

# model
# so the season slicer filters pit stops and qualifying too
Add-Relationship $def 'fact_pitstops.season' 'dim_season.season'
Add-Relationship $def 'fact_qualifying.season' 'dim_season.season'

# era for the slicer (sorted so pre-cap comes first)
Add-CalcColumn $def 'dim_season' 'era_sort' 'IF(dim_season[is_post_cap], 2, 1)' 'int64'
Add-CalcColumn $def 'dim_season' 'era' 'IF(dim_season[is_post_cap], "Post-cap (2021-26)", "Pre-cap (2014-20)")' 'string' 'era_sort'

# old measures, not used any more
Remove-Measures $def @('P1 Commentary', 'P2 Commentary', 'P3 Commentary', 'P4 Commentary', 'P5 Commentary', 'Pit Colour', 'Position Colour',
    'Avg Stop In View (s)', 'Gap To Fastest Crew (s)', 'Pit Crew Spread (s)', 'Equal-Team Equivalent')

$fcs = 'fact_constructor_standings'
Add-ToTable $def $fcs @(
    # shared
    @{ Name = 'Has Standings'; Expr = 'IF(CALCULATE(COUNTROWS(fact_constructor_standings), REMOVEFILTERS(dim_constructor)) > 0, 1)' }
    @{ Name = 'Selection Seasons Text'; Expr = @'
VAR n = COUNTROWS(VALUES(dim_season[season]))
VAR mn = MIN(dim_season[season])
VAR mx = MAX(dim_season[season])
RETURN SWITCH(TRUE(),
    n = 1, "the " & mn & " season",
    n = 13, "all 13 seasons from 2014 to 2026",
    n = mx - mn + 1, "the " & n & " seasons from " & mn & " to " & mx,
    n & " selected seasons between " & mn & " and " & mx)
'@ }
    @{ Name = 'Champion'; Expr = 'CALCULATE(FIRSTNONBLANK(fact_constructor_standings[constructor_name], 1), fact_constructor_standings[position] = 1, REMOVEFILTERS(dim_constructor))' }
    @{ Name = 'Runner Up'; Expr = 'CALCULATE(FIRSTNONBLANK(fact_constructor_standings[constructor_name], 1), fact_constructor_standings[position] = 2, REMOVEFILTERS(dim_constructor))' }
    @{ Name = 'Era Colour'; Expr = 'IF(SELECTEDVALUE(dim_season[is_post_cap]) = TRUE(), "#E10600", "#A7ADB5")' }
    @{ Name = 'Era Colour Teal'; Expr = 'IF(SELECTEDVALUE(dim_season[is_post_cap]) = TRUE(), "#15151E", "#A7ADB5")' }
    @{ Name = 'Team Colour'; Expr = "SWITCH(SELECTEDVALUE(dim_constructor[constructor_id]), $teamSwitch, `"#A7ADB5`")" }

    # chapter 1: title margins
    @{ Name = 'Title Margin (pts)'; Format = '#,0'; Expr = @'
VAR t = CALCULATETABLE(fact_constructor_standings, REMOVEFILTERS(dim_constructor))
VAR p1 = MAXX(FILTER(t, fact_constructor_standings[position] = 1), fact_constructor_standings[points])
VAR p2 = MAXX(FILTER(t, fact_constructor_standings[position] = 2), fact_constructor_standings[points])
RETURN IF(HASONEVALUE(dim_season[season]), p1 - p2)
'@ }
    @{ Name = 'Avg Title Margin'; Format = '#,0'; Expr = 'AVERAGEX(VALUES(dim_season[season]), [Title Margin (pts)])' }
    @{ Name = 'Pre-Cap Avg Title Margin'; Format = '#,0'; Expr = 'CALCULATE([Avg Title Margin], dim_season[is_post_cap] = FALSE())' }
    @{ Name = 'Post-Cap Avg Title Margin'; Format = '#,0'; Expr = 'CALCULATE([Avg Title Margin], dim_season[is_post_cap] = TRUE())' }
    @{ Name = 'Closest Title Fight'; Expr = @'
VAR t = FILTER(ADDCOLUMNS(VALUES(dim_season[season]), "m", [Title Margin (pts)], "c", [Champion]), NOT ISBLANK([m]))
VAR b = TOPN(1, t, [m], ASC, dim_season[season], DESC)
RETURN MAXX(b, dim_season[season]) & ": " & MAXX(b, [c]) & " by " & FORMAT(MAXX(b, [m]), "#,0")
'@ }
    @{ Name = 'Most Dominant Season'; Expr = @'
VAR t = FILTER(ADDCOLUMNS(VALUES(dim_season[season]), "m", [Title Margin (pts)], "c", [Champion]), NOT ISBLANK([m]))
VAR b = TOPN(1, t, [m], DESC, dim_season[season], DESC)
RETURN MAXX(b, dim_season[season]) & ": " & MAXX(b, [c]) & " by " & FORMAT(MAXX(b, [m]), "#,0")
'@ }
    @{ Name = 'Different Champions'; Format = '0'; Expr = '0 + COUNTROWS(CALCULATETABLE(VALUES(fact_constructor_standings[constructor_id]), fact_constructor_standings[position] = 1, REMOVEFILTERS(dim_constructor)))' }
    @{ Name = 'Champions List'; Expr = @'
VAR ch = CALCULATETABLE(SUMMARIZE(FILTER(fact_constructor_standings, fact_constructor_standings[position] = 1), fact_constructor_standings[constructor_name]), REMOVEFILTERS(dim_constructor))
VAR wc = ADDCOLUMNS(ch, "n", CALCULATE(COUNTROWS(fact_constructor_standings), fact_constructor_standings[position] = 1, REMOVEFILTERS(dim_constructor)))
RETURN CONCATENATEX(wc, fact_constructor_standings[constructor_name] & " (" & [n] & ")", ", ", [n], DESC)
'@ }
    @{ Name = 'Title Headline'; Expr = @'
VAR n = COUNTROWS(VALUES(dim_season[season]))
VAR preV = [Pre-Cap Avg Title Margin]
VAR postV = [Post-Cap Avg Title Margin]
VAR preC = CALCULATE([Different Champions], dim_season[is_post_cap] = FALSE())
VAR postC = CALCULATE([Different Champions], dim_season[is_post_cap] = TRUE())
RETURN SWITCH(TRUE(),
    n = 1, [Champion] & " won the " & MIN(dim_season[season]) & " constructors' title by " & FORMAT([Title Margin (pts)], "#,0") & " points over " & [Runner Up] & ".",
    NOT ISBLANK(preV) && NOT ISBLANK(postV), "Under the cap the average title margin fell from " & FORMAT(preV, "#,0") & " to " & FORMAT(postV, "#,0") & " points - and the title started changing hands: " & postC & " different champions, against " & preC & " before.",
    ISBLANK(postV), IF(preC = 1, "Before the cap one team won every title - ", "Before the cap the titles went to ") & [Champions List] & " - by " & FORMAT(preV, "#,0") & " points on average.",
    "Under the cap " & postC & " different teams have won the title, by " & FORMAT(postV, "#,0") & " points on average.")
'@ }
    @{ Name = 'Title Story'; Expr = @'
VAR nl = UNICHAR(10) & UNICHAR(10)
VAR n = COUNTROWS(VALUES(dim_season[season]))
VAR preV = [Pre-Cap Avg Title Margin]
VAR postV = [Post-Cap Avg Title Margin]
VAR overall = CALCULATE([Avg Title Margin], REMOVEFILTERS(dim_season))
VAR t = FILTER(ADDCOLUMNS(VALUES(dim_season[season]), "m", [Title Margin (pts)], "pc", CALCULATE(SELECTEDVALUE(dim_season[is_post_cap]))), NOT ISBLANK([m]))
VAR dom = TOPN(1, t, [m], DESC, dim_season[season], DESC)
VAR domPost = MAXX(dom, IF([pc], 1, 0)) = 1
VAR single =
    "The cap's headline promise was to stop one team out-spending everyone and running away with the championship, so the title margin - how far the champion finished ahead of the runner-up - is the first test." & nl &
    "In " & MIN(dim_season[season]) & ", " & [Champion] & " beat " & [Runner Up] & " by " & FORMAT([Title Margin (pts)], "#,0") & " points. " &
    IF(SELECTEDVALUE(dim_season[is_post_cap]), "It was a cost-cap season, with team spending limited to $" & FORMAT(MAX(dim_season[cap_usd_m]), "0") & "m.", "It was before the cost cap, when spending was effectively unlimited.") & nl &
    "Across all 13 seasons the average winning margin is " & FORMAT(overall, "#,0") & " points, so this title was " &
    IF([Title Margin (pts)] < overall * 0.5, "an unusually close fight.", IF([Title Margin (pts)] > overall * 1.5, "unusually one-sided.", "a fairly typical one."))
VAR multi =
    "The cap's headline promise was to stop one team out-spending everyone and running away with the championship, so the title margin - how far the champion finished ahead of the runner-up - is the first test." & nl &
    "Across " & [Selection Seasons Text] & ", the champion won by " & FORMAT([Avg Title Margin], "#,0") & " points on average. The closest fight was in " & [Closest Title Fight] & " points; the most one-sided in " & [Most Dominant Season] & " points." & nl &
    SWITCH(TRUE(),
        NOT ISBLANK(preV) && NOT ISBLANK(postV),
            "Pre-cap seasons here averaged " & FORMAT(preV, "#,0") & " points and post-cap seasons " & FORMAT(postV, "#,0") & ". " &
            IF(domPost, "Closer on average - yet the most lopsided season of all came under the cap. The cap has not stopped a team dominating; it has stopped the same team dominating year after year.", "Closer on average, and the most lopsided seasons all came before the cap."),
        ISBLANK(postV), "All of these seasons are before the cap. Clear the Era slicer to set them against the cap era.",
        "All of these seasons are under the cap. Clear the Era slicer to set them against the years before it.") & nl &
    "Titles in this period: " & [Champions List] & "."
RETURN IF(n = 1, single, multi)
'@ }

    # chapter 2: concentration
    @{ Name = 'Constructor HHI'; Format = '#,0'; Expr = @'
VAR tot = CALCULATE(SUM(fact_constructor_standings[points]), REMOVEFILTERS(dim_constructor))
RETURN IF(HASONEVALUE(dim_season[season]),
    CALCULATE(
        SUMX(VALUES(fact_constructor_standings[constructor_id]),
            (DIVIDE(CALCULATE(SUM(fact_constructor_standings[points])), tot) * 100) ^ 2),
        REMOVEFILTERS(dim_constructor)))
'@ }
    @{ Name = 'Avg HHI'; Format = '#,0'; Expr = 'AVERAGEX(VALUES(dim_season[season]), [Constructor HHI])' }
    @{ Name = 'Pre-Cap Avg HHI'; Format = '#,0'; Expr = 'CALCULATE([Avg HHI], dim_season[is_post_cap] = FALSE())' }
    @{ Name = 'Post-Cap Avg HHI'; Format = '#,0'; Expr = 'CALCULATE([Avg HHI], dim_season[is_post_cap] = TRUE())' }
    @{ Name = 'Equal Teams Card'; Expr = 'FORMAT(DIVIDE(10000, [Avg HHI]), "0.0") & " equal teams"' }
    @{ Name = 'Winners Headline'; Expr = @'
VAR n = COUNTROWS(VALUES(dim_season[season]))
VAR preW = [Pre-Cap Avg Winning Teams]
VAR postW = [Post-Cap Avg Winning Teams]
RETURN SWITCH(TRUE(),
    n = 1, [Winning Teams] & " different teams won races in " & MIN(dim_season[season]) & ", and the points were shared like " & [Equal Teams Card] & ".",
    NOT ISBLANK(preW) && NOT ISBLANK(postW), "A typical season now has " & FORMAT(postW, "0.0") & " race-winning teams, up from " & FORMAT(preW, "0.0") & " - and the points are shared a little more evenly.",
    ISBLANK(postW), "Before the cap, a typical season had just " & FORMAT([Avg Winning Teams], "0.0") & " race-winning teams.",
    "Under the cap, a typical season has " & FORMAT([Avg Winning Teams], "0.0") & " race-winning teams.")
'@ }
    @{ Name = 'Winners Story'; Expr = @'
VAR nl = UNICHAR(10) & UNICHAR(10)
VAR h = [Avg HHI]
VAR band = SWITCH(TRUE(), h < 1500, "unconcentrated", h < 2500, "moderately concentrated", "highly concentrated")
VAR nS = COUNTROWS(VALUES(dim_season[season]))
VAR teams = DIVIDE(CALCULATE(COUNTROWS(fact_constructor_standings), REMOVEFILTERS(dim_constructor)), nS)
VAR preH = [Pre-Cap Avg HHI]
VAR postH = [Post-Cap Avg HHI]
VAR preW = [Pre-Cap Avg Winning Teams]
VAR postW = [Post-Cap Avg Winning Teams]
RETURN
    "A title can be close while only two teams are ever in contention. So the second test looks at the whole field: how evenly the points are spread, and how many teams can actually win a race." & nl &
    "The top chart borrows a tool from competition regulators, the Herfindahl-Hirschman Index (HHI). Across " & [Selection Seasons Text] & " it averaged " & FORMAT(h, "#,0") & " - 'moderately concentrated' in regulator terms, and the same as if about " & FORMAT(DIVIDE(10000, h), "0.0") & " equally strong teams shared every point, although about " & FORMAT(teams, "0") & " teams took part." & nl &
    IF(nS = 1,
        [Winning Teams] & " different teams won at least one race that season.",
        "On average " & FORMAT([Avg Winning Teams], "0.0") & " teams won at least one race each season, and " & [Seasons With 4+ Winners] & " of these " & nS & " seasons had four or more different winners.") & nl &
    IF(NOT ISBLANK(preH) && NOT ISBLANK(postH),
        "Before the cap: HHI " & FORMAT(preH, "#,0") & " and " & FORMAT(preW, "0.0") & " winning teams a season. Under it: " & FORMAT(postH, "#,0") & " and " & FORMAT(postW, "0.0") & ". Both moved the right way, but modestly - a handful of teams still share almost everything.",
        "Clear the Era slicer to compare these seasons with the other side of 2021.")
'@ }

    # chapter 5: the rewards
    @{ Name = 'Back-of-Grid Gap %'; Format = '0.0%'; Expr = @'
VAR t = CALCULATETABLE(fact_constructor_standings, REMOVEFILTERS(dim_constructor))
VAR mx = MAXX(t, fact_constructor_standings[points])
VAR mn = MINX(FILTER(t, fact_constructor_standings[points] > 0), fact_constructor_standings[points])
RETURN IF(HASONEVALUE(dim_season[season]), DIVIDE(mx - mn, mx))
'@ }
    @{ Name = 'Avg Back-of-Grid Gap'; Format = '0.0%'; Expr = 'AVERAGEX(VALUES(dim_season[season]), [Back-of-Grid Gap %])' }
    @{ Name = 'Lowest Scorer Share'; Format = '0.0%'; Expr = '1 - [Avg Back-of-Grid Gap]' }
    @{ Name = 'Lowest Scorer Share (season)'; Format = '0.0%'; Expr = 'IF(HASONEVALUE(dim_season[season]), 1 - [Back-of-Grid Gap %])' }
    @{ Name = 'Narrowest Back-of-Grid Gap'; Expr = @'
VAR t = FILTER(ADDCOLUMNS(VALUES(dim_season[season]), "g", [Back-of-Grid Gap %]), NOT ISBLANK([g]))
VAR b = TOPN(1, t, [g], ASC, dim_season[season], DESC)
RETURN MAXX(b, dim_season[season]) & ": " & FORMAT(1 - MAXX(b, [g]), "0.0%")
'@ }
    @{ Name = 'Top 3 Points Share'; Format = '0%'; Expr = @'
VAR t = CALCULATETABLE(fact_constructor_standings, REMOVEFILTERS(dim_constructor))
RETURN IF(HASONEVALUE(dim_season[season]),
    DIVIDE(SUMX(TOPN(3, t, fact_constructor_standings[points], DESC), fact_constructor_standings[points]), SUMX(t, fact_constructor_standings[points])))
'@ }
    @{ Name = 'Team Points Share'; Format = '0.0%'; Expr = 'DIVIDE(SUM(fact_constructor_standings[points]), CALCULATE(SUM(fact_constructor_standings[points]), REMOVEFILTERS(dim_constructor)))' }
    @{ Name = 'Avg Top 3 Share'; Format = '0.0%'; Expr = 'AVERAGEX(VALUES(dim_season[season]), [Top 3 Points Share])' }
    @{ Name = 'Most Even Season'; Expr = @'
VAR t = FILTER(ADDCOLUMNS(VALUES(dim_season[season]), "s", [Top 3 Points Share]), NOT ISBLANK([s]))
VAR b = TOPN(1, t, [s], ASC, dim_season[season], DESC)
RETURN MAXX(b, dim_season[season]) & ": " & FORMAT(MAXX(b, [s]), "0%")
'@ }
    @{ Name = 'Points Headline'; Expr = @'
VAR n = COUNTROWS(VALUES(dim_season[season]))
VAR pre3 = CALCULATE([Avg Top 3 Share], dim_season[is_post_cap] = FALSE())
VAR post3 = CALCULATE([Avg Top 3 Share], dim_season[is_post_cap] = TRUE())
RETURN SWITCH(TRUE(),
    n = 1, "In " & MIN(dim_season[season]) & " the top three teams took " & FORMAT([Avg Top 3 Share], "0%") & " of all points; the lowest scorer got " & FORMAT([Lowest Scorer Share], "0.0%") & " of the champion's total.",
    NOT ISBLANK(pre3) && NOT ISBLANK(post3), "But the rewards still go to the front: the top three teams took " & FORMAT(pre3, "0%") & " of all points before the cap and " & FORMAT(post3, "0%") & " under it.",
    "In these seasons the top three teams took " & FORMAT([Avg Top 3 Share], "0%") & " of all points scored.")
'@ }
    @{ Name = 'Points Story'; Expr = @'
VAR nl = UNICHAR(10) & UNICHAR(10)
VAR pre3 = CALCULATE([Avg Top 3 Share], dim_season[is_post_cap] = FALSE())
VAR post3 = CALCULATE([Avg Top 3 Share], dim_season[is_post_cap] = TRUE())
VAR preL = CALCULATE([Lowest Scorer Share], dim_season[is_post_cap] = FALSE())
VAR postL = CALCULATE([Lowest Scorer Share], dim_season[is_post_cap] = TRUE())
RETURN
    "Closer cars do not automatically mean a fairer share of the rewards. Only the top ten finishers in each race score points - 25 for a win down to 1 for tenth - and the final points table also decides how prize money is shared. So a small pace deficit can still leave a team with almost nothing." & nl &
    "Across " & [Selection Seasons Text] & ", the three best teams took " & FORMAT([Avg Top 3 Share], "0%") & " of every point scored. The lowest-scoring team (of those that scored at all) finished with just " & FORMAT([Lowest Scorer Share], "0.0%") & " of the champion's total." & nl &
    IF(NOT ISBLANK(pre3) && NOT ISBLANK(post3),
        "Before the cap: top-three share " & FORMAT(pre3, "0%") & ", lowest scorer " & FORMAT(preL, "0.0%") & " of the champion. Under the cap: " & FORMAT(post3, "0%") & " and " & FORMAT(postL, "0.0%") & ". Qualifying gaps shrank by about a third, but the points barely moved - the cap has narrowed the field without yet spreading its rewards.",
        "Clear the Era slicer to compare these seasons with the other side of 2021.")
'@ }

    # chapter 6: team stories
    @{ Name = 'Team Has Standings'; Expr = 'IF(COUNTROWS(fact_constructor_standings) > 0, 1)' }
    @{ Name = 'Final Position'; Format = '\P0'; Expr = 'MIN(fact_constructor_standings[position])' }
    @{ Name = 'Worst Finish'; Format = '\P0'; Expr = 'MAX(fact_constructor_standings[position])' }
    @{ Name = 'Constructor Titles'; Format = '0'; Expr = '0 + COUNTROWS(FILTER(fact_constructor_standings, fact_constructor_standings[position] = 1))' }
    @{ Name = 'Selected Team'; Expr = 'SELECTEDVALUE(dim_constructor[constructor_name], "Several teams")' }
    @{ Name = 'Team Headline'; Expr = @'
VAR team = SELECTEDVALUE(dim_constructor[constructor_name])
VAR n = COUNTROWS(VALUES(fact_constructor_standings[season]))
VAR preV = CALCULATE(AVERAGE(fact_constructor_standings[position]), dim_season[is_post_cap] = FALSE())
VAR postV = CALCULATE(AVERAGE(fact_constructor_standings[position]), dim_season[is_post_cap] = TRUE())
RETURN SWITCH(TRUE(),
    ISBLANK(team), "Pick a single team in the Team slicer to follow its path through the cap era.",
    n = 1, team & " finished P" & MIN(fact_constructor_standings[position]) & " in " & MIN(fact_constructor_standings[season]) & ".",
    NOT ISBLANK(preV) && NOT ISBLANK(postV), team & " averaged P" & FORMAT(preV, "0.0") & " before the cap and P" & FORMAT(postV, "0.0") & " under it" &
        IF(postV < preV - 0.5, " - one of the cap era's risers.", IF(postV > preV + 0.5, " - it has gone backwards.", " - broadly unchanged.")),
    team & " averaged P" & FORMAT(AVERAGE(fact_constructor_standings[position]), "0.0") & " in these seasons.")
'@ }
    @{ Name = 'Team Story'; Expr = @'
VAR nl = UNICHAR(10) & UNICHAR(10)
VAR team = SELECTEDVALUE(dim_constructor[constructor_name])
VAR yrs = VALUES(fact_constructor_standings[season])
VAR n = COUNTROWS(yrs)
VAR first = MINX(yrs, fact_constructor_standings[season])
VAR last = MAXX(yrs, fact_constructor_standings[season])
VAR best = MIN(fact_constructor_standings[position])
VAR worst = MAX(fact_constructor_standings[position])
VAR bestYrs = CONCATENATEX(FILTER(yrs, CALCULATE(MIN(fact_constructor_standings[position])) = best), fact_constructor_standings[season], ", ", fact_constructor_standings[season], ASC)
VAR worstYrs = CONCATENATEX(FILTER(yrs, CALCULATE(MIN(fact_constructor_standings[position])) = worst), fact_constructor_standings[season], ", ", fact_constructor_standings[season], ASC)
VAR titles = [Constructor Titles]
VAR intro = "Averages hide individual stories. If the cap levelled the field, teams stuck in the midfield should be able to climb - and some of the old leaders should slip."
VAR mcl = IF(team = "McLaren", nl & "McLaren is the cap era's clearest underdog story: 9th in 2015 and 2017 during a troubled engine partnership, then a rebuild that ended in back-to-back constructors' titles in 2024 and 2025 - its first since 1998.", "")
RETURN IF(ISBLANK(team),
    intro & nl & "Several teams are selected, so the charts show the best position any of them reached each season and their combined points. Pick one team to follow its own story.",
    IF(n = 1,
        intro & nl & "In " & first & ", " & team & " finished P" & best & " with " & FORMAT(SUM(fact_constructor_standings[points]), "#,0") & " points" & IF(best = 1, " - champions.", ".") & " Clear the Season slicer to see how that fits its longer path." & mcl,
        intro & nl & team & " appears in " & n & " of the selected seasons (" & first & "-" & last & "). Its best finish was P" & best & " (" & bestYrs & ") and its worst P" & worst & " (" & worstYrs & "); it averaged P" & FORMAT(AVERAGE(fact_constructor_standings[position]), "0.0") & " and won " & IF(titles = 0, "no titles", titles & IF(titles = 1, " title", " titles")) & "." & mcl))
'@ }

    # verdict scorecard (always all seasons)
    @{ Name = 'V Title Margin'; Expr = 'FORMAT(CALCULATE([Avg Title Margin], REMOVEFILTERS(dim_season), dim_season[is_post_cap] = FALSE()), "#,0") & "  " & UNICHAR(8594) & "  " & FORMAT(CALCULATE([Avg Title Margin], REMOVEFILTERS(dim_season), dim_season[is_post_cap] = TRUE()), "#,0") & " pts"' }
    @{ Name = 'V Champions'; Expr = 'CALCULATE([Different Champions], REMOVEFILTERS(dim_season), dim_season[is_post_cap] = FALSE()) & "  " & UNICHAR(8594) & "  " & CALCULATE([Different Champions], REMOVEFILTERS(dim_season), dim_season[is_post_cap] = TRUE()) & " teams"' }
    @{ Name = 'V Race Winners'; Expr = 'FORMAT(CALCULATE([Avg Winning Teams], REMOVEFILTERS(dim_season), dim_season[is_post_cap] = FALSE()), "0.0") & "  " & UNICHAR(8594) & "  " & FORMAT(CALCULATE([Avg Winning Teams], REMOVEFILTERS(dim_season), dim_season[is_post_cap] = TRUE()), "0.0") & " teams"' }
    @{ Name = 'V HHI'; Expr = 'FORMAT(CALCULATE([Avg HHI], REMOVEFILTERS(dim_season), dim_season[is_post_cap] = FALSE()), "#,0") & "  " & UNICHAR(8594) & "  " & FORMAT(CALCULATE([Avg HHI], REMOVEFILTERS(dim_season), dim_season[is_post_cap] = TRUE()), "#,0")' }
    @{ Name = 'V Top 3 Share'; Expr = 'FORMAT(CALCULATE([Avg Top 3 Share], REMOVEFILTERS(dim_season), dim_season[is_post_cap] = FALSE()), "0%") & "  " & UNICHAR(8594) & "  " & FORMAT(CALCULATE([Avg Top 3 Share], REMOVEFILTERS(dim_season), dim_season[is_post_cap] = TRUE()), "0%")' }
)

Add-ToTable $def 'fact_results' @(
    @{ Name = 'Winning Teams'; Format = '0'; Expr = 'CALCULATE(DISTINCTCOUNT(fact_results[constructor_id]), fact_results[position_order] = 1, REMOVEFILTERS(dim_constructor))' }
    @{ Name = 'Avg Winning Teams'; Format = '0.0'; Expr = 'AVERAGEX(VALUES(dim_season[season]), [Winning Teams])' }
    @{ Name = 'Seasons With 4+ Winners'; Format = '0'; Expr = '0 + COUNTROWS(FILTER(VALUES(dim_season[season]), [Winning Teams] >= 4))' }
    @{ Name = 'Pre-Cap Avg Winning Teams'; Format = '0.0'; Expr = 'CALCULATE([Avg Winning Teams], dim_season[is_post_cap] = FALSE())' }
    @{ Name = 'Post-Cap Avg Winning Teams'; Format = '0.0'; Expr = 'CALCULATE([Avg Winning Teams], dim_season[is_post_cap] = TRUE())' }
)

Add-ToTable $def 'fact_qualifying' @(
    @{ Name = 'Qualifying Spread %'; Format = '0.00%'; Expr = @'
CALCULATE(
    AVERAGEX(
        SUMMARIZE(fact_qualifying, fact_qualifying[season], fact_qualifying[round]),
        VAR teams = ADDCOLUMNS(CALCULATETABLE(VALUES(fact_qualifying[constructor_id])), "best", CALCULATE(MIN(fact_qualifying[best_sec]), fact_qualifying[best_sec] < 1000))
        VAR f = MINX(teams, [best])
        VAR s = MAXX(teams, [best])
        RETURN DIVIDE(s - f, f)),
    REMOVEFILTERS(dim_constructor))
'@ }
    @{ Name = 'V Pace Gap'; Expr = 'FORMAT(CALCULATE([Qualifying Spread %], REMOVEFILTERS(dim_season), dim_season[is_post_cap] = FALSE()), "0.00%") & "  " & UNICHAR(8594) & "  " & FORMAT(CALCULATE([Qualifying Spread %], REMOVEFILTERS(dim_season), dim_season[is_post_cap] = TRUE()), "0.00%")' }
    @{ Name = 'Pre-Cap Avg Qualifying Spread'; Format = '0.00%'; Expr = 'CALCULATE([Qualifying Spread %], dim_season[is_post_cap] = FALSE())' }
    @{ Name = 'Post-Cap Avg Qualifying Spread'; Format = '0.00%'; Expr = 'CALCULATE([Qualifying Spread %], dim_season[is_post_cap] = TRUE())' }
    @{ Name = 'Pace Spread Seconds'; Expr = 'FORMAT([Qualifying Spread %] * 90, "0.0") & "s per lap"' }
    @{ Name = 'Tightest Qualifying Season'; Expr = @'
VAR t = FILTER(ADDCOLUMNS(VALUES(dim_season[season]), "q", [Qualifying Spread %]), NOT ISBLANK([q]))
VAR b = TOPN(1, t, [q], ASC, dim_season[season], DESC)
RETURN MAXX(b, dim_season[season]) & ": " & FORMAT(MAXX(b, [q]), "0.00%")
'@ }
    @{ Name = 'Team Quali Gap %'; Format = '0.00%'; Expr = @'
CALCULATE(
    AVERAGEX(SUMMARIZE(fact_qualifying, fact_qualifying[season], fact_qualifying[round]),
        VAR tb = CALCULATE(MIN(fact_qualifying[best_sec]), fact_qualifying[best_sec] < 1000)
        VAR fb = CALCULATE(MIN(fact_qualifying[best_sec]), fact_qualifying[best_sec] < 1000, REMOVEFILTERS(dim_constructor))
        RETURN DIVIDE(tb - fb, fb)))
'@ }
    @{ Name = 'Team Quali Gap (latest season)'; Format = '0.00%'; Expr = @'
VAR y = MAX(dim_season[season])
RETURN CALCULATE([Team Quali Gap %], dim_season[season] = y)
'@ }
    @{ Name = 'Fastest Team On Average'; Expr = @'
VAR t = FILTER(ADDCOLUMNS(ALL(dim_constructor[constructor_name]), "g", [Team Quali Gap %]), NOT ISBLANK([g]))
VAR b = TOPN(1, t, [g], ASC, dim_constructor[constructor_name], ASC)
RETURN SUBSTITUTE(MAXX(b, dim_constructor[constructor_name]), " F1 Team", "") & ": " & FORMAT(MAXX(b, [g]), "0.00%") & " off"
'@ }
    @{ Name = 'Pace Team Title'; Expr = '"Each team''s average qualifying gap to the fastest car, " & MAX(dim_season[season]) & " (team colours)"' }
    @{ Name = 'Pace Headline'; Expr = @'
VAR n = COUNTROWS(VALUES(dim_season[season]))
VAR preQ = [Pre-Cap Avg Qualifying Spread]
VAR postQ = [Post-Cap Avg Qualifying Spread]
VAR q = [Qualifying Spread %]
RETURN SWITCH(TRUE(),
    n = 1, "In " & MIN(dim_season[season]) & " the slowest team qualified " & FORMAT(q, "0.00%") & " - about " & FORMAT(q * 90, "0.0") & " seconds a lap - behind the fastest.",
    NOT ISBLANK(preQ) && NOT ISBLANK(postQ), "The clearest change: the slowest team's qualifying deficit shrank from " & FORMAT(preQ, "0.00%") & " to " & FORMAT(postQ, "0.00%") & " of a lap - roughly " & FORMAT(preQ * 90, "0.0") & "s to " & FORMAT(postQ * 90, "0.0") & "s on a 90-second lap.",
    "In these seasons the slowest team qualified " & FORMAT(q, "0.00%") & " - about " & FORMAT(q * 90, "0.0") & " seconds a lap - behind the fastest.")
'@ }
    @{ Name = 'Pace Story'; Expr = @'
VAR nl = UNICHAR(10) & UNICHAR(10)
VAR preQ = [Pre-Cap Avg Qualifying Spread]
VAR postQ = [Post-Cap Avg Qualifying Spread]
VAR has26 = CONTAINS(VALUES(dim_season[season]), dim_season[season], 2026)
RETURN
    "Results depend on reliability, strategy and luck, but qualifying is the purest test of car speed: every team does its fastest possible lap, on the same track, on the same day. If the cap stopped rich teams buying extra performance, the field's pace should bunch up." & nl &
    "Across " & [Selection Seasons Text] & ", the slowest team was on average " & FORMAT([Qualifying Spread %], "0.00%") & " slower than the fastest - about " & FORMAT([Qualifying Spread %] * 90, "0.0") & " seconds on a 90-second lap. The tightest season was " & [Tightest Qualifying Season] & "." &
    IF(NOT ISBLANK(preQ) && NOT ISBLANK(postQ), " That gap fell by about " & FORMAT(1 - DIVIDE(postQ, preQ), "0%") & " once the cap arrived.", "") & nl &
    "One caution: 2022 also brought the biggest technical rule change in decades, designed to let cars race closely. The cap and the new rules pushed in the same direction, so their effects cannot be fully separated." &
    IF(has26, " 2026 brought another rule overhaul and a brand-new team, Cadillac, which is why the gap jumped back up.", "")
'@ }
)

Add-ToTable $def 'fact_pitstops' @(
    @{ Name = 'V Pit Edge'; Expr = @'
VAR cPre = CALCULATE([Champion Top-2 Crew Seasons], REMOVEFILTERS(dim_season), dim_season[is_post_cap] = FALSE())
VAR nPre = CALCULATE(COUNTROWS(VALUES(dim_season[season])), REMOVEFILTERS(dim_season), dim_season[is_post_cap] = FALSE())
VAR cPost = CALCULATE([Champion Top-2 Crew Seasons], REMOVEFILTERS(dim_season), dim_season[is_post_cap] = TRUE())
VAR nPost = CALCULATE(COUNTROWS(VALUES(dim_season[season])), REMOVEFILTERS(dim_season), dim_season[is_post_cap] = TRUE())
RETURN cPre & " of " & nPre & "  " & UNICHAR(8594) & "  " & cPost & " of " & nPost
'@ }
    @{ Name = 'Pit Has Data'; Expr = 'IF(NOT ISBLANK([Avg Pit Stop Duration (s)]), 1)' }
    @{ Name = 'Pit Stops Timed'; Format = '#,0'; Expr = 'CALCULATE(COUNTROWS(fact_pitstops), fact_pitstops[duration_sec] < 60)' }
    @{ Name = 'Fastest Pit Crew'; Expr = @'
VAR tbl = FILTER(ADDCOLUMNS(ALL(dim_constructor[constructor_name]), "v", [Avg Pit Stop Duration (s)]), NOT ISBLANK([v]))
VAR b = TOPN(1, tbl, [v], ASC, dim_constructor[constructor_name], ASC)
RETURN SUBSTITUTE(MAXX(b, dim_constructor[constructor_name]), " F1 Team", "") & " - " & FORMAT(MAXX(b, [v]), "0.00") & "s"
'@ }
    @{ Name = 'Slowest Pit Crew'; Expr = @'
VAR tbl = FILTER(ADDCOLUMNS(ALL(dim_constructor[constructor_name]), "v", [Avg Pit Stop Duration (s)]), NOT ISBLANK([v]))
VAR b = TOPN(1, tbl, [v], DESC, dim_constructor[constructor_name], ASC)
RETURN SUBSTITUTE(MAXX(b, dim_constructor[constructor_name]), " F1 Team", "") & " - " & FORMAT(MAXX(b, [v]), "0.00") & "s"
'@ }
    @{ Name = 'Pit Crew Gap (s)'; Format = '0.00\s'; Expr = @'
VAR t = FILTER(ADDCOLUMNS(ALL(dim_constructor[constructor_name]), "v", [Avg Pit Stop Duration (s)]), NOT ISBLANK([v]))
RETURN IF(HASONEVALUE(dim_season[season]), MAXX(t, [v]) - MINX(t, [v]))
'@ }
    @{ Name = 'Avg Pit Crew Gap (s)'; Format = '0.00\s'; Expr = 'AVERAGEX(VALUES(dim_season[season]), [Pit Crew Gap (s)])' }
    @{ Name = 'Champion Pit Rank'; Format = '0'; Expr = @'
VAR champ = CALCULATE(FIRSTNONBLANK(fact_constructor_standings[constructor_id], 1), fact_constructor_standings[position] = 1, REMOVEFILTERS(dim_constructor))
VAR t = FILTER(ADDCOLUMNS(ALL(dim_constructor[constructor_id]), "v", [Avg Pit Stop Duration (s)]), NOT ISBLANK([v]))
VAR cv = MAXX(FILTER(t, dim_constructor[constructor_id] = champ), [v])
RETURN IF(HASONEVALUE(dim_season[season]) && NOT ISBLANK(cv), COUNTROWS(FILTER(t, [v] < cv)) + 1)
'@ }
    @{ Name = 'Avg Champion Pit Rank'; Format = '0.0'; Expr = 'AVERAGEX(VALUES(dim_season[season]), [Champion Pit Rank])' }
    @{ Name = 'Champion Top-2 Crew Seasons'; Format = '0'; Expr = '0 + COUNTROWS(FILTER(VALUES(dim_season[season]), [Champion Pit Rank] <= 2))' }
    @{ Name = 'Pit Team Title'; Expr = '"Average pit stop by team, " & MAX(dim_season[season]) & " - fastest at the top"' }
    @{ Name = 'Avg Pit Stop (latest season)'; Format = '0.00'; Expr = @'
VAR y = MAX(dim_season[season])
RETURN CALCULATE([Avg Pit Stop Duration (s)], dim_season[season] = y)
'@ }
    @{ Name = 'Pit Headline'; Expr = @'
VAR n = COUNTROWS(VALUES(dim_season[season]))
VAR nPre = CALCULATE(COUNTROWS(VALUES(dim_season[season])), dim_season[is_post_cap] = FALSE())
VAR nPost = CALCULATE(COUNTROWS(VALUES(dim_season[season])), dim_season[is_post_cap] = TRUE())
VAR cPre = CALCULATE([Champion Top-2 Crew Seasons], dim_season[is_post_cap] = FALSE())
VAR cPost = CALCULATE([Champion Top-2 Crew Seasons], dim_season[is_post_cap] = TRUE())
RETURN SWITCH(TRUE(),
    n = 1, "In " & MIN(dim_season[season]) & " the champions, " & [Champion] & ", had the No. " & [Champion Pit Rank] & " pit crew; the fastest and slowest crews were " & FORMAT([Pit Crew Gap (s)], "0.00") & "s a stop apart.",
    nPre > 0 && nPost > 0, "The champion's pit-crew edge has faded: before the cap the champion had a top-two crew in " & cPre & " of " & nPre & " seasons; under it, in " & cPost & " of " & nPost & ".",
    "In these seasons the champion had a top-two pit crew in " & [Champion Top-2 Crew Seasons] & " of " & n & ", and the fastest and slowest crews were " & FORMAT([Avg Pit Crew Gap (s)], "0.00") & "s a stop apart.")
'@ }
    @{ Name = 'Pit Story'; Expr = @'
VAR nl = UNICHAR(10) & UNICHAR(10)
VAR preG = CALCULATE([Avg Pit Crew Gap (s)], dim_season[is_post_cap] = FALSE())
VAR postG = CALCULATE([Avg Pit Crew Gap (s)], dim_season[is_post_cap] = TRUE())
VAR preR = CALCULATE([Avg Champion Pit Rank], dim_season[is_post_cap] = FALSE())
VAR postR = CALCULATE([Avg Champion Pit Rank], dim_season[is_post_cap] = TRUE())
RETURN
    "Why pit stops? A stop is pure operations - people, rehearsal and equipment rather than car design - and most of that spending now counts against the cap. If money bought an operational edge, two things should happen under the cap: the gap between the slickest and slowest crews should narrow, and the richest teams should lose their automatic advantage." & nl &
    "Across " & [Selection Seasons Text] & ", the fastest and slowest crews were on average " & FORMAT([Avg Pit Crew Gap (s)], "0.00") & " seconds a stop apart, and the champion's crew ranked " & FORMAT([Avg Champion Pit Rank], "0.0") & " on average (1 = fastest)." & nl &
    IF(NOT ISBLANK(preG) && NOT ISBLANK(postG),
        "Before the cap the crew gap averaged " & FORMAT(preG, "0.00") & "s and the champion's crew ranked " & FORMAT(preR, "0.0") & "; under it, " & FORMAT(postG, "0.00") & "s and " & FORMAT(postR, "0.0") & ". The field has tightened a little, and half of the cap-era titles were won with only the third- or fourth-best crew - championship-winning operations are no longer something only the biggest budget can buy.",
        "Clear the Era slicer to compare these seasons with the other side of 2021.")
'@ }
)

# report
$src = 'Source: Jolpica F1 API (community successor to Ergast), seasons 2014-2026. 2026 is a partial season (17 rounds). Cost cap introduced 2021: $145m, stepping down to $135m by 2023.'
$seasonCat = (Proj (Col 'dim_season' 'season') 'Season')
$seasonSort = @{ field = (Col 'dim_season' 'season'); direction = 'Ascending' }
$chartW = 600
function Season-Era($p, $hasTable, $hasMeasure) {
    Header-Slicers @(
        , @("${p}_slicer_season", 'dim_season', 'season', 'Season', $hasTable, $hasMeasure)
        , @("${p}_slicer_era", 'dim_season', 'era', 'Era', $hasTable, $hasMeasure)
    )
}
function Era-Only($p, $hasTable, $hasMeasure) { Header-Slicers @(, @("${p}_slicer_era", 'dim_season', 'era', 'Era', $hasTable, $hasMeasure)) }
function Season-Only($p, $hasTable, $hasMeasure) { Header-Slicers @(, @("${p}_slicer_season", 'dim_season', 'season', 'Season', $hasTable, $hasMeasure)) }
function Era-Columns($name, [int[]]$pos, $table, $measure, $display, $title, $axisExtra = @{}) {
    $ax = Axis-Objects -Categorical @axisExtra
    New-Visual $name 'clusteredColumnChart' $pos `
        -Query @{ Category = (Role $seasonCat); Y = (Role (Proj (Meas $table $measure) $display)) } `
        -Sort $seasonSort `
        -Objects ($ax + @{
            dataPoint = @(PropsSel @{ fill = (MeasFill $fcs 'Era Colour') } (AllPoints))
            labels    = (Props @{ show = (L $true); color = (Solid $C.Muted); fontSize = (L 8D) })
        }) `
        -Container @{ title = (Title $title) }
}

$pages = @()
Set-Band $rpt $Band 'f1_band.png'

# Cover
# if there's a logo at assets\f1_logo.png it goes on the cover (not included - trademark)
$p = 'p0'; $script:Z = 0
Add-ReportImage $rpt (Join-Path $PSScriptRoot 'assets\cover.png') 'f1_cover.png'
$logo = $null
$logoFile = Join-Path $PSScriptRoot 'assets\f1_logo.png'
if (Test-Path $logoFile) { Add-ReportImage $rpt $logoFile 'f1_logo.png'; $logo = 'f1_logo.png' }
$v = Cover-Page -Prefix $p -ImageItem 'f1_cover.png' -PanelColor '#15151E' -KickerColor '#E10600' -LogoItem $logo `
    -Kicker 'Formula 1 and the cost cap, 2014-2026' `
    -TitleText 'Did the budget cap make F1 a fair fight?' `
    -SubtitleText 'In 2021 F1 capped team spending at $145m to end the era of financially dominant teams. Six seasons in, has it worked? Six tests, one verdict.' `
    -Contents @('At the top: closer title fights?', 'Who can win: more winners, less concentration?', 'Pace: did the cars get closer?', 'Operations: did the pit-crew edge fade?', 'The rewards: are the points shared more fairly?', 'Team stories - then the verdict') `
    -Footer 'Data: Jolpica F1 API - every result, qualifying session, pit stop and final standing, 2014-2026.' `
    -Cards @(
        , @($fcs, 'Cover Title Margin Shift', "Avg title-winning margin, before $([char]0x2192) after cap", $C.Ink)
        , @($fcs, 'Cover Biggest Title Margin', 'Biggest title margin: Red Bull 2023, post-cap', $C.Amber)
        , @($fcs, 'Cover McLaren Swing', 'McLaren: worst finish to back-to-back titles', '#FF8000')
    )
$pages += @{ Name = 'p0_cover'; DisplayName = 'Cover'; Visuals = $v }

# Chapter 1: at the top
$p = 'p1'; $script:Z = 0
$v = Page-Chrome $p "Title fights got closer - but dominance hasn't gone away" 'Points gap between champion and runner-up in the constructors'' championship. Grey = before the cap, red = under it.' $src (Era-Only $p $fcs 'Has Standings') $Band 'LAP 1/6   At the top'
$v += Card-Row $p @(
    , @($fcs, 'Avg Title Margin', 'Avg title-winning margin (pts)', $C.Ink)
    , @($fcs, 'Closest Title Fight', 'Closest title fight (pts)', $C.Green, 18)
    , @($fcs, 'Most Dominant Season', 'Most one-sided title (pts)', $C.Amber, 18)
    , @($fcs, 'Different Champions', 'Different champions', $C.Ink)
)
$v += Era-Columns "${p}_chart" @(20, 186, $chartW, 500) $fcs 'Title Margin (pts)' 'Title margin (pts)' 'Champion vs runner-up, constructor points'
$v += Story-Panel $p $fcs 'Title Headline' 'Title Story' 'Title margin = the champion''s final constructors'' points minus the runner-up''s. The constructors'' championship adds up both of a team''s cars. The cap limited performance spending to $145m from 2021 ($140m in 2022, $135m from 2023). Points totals grow with the number of races, and 2026 is a partial season.'
$pages += @{ Name = 'p1_title_fights'; DisplayName = '1 Title Fights'; Visuals = $v }

# Chapter 2: who can win
$p = 'p2'; $script:Z = 0
$v = Page-Chrome $p 'More teams win races, and points are shared a little more evenly' 'Top: points concentration (HHI, lower = more even). Bottom: different teams winning at least one race.' $src (Era-Only $p $fcs 'Has Standings') $Band 'LAP 2/6   Who can win'
$v += Card-Row $p @(
    , @($fcs, 'Avg HHI', 'Avg points concentration (HHI)', $C.Ink)
    , @($fcs, 'Equal Teams Card', 'Equivalent number of equal teams', $C.Ink, 20)
    , @('fact_results', 'Avg Winning Teams', 'Avg teams winning a race / season', $C.Amber)
    , @('fact_results', 'Seasons With 4+ Winners', 'Seasons where 4+ teams won', $C.Green)
)
$v += New-Visual "${p}_hhi" 'clusteredColumnChart' @(20, 186, $chartW, 245) `
    -Query @{ Category = (Role $seasonCat); Y = (Role (Proj (Meas $fcs 'Constructor HHI') 'HHI')) } `
    -Sort $seasonSort `
    -Objects ((Axis-Objects -Categorical -ValueStart 0 -ValueEnd 3000 -ValueFormatUnits 1) + @{
        dataPoint           = @(PropsSel @{ fill = (MeasFill $fcs 'Era Colour') } (AllPoints))
        labels              = (Props @{ show = (L $false) })
        y1AxisReferenceLine = @(PropsSel @{
                show = (L $true); value = (L 2500D); lineColor = (Solid $C.Red); style = (L 'dotted'); transparency = (L 0D)
                displayName = (L 'Highly concentrated (2,500)'); dataLabelShow = (L $true); dataLabelColor = (Solid $C.Red)
                dataLabelText = (L 'Name'); dataLabelHorizontalPosition = (L 'left'); dataLabelVerticalPosition = (L 'above')
            } @{ id = '1' })
    }) `
    -Container @{ title = (Title 'Points concentration (HHI) by season') }
$v += New-Visual "${p}_win" 'clusteredColumnChart' @(20, 441, $chartW, 245) `
    -Query @{ Category = (Role $seasonCat); Y = (Role (Proj (Meas 'fact_results' 'Winning Teams') 'Teams winning a race')) } `
    -Sort $seasonSort `
    -Objects ((Axis-Objects -Categorical -ValueStart 0 -ValueEnd 4.8) + @{
        dataPoint = @(PropsSel @{ fill = (MeasFill $fcs 'Era Colour Teal') } (AllPoints))
        labels    = (Props @{ show = (L $true); color = (Solid $C.Muted); fontSize = (L 9D) })
    }) `
    -Container @{ title = (Title 'Different teams winning at least one race') }
$v += Story-Panel $p $fcs 'Winners Headline' 'Winners Story' 'HHI = add up the square of each team''s percentage share of the season''s points. 10,000 means one team scored everything; ten equal teams would give 1,000. Regulators call 1,500-2,500 "moderately concentrated" and over 2,500 "highly concentrated". 10,000 / HHI = the number of equally strong teams that would give the same score.'
$pages += @{ Name = 'p2_who_can_win'; DisplayName = '2 Who Can Win'; Visuals = $v }

# Chapter 3: pace
$p = 'p3'; $script:Z = 0
$v = Page-Chrome $p 'The clearest change: the cars got closer on raw pace' 'Top: slowest team''s qualifying gap to the fastest, % of lap. Bottom: every team''s gap in the latest selected season.' $src (Season-Only $p $fcs 'Has Standings') $Band 'LAP 3/6   Pace'
$v += Card-Row $p @(
    , @('fact_qualifying', 'Qualifying Spread %', 'Avg gap, slowest to fastest team', $C.Amber)
    , @('fact_qualifying', 'Pace Spread Seconds', 'On a 90-second lap', $C.Ink, 20)
    , @('fact_qualifying', 'Tightest Qualifying Season', 'Tightest season', $C.Green, 20)
    , @('fact_qualifying', 'Fastest Team On Average', 'Closest to the front', $C.Ink, 20)
)
$v += Era-Columns "${p}_spread" @(20, 186, $chartW, 150) 'fact_qualifying' 'Qualifying Spread %' 'Qualifying gap' 'Slowest team''s qualifying gap to the fastest, % of lap time' @{ ValueStart = 0; ValueEnd = 0.075 }
$v += New-Visual "${p}_teams" 'clusteredBarChart' @(20, 344, $chartW, 342) `
    -Query @{ Category = (Role (Proj (Col 'dim_constructor' 'constructor_name') 'Team')); Y = (Role (Proj (Meas 'fact_qualifying' 'Team Quali Gap (latest season)') 'Gap to fastest')) } `
    -Sort @{ field = (Meas 'fact_qualifying' 'Team Quali Gap (latest season)'); direction = 'Ascending' } `
    -Objects ((Axis-Objects -ValueStart 0 -CatMargin 35 -CatPadding 5) + @{
        dataPoint    = @(PropsSel @{ fill = (MeasFill $fcs 'Team Colour') } (AllPoints))
        labels       = (Props @{ show = (L $true); color = (Solid $C.Ink); fontSize = (L 8D); labelPrecision = (L 2L) })
    }) `
    -Container @{ title = (Title -MeasureTable 'fact_qualifying' -Measure 'Pace Team Title') }
$v += Story-Panel $p 'fact_qualifying' 'Pace Headline' 'Pace Story' 'For each race weekend: (slowest team''s best qualifying lap - fastest team''s) / fastest team''s lap, averaged over the weekends selected. A percentage makes a 70-second lap at Monaco and a 105-second lap at Spa comparable. Laps where no time was set are excluded.'
$pages += @{ Name = 'p3_pace'; DisplayName = '3 Pace'; Visuals = $v }

# Chapter 4: operations
$p = 'p4'; $script:Z = 0
$v = Page-Chrome $p "Off the track too: the champion's pit-crew edge has faded" 'Top: fastest-to-slowest pit crew gap by season. Bottom: average stop by team in the latest selected season.' $src (Season-Only $p 'fact_pitstops' 'Pit Has Data') $Band 'LAP 4/6   Operations'
$v += Card-Row $p @(
    , @('fact_pitstops', 'Avg Pit Crew Gap (s)', 'Fastest-to-slowest crew gap', $C.Ink)
    , @('fact_pitstops', 'Avg Champion Pit Rank', "Champion's pit crew, avg rank", $C.Amber)
    , @('fact_pitstops', 'Fastest Pit Crew', 'Fastest crew', $C.Green, 17)
    , @('fact_pitstops', 'Slowest Pit Crew', 'Slowest crew', $C.Red, 17)
)
$v += Era-Columns "${p}_gap" @(20, 186, $chartW, 150) 'fact_pitstops' 'Pit Crew Gap (s)' 'Crew gap (s)' 'Gap between the fastest and slowest pit crew, seconds per stop' @{ ValueStart = 0 }
$v += New-Visual "${p}_teams" 'clusteredBarChart' @(20, 344, $chartW, 342) `
    -Query @{ Category = (Role (Proj (Col 'dim_constructor' 'constructor_name') 'Team')); Y = (Role (Proj (Meas 'fact_pitstops' 'Avg Pit Stop (latest season)') 'Avg stop (s)')) } `
    -Sort @{ field = (Meas 'fact_pitstops' 'Avg Pit Stop (latest season)'); direction = 'Ascending' } `
    -Objects ((Axis-Objects -ValueStart 20 -CatMargin 35 -CatPadding 5) + @{
        dataPoint    = @(PropsSel @{ fill = (MeasFill $fcs 'Team Colour') } (AllPoints))
        labels       = (Props @{ show = (L $true); color = (Solid $C.Ink); fontSize = (L 8D); labelPrecision = (L 2L) })
    }) `
    -Container @{ title = (Title -MeasureTable 'fact_pitstops' -Measure 'Pit Team Title') }
$v += Story-Panel $p 'fact_pitstops' 'Pit Headline' 'Pit Story' 'Pit stop time = pit-lane entry to exit (most of it is driving at the pit-lane speed limit), averaged per team; stops of 60 seconds or more - penalties, repairs, red flags - are excluded. Every team stops at the same tracks each season, so comparisons within a season are fair. Champion''s crew rank: 1 = the fastest crew that season.'
$pages += @{ Name = 'p4_operations'; DisplayName = '4 Operations'; Visuals = $v }

# Chapter 5: the rewards
$p = 'p5'; $script:Z = 0
$v = Page-Chrome $p 'But the rewards still go to the front' 'Top: each season''s points split by team, in team colours. Bottom: lowest scorer''s points as a share of the champion''s.' $src (Era-Only $p $fcs 'Has Standings') $Band 'LAP 5/6   The rewards'
$v += Card-Row $p @(
    , @($fcs, 'Avg Top 3 Share', 'Points won by the top three teams', $C.Amber)
    , @($fcs, 'Lowest Scorer Share', "Lowest scorer vs champion's points", $C.Red)
    , @($fcs, 'Most Even Season', 'Most evenly shared season', $C.Green, 20)
    , @($fcs, 'Narrowest Back-of-Grid Gap', 'Best season for the back markers', $C.Ink, 20)
)
# points split by team each season
$teamNames = Import-Csv (Join-Path $PSScriptRoot '..\data\processed\dim_constructor.csv') -Encoding UTF8
$teamFills = @($teamNames | Where-Object { $TeamColours.Contains($_.constructor_id) } | ForEach-Object {
    PropsSel @{ fill = (Solid $TeamColours[$_.constructor_id]) } (ValueSel 'dim_constructor' 'constructor_name' $_.constructor_name) })
$v += New-Visual "${p}_split" 'hundredPercentStackedColumnChart' @(20, 186, $chartW, 245) `
    -Query @{
        Category = (Role $seasonCat)
        Series   = (Role (Proj (Col 'dim_constructor' 'constructor_name') 'Team'))
        Y        = (Role (Proj (Meas $fcs 'Constructor Championship Points') 'Points'))
        Tooltips = (Role (Proj (Meas $fcs 'Team Points Share') 'Share of the season''s points'))
    } `
    -Sort $seasonSort `
    -Objects ((Axis-Objects -Categorical -ValueStart 0 -ValueEnd 1) + @{
        dataPoint = $teamFills
        legend    = (Props @{ show = (L $false) })
        labels    = (Props @{ show = (L $false) })
    }) `
    -Container @{ title = (Title 'Each season''s points, split by team (hover for team and share)') }
$v += Era-Columns "${p}_last" @(20, 441, $chartW, 245) $fcs 'Lowest Scorer Share (season)' 'Lowest scorer vs champion' "Lowest scorer's points as a share of the champion's" @{ ValueStart = 0 }
$v += Story-Panel $p $fcs 'Points Headline' 'Points Story' 'Top-three share = points won by the three highest-scoring teams / all constructors'' points that season. Lowest scorer = the lowest-placed team that scored at all; teams on zero points are left out so one pointless team does not define the back. Points go to the top 10 finishers only (25-18-15-12-10-8-6-4-2-1).'
$pages += @{ Name = 'p5_rewards'; DisplayName = '5 The Rewards'; Visuals = $v }

# Chapter 6: team stories
$p = 'p6'; $script:Z = 0
$slicers = Header-Slicers @(
    , @("${p}_slicer_season", 'dim_season', 'season', 'Season', $fcs, 'Team Has Standings')
    , @("${p}_slicer_team", 'dim_constructor', 'constructor_name', 'Team', $fcs, 'Team Has Standings', @('McLaren'), $true)
)
$v = Page-Chrome $p 'Team by team: who rose and who fell under the cap' 'Final constructors'' position (top) and points (bottom) by season - McLaren by default; choose any team.' $src $slicers $Band 'LAP 6/6   Team stories'
$v += Card-Row $p @(
    , @($fcs, 'Selected Team', 'Team shown', $C.Ink, 20)
    , @($fcs, 'Final Position', 'Best finish', $C.Green)
    , @($fcs, 'Worst Finish', 'Worst finish', $C.Red)
    , @($fcs, 'Constructor Titles', 'Constructors'' titles', $C.Amber)
)
$v += New-Visual "${p}_pos" 'clusteredColumnChart' @(20, 186, $chartW, 300) `
    -Query @{ Category = (Role $seasonCat); Y = (Role (Proj (Meas $fcs 'Final Position') 'Final position')) } `
    -Sort $seasonSort `
    -Objects ((Axis-Objects -Categorical -Invert -ValueStart 0 -ValueEnd 11 -HideValueAxis) + @{
        dataPoint = @(PropsSel @{ fill = (MeasFill $fcs 'Team Colour') } (AllPoints))
        labels    = (Props @{ show = (L $true); color = (Solid $C.Muted); fontSize = (L 9D) })
    }) `
    -Container @{ title = (Title 'Final championship position (1st at the top)') }
$v += New-Visual "${p}_pts" 'clusteredColumnChart' @(20, 496, $chartW, 190) `
    -Query @{ Category = (Role $seasonCat); Y = (Role (Proj (Meas $fcs 'Constructor Championship Points') 'Championship points')) } `
    -Sort $seasonSort `
    -Objects ((Axis-Objects -Categorical) + @{
        dataPoint = @(PropsSel @{ fill = (MeasFill $fcs 'Team Colour') } (AllPoints))
        labels    = (Props @{ show = (L $true); color = (Solid $C.Muted); fontSize = (L 8D); labelPosition = (L 'Above') })
    }) `
    -Container @{ title = (Title 'Constructors'' championship points') }
$v += Story-Panel $p $fcs 'Team Headline' 'Team Story' 'Final position = place in the constructors'' championship at the end of the season (10-11 teams, so P10 or P11 is last). Points grow with the number of races (17 to 24 a season) and 2026 is partial, so compare positions rather than raw points across years.'
$pages += @{ Name = 'p6_team_stories'; DisplayName = '6 Team Stories'; Visuals = $v }

# Verdict
$p = 'p7'; $script:Z = 0
$G = '#1E8E3E'; $A = '#D98A1C'; $N = '#8A9099'
$v = Verdict-Page -Prefix $p -Kicker 'CHEQUERED FLAG' -TitleText 'Closer at the front, not yet fairer at the back' `
    -SubtitleText 'Every test from the six chapters, before the cap (2014-20) and under it (2021-26). Values are season averages.' -Footer $src `
    -Rows @(
        , @($fcs, 'V Champions', 'Different champions', 'How many different teams won the constructors'' title in each era.', 'Changed', $G)
        , @($fcs, 'V Title Margin', 'Title-winning margin', 'Average points gap between champion and runner-up.', 'Slightly closer', $A)
        , @($fcs, 'V Race Winners', 'Teams winning races', 'Average number of different teams to win a race in a season.', 'Modest gain', $A)
        , @($fcs, 'V HHI', 'Points concentration (HHI)', 'Lower = points shared more evenly across the field.', 'Slightly better', $A)
        , @('fact_qualifying', 'V Pace Gap', 'Qualifying pace gap', 'Slowest team''s deficit to the fastest, % of a lap.', 'Clearly closer', $G)
        , @('fact_pitstops', 'V Pit Edge', 'Champion''s pit-crew edge', 'Seasons in which the champion had a top-two pit crew.', 'Faded', $G)
        , @($fcs, 'V Top 3 Share', 'Points won by the top three', 'Share of all points taken by the three best teams.', 'Barely moved', $N)
    ) `
    -Takeaways @(
        , @('Dominance became temporary', 'Mercedes won eight constructors'' titles in a row (2014-2021). Since then the title has passed between Red Bull, McLaren and Mercedes. But the cap has not made dominance impossible: Red Bull''s 2023 title, won by 451 points, was the most one-sided season of all.')
        , @('The cars got closer', 'The clearest effect is on raw speed. The slowest team''s qualifying deficit shrank by about a third. The 2022 rule overhaul pushed the same way, so the cap cannot take all the credit.')
        , @('Money no longer buys the best crew', 'Before the cap the champion had a top-two pit crew in six of seven seasons. Under the cap, half the titles were won with only the third- or fourth-best crew - operational excellence is more evenly spread.')
        , @('The rewards have not spread out', 'The top three teams still take around 70% of all points, and the back of the grid scores almost nothing, because points only go to the top ten finishers.')
        , @('So, did it work?', 'Partly. The cap has made F1 less predictable at the front and closer on pace, but not yet fairer for the teams at the back. Six seasons is a short record, and 2026 is incomplete and brings new rules - these are trends worth re-checking as more seasons arrive.')
    )
$pages += @{ Name = 'p7_verdict'; DisplayName = 'Verdict'; Visuals = $v }

Write-Report $rpt $pages $args[0]
"F1 dashboard written: $($pages.Count) pages"
