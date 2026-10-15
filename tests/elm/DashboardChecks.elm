module DashboardChecks exposing (checks)

import Json.Encode
import Dict
import WorkDashboard as Work


checks : List ( String, Bool )
checks =
    let
        loaded = Work.start "owner" Work.init |> Tuple.first
        overview = { today = "2026-10-15", team = ( "", "", True ), kpi = [], stages = [], documents = Dict.empty, payments = Json.Encode.null, teams = [] }
        ready = Work.update (Work.OverviewLoaded "owner" loaded.overviewGeneration (Ok overview)) loaded |> Tuple.first
        branch = Work.update (Work.OverviewTeam "north") ready |> Tuple.first
        branched = Work.update (Work.OverviewLoaded "owner" branch.overviewGeneration (Ok { overview | team = ( "north", "North branch", True ) })) branch |> Tuple.first
        assigned = Work.update (Work.OverviewScope "all") branched |> Tuple.first
        assignedReady = Work.update (Work.OverviewLoaded "owner" assigned.overviewGeneration (Ok { overview | team = ( "north", "North branch", True ) })) assigned |> Tuple.first
        stage = Work.update (Work.Select "caseStages" "Closed" "Applications by stage" True) assignedReady |> Tuple.first
        tasks = Work.update (Work.Select "tasks" "" "Tasks" False) stage |> Tuple.first
        changedScope = Work.update (Work.Assignment "unassigned") stage |> Tuple.first
        clearedBranch = Work.update Work.ClearBranch stage |> Tuple.first
        data = { today = "2026-10-15", total = 1, scope = stage.filters.scope, category = stage.filters.category, teamId = stage.filters.team, teamName = "North branch", counts = Dict.empty, items = [] }
        success = Work.update (Work.WorkLoaded "owner" stage.workGeneration (Ok data)) stage |> Tuple.first
        old = Work.update (Work.WorkLoaded "owner" stage.workGeneration (Ok data)) tasks |> Tuple.first
        incorrect = Work.update (Work.WorkLoaded "owner" stage.workGeneration (Ok { data | teamId = "" })) stage |> Tuple.first
        failure = Work.update (Work.WorkLoaded "owner" stage.workGeneration (Err "Unavailable")) stage |> Tuple.first
        newUser = Work.start "other" success |> Tuple.first
        foreign = Work.update (Work.WorkLoaded "owner" newUser.workGeneration (Ok data)) newUser |> Tuple.first
        member = Work.update (Work.OverviewLoaded "owner" loaded.overviewGeneration (Ok { overview | team = ( "", "General", False ) })) loaded |> Tuple.first
        disabledBranch = Work.update (Work.OverviewTeam "north") member |> Tuple.first
        mobile = Work.update (Work.Viewport 390) stage |> Tuple.first
        initialPhone = Work.update (Work.StartWork 320) loaded |> Tuple.first
        rotated = Work.update (Work.Viewport 1280) mobile |> Tuple.first
        cleared = Work.clear success
        again = Work.start "owner" cleared |> Tuple.first
        lateSession = Work.update (Work.WorkLoaded "owner" stage.workGeneration (Ok data)) again |> Tuple.first
        allAccessible = Work.update Work.AllAccessible stage |> Tuple.first
    in
    [ ( "Dashboard filtering copies branch and assignment into the work queue", stage.filters.team == "north" && stage.filters.teamName == "North branch" && stage.filters.scope == "all" && stage.filters.dashboard )
    , ( "Dashboard stage selection includes the stage", stage.filters.category == "caseStages" && stage.filters.stage == "Closed" )
    , ( "Selecting a non-stage category clears the previous stage", tasks.filters.stage == "" && tasks.filters.category == "tasks" && not tasks.filters.dashboard )
    , ( "Changing assignment preserves selected stage and branch", changedScope.filters.stage == "Closed" && changedScope.filters.team == "north" && changedScope.filters.scope == "unassigned" )
    , ( "Clearing a branch preserves the category", clearedBranch.filters.team == "" && clearedBranch.filters.category == "caseStages" && clearedBranch.filters.stage == "Closed" )
    , ( "Work filtering accepts a matching server response", success.work == Just data && not success.workLoading )
    , ( "Older work replies cannot replace a newer category", old == tasks )
    , ( "A server that ignores the branch cannot silently widen work", incorrect.work == Nothing && incorrect.workError /= "" )
    , ( "Work errors clear loading without discarding filters", not failure.workLoading && failure.workError == "Unavailable" && failure.filters == stage.filters )
    , ( "Dashboard work stays isolated between accounts", newUser.work == Nothing && newUser.overview == Nothing && foreign == newUser )
    , ( "Members cannot select another branch", disabledBranch == member )
    , ( "Mobile work pages use ten rows and keep the selected filters", mobile.pageSize == 10 && mobile.filters.category == stage.filters.category && mobile.filters.team == stage.filters.team )
    , ( "Old session replies cannot cross logout and same-user login", lateSession == again )
    , ( "Empty work recovery resets stale category and branch filters", allAccessible.filters.scope == "all" && allAccessible.filters.team == "" && allAccessible.filters.category == "" && allAccessible.filters.stage == "" )
    , ( "Initial phone work request uses ten rows", initialPhone.pageSize == 10 && initialPhone.workLoading )
    , ( "Rotating to desktop preserves filters and resets pagination", rotated.pageSize == 25 && rotated.filters.offset == 0 && rotated.filters.category == mobile.filters.category )
    ]
