module WorkDashboard exposing (Model, Msg(..), Overview, Work, clear, init, main, overviewDecoder, start, update, view, workDecoder)

import Browser
import Browser.Dom
import Browser.Events
import Dict exposing (Dict)
import Frontend.Http as Request
import Frontend.Money as Money
import Html exposing (..)
import Html.Attributes as A
import Html.Events exposing (onClick, onInput, onSubmit)
import Json.Decode as D
import Ports
import Task
import Url


type alias Kpi =
    { label : String, value : Int, hint : String, category : String, stage : String, severity : String }


type alias Stage =
    { stage : String, count : Int }


type alias Overview =
    { today : String, team : ( String, String, Bool ), kpi : List Kpi, stages : List Stage, documents : Dict String Int, payments : D.Value, teams : List D.Value }


type alias Work =
    { today : String, total : Int, scope : String, category : String, teamId : String, teamName : String, counts : Dict String Int, items : List D.Value }


type alias Filters =
    { scope : String, team : String, teamName : String, category : String, stage : String, title : String, offset : Int, dashboard : Bool }


type alias Model =
    { userId : String, pageSize : Int, overview : Maybe Overview, work : Maybe Work, overviewScope : String, overviewTeam : String, filters : Filters, overviewGeneration : Int, workGeneration : Int, overviewLoading : Bool, workLoading : Bool, overviewError : String, workError : String }


type Msg
    = OverviewScope String
    | OverviewTeam String
    | RefreshOverview
    | OverviewLoaded String Int (Result String Overview)
    | Assignment String
    | Select String String String Bool
    | ClearBranch
    | ClearCategory
    | AllAccessible
    | RefreshWork
    | WorkLoaded String Int (Result String Work)
    | Page Int
    | Focused (Result Browser.Dom.Error ())
    | Viewport Int
    | StartWork Int


init : Model
init =
    { userId = "", pageSize = 25, overview = Nothing, work = Nothing, overviewScope = "mine", overviewTeam = "", filters = { scope = "mine", team = "", teamName = "", category = "", stage = "", title = "All work", offset = 0, dashboard = False }, overviewGeneration = 0, workGeneration = 0, overviewLoading = False, workLoading = False, overviewError = "", workError = "" }


clear : Model -> Model
clear model =
    { init | overviewGeneration = model.overviewGeneration + 1, workGeneration = model.workGeneration + 1 }


optionalString : String -> D.Decoder String
optionalString key =
    D.oneOf [ D.field key D.string, D.succeed "" ]


overviewDecoder : D.Decoder Overview
overviewDecoder =
    D.map7 Overview
        (D.field "today" D.string)
        (D.map3 (\id name selectable -> ( id, name, selectable )) (D.field "teamId" D.string) (D.field "teamName" D.string) (D.field "teamSelectable" D.bool))
        (D.field "kpi" (D.list (D.map6 Kpi (D.field "label" D.string) (D.field "value" D.int) (D.field "hint" D.string) (D.field "category" D.string) (optionalString "stage") (optionalString "severity"))))
        (D.field "caseStages" (D.list (D.map2 Stage (D.field "stage" D.string) (D.field "count" D.int))))
        (D.field "documentCompleteness" (D.dict D.int))
        (D.field "paymentsDue" D.value)
        (D.field "teams" (D.list D.value))


workDecoder : D.Decoder Work
workDecoder =
    D.map8 Work (D.field "today" D.string) (D.field "total" D.int) (D.field "scope" D.string) (D.field "category" D.string) (D.field "teamId" D.string) (D.field "teamName" D.string) (D.field "counts" (D.dict D.int)) (D.field "items" (D.list D.value))
        |> D.andThen (\data -> if data.total < 0 || not (List.member data.scope [ "mine", "all", "unassigned" ]) then D.fail "Invalid work totals or scope" else D.succeed data)


start : String -> Model -> ( Model, Cmd Msg )
start userId model =
    let
        current = if userId == model.userId then model else let reset = clear model in { reset | userId = userId }
        ( overview, overviewCmd ) = update RefreshOverview current
    in
    ( overview, Cmd.batch [ overviewCmd, Browser.Dom.getViewport |> Task.perform (\viewport -> StartWork (round viewport.viewport.width)) ] )


loadWork : Model -> ( Model, Cmd Msg )
loadWork model =
    let
        f = model.filters
        generation = model.workGeneration + 1
        query = "scope=" ++ Url.percentEncode f.scope ++ "&focus=adviser&category=" ++ Url.percentEncode f.category ++ "&offset=" ++ String.fromInt f.offset ++ "&limit=" ++ String.fromInt model.pageSize ++ (if f.stage /= "" then "&stage=" ++ Url.percentEncode f.stage else "") ++ (if f.team /= "" then "&team=" ++ Url.percentEncode f.team else "") ++ (if f.dashboard then "&dashboard=1" else "")
    in
    ( { model | workGeneration = generation, workLoading = True, workError = "", work = Nothing }, Request.get ("/api/my-work?" ++ query) workDecoder (WorkLoaded model.userId generation) )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let f = model.filters in
    case msg of
        RefreshOverview ->
            let generation = model.overviewGeneration + 1 in
            ( { model | overviewGeneration = generation, overviewLoading = True, overviewError = "" }, Request.get ("/api/dashboard/overview?scope=" ++ Url.percentEncode model.overviewScope ++ (if model.overviewTeam == "" then "" else "&team=" ++ Url.percentEncode model.overviewTeam)) overviewDecoder (OverviewLoaded model.userId generation) )
        OverviewScope scope -> update RefreshOverview { model | overviewScope = if List.member scope [ "mine", "all", "unassigned" ] then scope else "mine" }
        OverviewTeam team ->
            if model.overview |> Maybe.map (\data -> let ( _, _, selectable ) = data.team in selectable) |> Maybe.withDefault False then update RefreshOverview { model | overviewTeam = team } else ( model, Cmd.none )
        OverviewLoaded userId generation result ->
            if userId /= model.userId || generation /= model.overviewGeneration then ( model, Cmd.none ) else
            case result of
                Err message -> ( { model | overviewLoading = False, overviewError = message, overview = Nothing }, Cmd.none )
                Ok data ->
                    let ( teamId, _, _ ) = data.team in
                    if teamId /= model.overviewTeam then ( { model | overviewLoading = False, overviewError = "The server did not apply the branch filter. Refresh overview to retry.", overview = Nothing }, Cmd.none ) else ( { model | overviewLoading = False, overview = Just data }, Cmd.none )
        Assignment scope -> loadWork { model | filters = { f | scope = if List.member scope [ "mine", "all", "unassigned" ] then scope else "mine", offset = 0 } }
        Select category stage title fromDashboard ->
            if not (List.member category (List.map Tuple.first categories ++ [ "followupsToday", "followupsUpcoming", "documentsComplete", "invoicesOverdue", "invoicesDueSoon", "caseStages" ])) || (fromDashboard && (model.overviewLoading || model.overviewError /= "")) then ( model, Cmd.none ) else
            let
                teamName = model.overview |> Maybe.map (\data -> let ( _, name, _ ) = data.team in name) |> Maybe.withDefault ""
                selected = { f | category = category, stage = if category == "caseStages" then stage else "", title = if stage == "" then title else "Applications by stage · " ++ stage, offset = 0, dashboard = fromDashboard, scope = if fromDashboard then model.overviewScope else f.scope, team = if fromDashboard then model.overviewTeam else f.team, teamName = if fromDashboard then teamName else f.teamName }
                ( next, cmd ) = loadWork { model | filters = selected }
            in
            ( next, Cmd.batch [ cmd, Browser.Dom.focus "selected-work-title" |> Task.attempt Focused ] )
        ClearBranch -> loadWork { model | filters = { f | team = "", teamName = "", offset = 0 } }
        ClearCategory -> loadWork { model | filters = { f | category = "", stage = "", team = "", teamName = "", title = "All work", dashboard = False, offset = 0 } }
        AllAccessible -> loadWork { model | filters = { f | scope = "all", category = "", stage = "", team = "", teamName = "", title = "All work", dashboard = False, offset = 0 } }
        RefreshWork -> loadWork model
        WorkLoaded userId generation result ->
            if userId /= model.userId || generation /= model.workGeneration then ( model, Cmd.none ) else
            case result of
                Err message -> ( { model | workLoading = False, workError = message }, Cmd.none )
                Ok data ->
                    if data.category /= f.category || data.teamId /= f.team || data.scope /= f.scope then ( { model | workLoading = False, workError = "The server did not apply the work filter. Refresh work to retry.", work = Nothing }, Cmd.none ) else ( { model | workLoading = False, work = Just data, filters = { f | teamName = data.teamName } }, Ports.workReady () )
        Page offset ->
            if model.workLoading || offset < 0 || (model.work |> Maybe.map (\data -> offset >= data.total) |> Maybe.withDefault True) then ( model, Cmd.none ) else loadWork { model | filters = { f | offset = offset } }
        Focused _ -> ( model, Cmd.none )
        Viewport width ->
            let size = if width <= 640 then 10 else 25 in
            if size == model.pageSize then ( model, Cmd.none ) else loadWork { model | pageSize = size, filters = { f | offset = 0 } }
        StartWork width ->
            loadWork { model | pageSize = if width <= 640 then 10 else 25, filters = { f | offset = 0 } }


categories : List ( String, String )
categories =
    [ ( "deals", "Deals" ), ( "pipeline", "Open pipeline" ), ( "leads", "Leads" ), ( "students", "Students" ), ( "cases", "All applications" ), ( "applications", "Applications" ), ( "followups", "Follow-ups" ), ( "overdueLeads", "Overdue lead follow-ups" ), ( "documents", "Applications needing documents" ), ( "documentIssues", "Document follow-ups" ), ( "deadlines", "Due within 7 days / overdue" ), ( "tasks", "Tasks" ), ( "handoffs", "Pending handoffs" ), ( "overdueHandoffs", "Overdue handoffs" ), ( "pendingApprovals", "Receipts awaiting approval" ), ( "invoices", "Invoices requiring attention" ) ]


str : String -> D.Value -> String
str key json =
    D.decodeValue (D.field key D.string) json |> Result.withDefault ""


int : String -> D.Value -> Int
int key json =
    D.decodeValue (D.field key D.int) json |> Result.withDefault 0


rows : String -> D.Value -> List D.Value
rows key json =
    D.decodeValue (D.field key (D.list D.value)) json |> Result.withDefault []


btn : String -> Msg -> Bool -> Html Msg
btn title msg disabled =
    button [ A.type_ "button", A.class "secondary", A.disabled disabled, onClick msg ] [ text title ]


scopeOptions : String -> List (Html Msg)
scopeOptions selected =
    List.map (\( value, title ) -> option [ A.value value, A.selected (selected == value) ] [ text title ]) [ ( "mine", "Mine and unassigned" ), ( "unassigned", "Unassigned" ), ( "all", "All accessible work" ) ]


itemView : D.Value -> Html Msg
itemView item =
    let
        entity = str "entity" item
        route = str "route" item
        details_ = D.decodeValue (D.field "details" (D.list D.string)) item |> Result.withDefault []
        action = Dict.get entity (Dict.fromList [ ( "case", "Review application and next action" ), ( "lead", "Review lead and follow up" ), ( "deal", "Review deal and next action" ), ( "student", "Review student journey" ), ( "task", "Review and update task" ), ( "invoice", "Review balance and receipts" ), ( "handoff", "Review handoff" ), ( "document", "Review document requirement" ) ]) |> Maybe.withDefault "Review and take action"
        context = if entity == "case" then section [ A.class "work-item__details" ] (h4 [] [ text "Application context and requirements" ] :: List.map (\detail -> p [] [ text detail ]) details_) else details [ A.class "work-item__details" ] (summary [] [ text "More context" ] :: List.map (\detail -> p [] [ text detail ]) details_)
    in
    article [ A.class ("card work-item work-item--" ++ str "priority" item) ]
        [ a [ A.href route, A.class "work-item__title" ] [ text (str "name" item) ]
        , p [] [ text ("Needs attention: " ++ str "reason" item) ]
        , p [] [ text ("Next action: " ++ (if str "action" item == "" then "Choose the next action." else str "action" item)) ]
        , p [] [ text ("Responsible: " ++ (if str "owner" item == "" then "Unassigned" else str "owner" item)) ]
        , p [] [ text (if str "deadline" item == "" then "Deadline: Not set" else "Due " ++ str "deadline" item) ]
        , if entity == "case" && str "owner" item == "" then a [ A.href (route ++ "#handoff"), A.class "button secondary" ] [ text "Assign an officer" ] else text ""
        , if List.isEmpty details_ then text "" else context
        , a [ A.href route, A.class "button secondary", A.attribute "aria-label" (action ++ " — " ++ str "name" item) ] [ text action ] ]


workView : Model -> Html Msg
workView model =
    let
        f = model.filters
        data = model.work
        countCards totals =
            div [ A.class "work-counts" ] (categories |> List.filter (\( key, _ ) -> List.member key [ "deals", "pipeline", "leads", "students", "cases" ] == totals) |> List.map (\( key, title ) -> let count = data |> Maybe.map (\snapshot -> Dict.get key snapshot.counts |> Maybe.withDefault 0) |> Maybe.withDefault 0 in button [ A.type_ "button", A.class "work-count", A.attribute "aria-pressed" (if f.category == key then "true" else "false"), A.attribute "data-category" key, onClick (Select key "" title False) ] [ strong [] [ text (String.fromInt count) ], span [] [ text title ] ]))
        items = data |> Maybe.map .items |> Maybe.withDefault []
        total = data |> Maybe.map .total |> Maybe.withDefault 0
    in
    section [ A.class "tools daily-work" ]
        [ h2 [] [ text "My work today" ], p [] [ text "Choose a record below to take its next action. Unassigned work is included." ]
        , form [ A.class "toolbar", onSubmit RefreshWork ]
            [ label [] [ text "Show work", select [ A.name "scope", A.attribute "aria-label" "Work assignment", A.value f.scope, onInput Assignment ] (scopeOptions f.scope) ]
            , button [ A.type_ "submit", A.class "secondary", A.disabled model.workLoading ] [ text "Refresh work" ]
            , p [ A.attribute "data-work-branch" "", A.attribute "role" "status" ] [ text ("Branch: " ++ (if f.team == "" then "All accessible branches" else if f.teamName == "" then "Selected branch" else f.teamName)) ]
            , if f.team == "" then text "" else button [ A.type_ "button", A.class "secondary", A.attribute "data-clear-work-branch" "", onClick ClearBranch ] [ text "Clear branch filter" ] ]
        , data |> Maybe.map (\snapshot -> p [] [ text (snapshot.today ++ " · " ++ String.fromInt total ++ " work items · " ++ (if f.team == "" then "all accessible branches" else "selected branch")) ]) |> Maybe.withDefault (text "")
        , details [ A.class "journey-section" ] [ summary [] [ text "Filter attention by type" ], p [] [ text "Counts overlap: a record can be overdue and also need documents." ], countCards False ]
        , details [ A.class "journey-section" ] [ summary [] [ text "Browse all records" ], p [] [ text "All stages in the selected assignment view. Open pipeline excludes won and lost deals." ], countCards True ]
        , div [ A.class "actions" ] [ h3 [ A.id "selected-work-title", A.tabindex -1 ] [ text f.title ], if f.category == "" then text "" else btn "Show all work" ClearCategory False ]
        , if model.workError /= "" then p [ A.attribute "role" "alert" ] [ text model.workError ] else if model.workLoading then p [ A.attribute "role" "status" ] [ text ("Loading " ++ String.toLower f.title ++ "…") ] else text ""
        , div [ A.attribute "aria-label" "Matching work records", A.attribute "aria-busy" (if model.workLoading then "true" else "false") ]
            (if model.workLoading || model.workError /= "" then [] else if List.isEmpty items then [ p [] [ text (if f.category == "" then "No work items in this view. Choose All accessible work to check other assignments." else "No matching work items in this view. Choose Show all work or change the assignment filter.") ], div [ A.class "actions" ] [ btn "Check all accessible work" AllAccessible False, a [ A.href "/leads", A.class "button secondary" ] [ text "Create your first lead" ], a [ A.href "/cases", A.class "button secondary" ] [ text "Review applications" ], a [ A.href "/invoices", A.class "button secondary" ] [ text "Review invoices & payments" ] ] ] else List.map itemView items ++ [ div [ A.class "actions" ] [ span [] [ text (String.fromInt (f.offset + 1) ++ "–" ++ String.fromInt (min total (f.offset + List.length items)) ++ " of " ++ String.fromInt total) ], btn "Previous" (Page (f.offset - model.pageSize)) (f.offset == 0), btn "Next" (Page (f.offset + model.pageSize)) (f.offset + model.pageSize >= total) ] ])
        ]


panel : String -> String -> List (Html Msg) -> Html Msg
panel title note children =
    details [ A.class "dashboard-panel" ] (summary [] [ text title ] :: p [ A.class "dashboard-note" ] [ text note ] :: children)


tableView : List String -> List (List (Html Msg)) -> Html Msg
tableView headings values =
    table [ A.class "dashboard-table" ] [ thead [] [ tr [] (List.map (\heading -> th [ A.scope "col" ] [ text heading ]) headings) ], tbody [] (List.map (\row -> tr [] (List.indexedMap (\index cell -> if index == 0 then th [ A.scope "row" ] [ cell ] else td [] [ cell ]) row)) values) ]


overviewView : Model -> Html Msg
overviewView model =
    let
        data = model.overview
        ( _, teamName, selectable ) = data |> Maybe.map .team |> Maybe.withDefault ( "", "", False )
        selectWork key stage label = Select key stage label True
        simpleRows values = ul [ A.class "stage-list" ] (List.map (\( title, count, key ) -> li [] [ span [ A.class "stage-list__row" ] [ span [ A.class "stage-list__name" ] [ text title ], span [ A.class "stage-list__count" ] [ text (String.fromInt count) ] ], if key == "" then text "" else button [ A.type_ "button", A.class "secondary", A.attribute "aria-label" (title ++ ". Show matching records"), onClick (selectWork key "" title) ] [ text "Show records" ] ]) values)
        money currency value = currency ++ " " ++ Money.format value
        content snapshot =
            let documents = snapshot.documents
                count key = Dict.get key documents |> Maybe.withDefault 0
                highest = List.maximum (List.map .count snapshot.stages) |> Maybe.withDefault 0
                buckets = [ ( "Overdue", "overdue" ), ( "Due within seven days", "dueSoon" ), ( "Later", "later" ), ( "No due date recorded", "noDueDate" ) ]
                paymentRows ( title, key ) = let values = rows key snapshot.payments in if List.isEmpty values then text "" else div [] [ h4 [] [ text title ], tableView [ "Currency", "Outstanding", "Invoices" ] (List.map (\row -> [ text (str "currency" row), text (money (str "currency" row) (D.decodeValue (D.field "amount" D.float) row |> Result.withDefault 0)), text (String.fromInt (int "count" row)) ]) values) ]
            in
            [ div [ A.class "kpi-grid" ] (List.map (\kpi -> button [ A.type_ "button", A.class ("kpi" ++ (if kpi.severity == "" then "" else " kpi--attention")), A.attribute "data-category" kpi.category, A.attribute "data-stage" kpi.stage, A.attribute "aria-label" (kpi.label ++ ": " ++ String.fromInt kpi.value ++ ". " ++ kpi.hint ++ ". Show matching records"), A.disabled model.overviewLoading, onClick (selectWork kpi.category kpi.stage kpi.label) ] [ span [ A.class "kpi__label" ] [ text kpi.label ], strong [ A.class "kpi__value" ] [ text (String.fromInt kpi.value) ], span [ A.class "kpi__hint" ] [ text kpi.hint ] ]) snapshot.kpi)
            , div [ A.class "dashboard-grid" ]
                [ panel "Applications by stage" "Every stage your account can read. Choose a stage to open those applications."
                    [ if List.isEmpty snapshot.stages then p [] [ text "No applications are visible to this account." ] else ul [ A.class "stage-list" ] (List.map (\stage -> li [] [ button [ A.type_ "button", A.attribute "aria-label" (stage.stage ++ ": " ++ String.fromInt stage.count ++ " applications. Show matching records"), A.disabled model.overviewLoading, onClick (selectWork "caseStages" stage.stage "Applications by stage") ] [ span [ A.class "stage-list__name" ] [ text stage.stage ], span [ A.class "stage-list__count" ] [ text (String.fromInt stage.count) ], span [ A.class "stage-list__bar", A.attribute "aria-hidden" "true" ] [ span [ A.style "width" (String.fromInt (if highest == 0 then 0 else round (100 * toFloat stage.count / toFloat highest)) ++ "%") ] [] ] ] ]) snapshot.stages) ]
                , panel "Document completeness" "Accessible required documents only. An empty checklist is reported separately and is not treated as complete."
                    [ if count "applications" == 0 then p [] [ text "No active applications are visible to this account." ] else div []
                        [ div [ A.class "completeness", A.attribute "role" "img", A.attribute "aria-label" (String.fromInt (count "completePercent") ++ "% of active applications have every accessible required document verified") ] [ span [ A.style "width" (String.fromInt (clamp 0 100 (count "completePercent")) ++ "%") ] [] ]
                        , simpleRows [ ( "Applications with every required file verified", count "complete", "documentsComplete" ), ( "Applications still missing a required file", count "incomplete", "documents" ), ( "Applications with no required files recorded", count "noRequirements", "" ) ]
                        , p [] [ text (String.fromInt (count "requiredDocuments") ++ " required documents recorded · " ++ String.fromInt (count "verifiedDocuments") ++ " verified · " ++ String.fromInt (count "expiredDocuments") ++ " expired · " ++ String.fromInt (count "outstandingFiles") ++ " still outstanding") ] ] ] ]
            , panel "Payments due" "Amounts stay in their own currency and are never added together. Overdue is measured against the workspace date."
                (simpleRows [ ( "Overdue", int "overdueCount" snapshot.payments, "invoicesOverdue" ), ( "Due within seven days", int "dueSoonCount" snapshot.payments, "invoicesDueSoon" ), ( "Outstanding invoices in total", int "openCount" snapshot.payments, "invoices" ), ( "Receipts awaiting approval", int "pendingApprovals" snapshot.payments, "pendingApprovals" ) ] :: List.map paymentRows buckets ++ (if List.all (\( _, key ) -> List.isEmpty (rows key snapshot.payments)) buckets then [ p [] [ text "No outstanding balances are visible to this account." ] ] else []))
            , panel (if selectable then "Branch overview" else "My branch") "Operational figures per branch, limited to records each viewer may read."
                [ if List.isEmpty snapshot.teams then p [] [ text "No branch is assigned to this account." ] else branchTable selectable model snapshot.teams ] ]
    in
    section [ A.class "tools dashboard-overview" ]
        [ h2 [] [ text "Workspace overview" ], p [] [ text "Use these figures to filter My work today. Expand a breakdown for stages, documents, balances or branches." ]
        , div [ A.class "toolbar" ] [ label [] [ text "Show work", select [ A.name "scope", A.value model.overviewScope, onInput OverviewScope ] (scopeOptions model.overviewScope) ], if selectable then label [] [ text "Branch", select [ A.name "team", A.value model.overviewTeam, onInput OverviewTeam ] (option [ A.value "", A.selected (model.overviewTeam == "") ] [ text "All branches" ] :: (data |> Maybe.map (\snapshot -> List.map (\team -> option [ A.value (str "id" team), A.selected (str "id" team == model.overviewTeam) ] [ text (str "name" team) ]) snapshot.teams) |> Maybe.withDefault [])) ] else if teamName == "" then text "" else p [] [ text ("Branch: " ++ teamName) ], btn "Refresh overview" RefreshOverview model.overviewLoading ]
        , if model.overviewError /= "" then div [] [ p [ A.attribute "role" "status" ] [ text "Unavailable · open to retry" ], p [ A.attribute "role" "alert" ] [ text (model.overviewError ++ " Use Refresh overview to retry.") ] ] else p [ A.attribute "role" "status" ] [ text (if model.overviewLoading then "Loading the operational overview…" else data |> Maybe.map (\snapshot -> snapshot.today ++ " · figures for records you can read" ++ (if teamName == "" then "" else " in " ++ teamName) ++ ". Choose any figure to open the matching records.") |> Maybe.withDefault "") ]
        , div [ A.attribute "aria-busy" (if model.overviewLoading then "true" else "false") ] (data |> Maybe.map content |> Maybe.withDefault []) ]


branchTable : Bool -> Model -> List D.Value -> Html Msg
branchTable selectable model teams =
    table [ A.class "dashboard-table" ]
        [ thead [] [ tr [] (List.map (\heading -> th [ A.scope "col" ] [ text heading ]) [ "Branch", "Staff", "Active applications", "Open leads", "Follow-ups due", "Documents missing", "Payments overdue" ]) ]
        , tbody [] (List.map (\team ->
            let selected = str "id" team == model.overviewTeam in
            tr (if selected then [ A.attribute "aria-current" "true" ] else [])
                (th [ A.scope "row" ]
                    [ text (str "name" team)
                    , if selectable then button [ A.type_ "button", A.class "secondary", A.attribute "aria-label" ("Show the operational overview for " ++ str "name" team), A.disabled (selected || model.overviewLoading), onClick (OverviewTeam (str "id" team)) ] [ text (if selected then "Viewing" else "View") ] else text ""
                    ] :: List.map (\key -> td [] [ text (String.fromInt (int key team)) ]) [ "members", "activeCases", "openLeads", "followUpsDue", "documentsIncomplete", "invoicesOverdue" ])
            ) teams)
        ]


view : Model -> Html Msg
view model =
    div [ A.class "work-dashboard-elm" ] [ workView model, overviewView model ]


main : Program { userId : String } Model Msg
main =
    Browser.element { init = \flags -> start flags.userId init, update = update, view = view, subscriptions = \_ -> Browser.Events.onResize (\width _ -> Viewport width) }
