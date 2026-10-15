module ManagementReport exposing (Model, Msg(..), Snapshot, activity, canExport, clear, csv, decoder, init, start, update, view)

import Dict exposing (Dict)
import Frontend.Date as Date
import Frontend.Http as Request
import Frontend.Money as Money
import Html exposing (..)
import Html.Attributes as A
import Html.Events exposing (onClick, onInput)
import Json.Decode as D
import Ports


type alias Metadata =
    { today : String, generatedAt : String, scopeLabel : String, currency : String, missingRates : List String }


type alias Counts =
    { contacts : Int, students : Int, leads : Int, activeCases : Int, openTasks : Int, totalCases : Int }


type alias Financial =
    { pipeline : Dict String Float, won : Dict String Float, balance : Dict String Float, pipelineTotal : Float, wonTotal : Float, balanceTotal : Float }


type alias Snapshot =
    { meta : Metadata, counts : Counts, financial : Financial, stageCounts : Dict String Int, stageCurrencies : Dict String (Dict String Float), caseStages : Dict String Int, createdCounts : Dict String Int }


type alias Model =
    { userId : String, generation : Int, data : Maybe Snapshot, loading : Bool, error : String, printError : Bool, period : String, from : String, to : String }


type Msg
    = Refresh
    | Loaded String Int (Result String Snapshot)
    | Period String
    | From String
    | To String
    | Download
    | Print
    | Printed Bool


init : Model
init =
    { userId = "", generation = 0, data = Nothing, loading = False, error = "", printError = False, period = "30", from = "", to = "" }


clear : Model -> Model
clear model =
    { init | generation = model.generation + 1 }


decoder : D.Decoder Snapshot
decoder =
    D.map7 Snapshot
        (D.map5 Metadata (D.field "today" D.string) (D.field "generatedAt" D.string) (D.field "scopeLabel" D.string) (D.field "reportingCurrency" D.string) (D.field "missingRates" (D.list D.string)))
        (D.map6 Counts (D.field "contacts" D.int) (D.field "students" D.int) (D.field "leads" D.int) (D.field "activeCases" D.int) (D.field "openTasks" D.int) (D.field "totalCases" D.int))
        (D.map6 Financial (D.field "pipelineByCurrency" (D.dict D.float)) (D.field "wonByCurrency" (D.dict D.float)) (D.field "balanceByCurrency" (D.dict D.float)) (D.field "pipelineValue" D.float) (D.field "wonValue" D.float) (D.field "outstandingBalance" D.float))
        (D.field "stageCounts" (D.dict D.int))
        (D.field "stageCurrencyValues" (D.dict (D.dict D.float)))
        (D.field "caseStages" (D.dict D.int))
        (D.field "createdCounts" (D.dict D.int))
        |> D.andThen (\snapshot -> if Date.valid snapshot.meta.today && not (String.isEmpty snapshot.meta.generatedAt) && not (String.isEmpty snapshot.meta.currency) then D.succeed snapshot else D.fail "Incomplete report metadata")


start : String -> Model -> ( Model, Cmd Msg )
start userId model =
    update Refresh (if userId == model.userId then model else { init | userId = userId, generation = model.generation })


setPeriod : String -> Snapshot -> Model -> Model
setPeriod period data model =
    if period == "custom" then { model | period = period }
    else
        { model | period = period, to = data.meta.today, from =
            if period == "all" then Dict.keys data.createdCounts |> List.filter Date.valid |> List.head |> Maybe.withDefault data.meta.today
            else Date.daysBefore (if period == "90" then 89 else 29) data.meta.today
        }


canExport : Model -> Bool
canExport model =
    model.data /= Nothing && not model.loading && model.error == "" && Date.valid model.from && Date.valid model.to && model.from <= model.to


activity : Model -> Snapshot -> List ( String, Int )
activity model data =
    if not (Date.valid model.from && Date.valid model.to) || model.from > model.to then []
    else Dict.toList data.createdCounts |> List.filter (\( date, _ ) -> Date.valid date && date >= model.from && date <= model.to)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Refresh ->
            let generation = model.generation + 1 in
            ( { model | generation = generation, loading = True, error = "" }, Request.get "/api/reports" decoder (Loaded model.userId generation) )
        Loaded userId generation result ->
            if userId /= model.userId || generation /= model.generation then ( model, Cmd.none )
            else case result of
                Err message -> ( { model | loading = False, error = message }, Cmd.none )
                Ok data ->
                    let next = { model | loading = False, error = "", data = Just data } in
                    ( if model.from == "" || model.to == "" then setPeriod model.period data next else next, Cmd.none )
        Period period -> ( model.data |> Maybe.map (\data -> setPeriod period data model) |> Maybe.withDefault model, Cmd.none )
        From date -> ( { model | from = date, period = "custom" }, Cmd.none )
        To date -> ( { model | to = date, period = "custom" }, Cmd.none )
        Download ->
            case model.data of
                Just data ->
                    if canExport model then ( model, Ports.downloadFile { filename = "ecc-management-report-" ++ String.left 10 data.meta.generatedAt ++ ".csv", content = csv model data, mime = "text/csv;charset=utf-8" } ) else ( model, Cmd.none )
                Nothing -> ( model, Cmd.none )
        Print -> ( { model | printError = False }, if canExport model then Ports.printElement "management-report" else Cmd.none )
        Printed success -> ( { model | printError = not success }, Cmd.none )


amount : Float -> String
amount value =
    Money.format value

currencies : Dict String Float -> String
currencies values =
    if Dict.isEmpty values then "—" else Dict.toList values |> List.map (\( currency, value ) -> currency ++ " " ++ amount value) |> String.join " · "


complete : Snapshot -> Dict String Float -> Bool
complete data values =
    Dict.keys values |> List.all (\currency -> not (List.member currency data.meta.missingRates))


csv : Model -> Snapshot -> String
csv model data =
    let
        f = data.financial
        countRows = [ ( "Contacts", data.counts.contacts ), ( "Students", data.counts.students ), ( "Leads", data.counts.leads ), ( "Active applications", data.counts.activeCases ), ( "Open tasks", data.counts.openTasks ) ] |> List.map (\( label, count ) -> [ "Current position", label, "", String.fromInt count ])
        financeRows ( label, values, total ) =
            (if complete data values then [ [ "Financial consolidated", label, data.meta.currency, amount total ] ] else []) ++ (Dict.toList values |> List.map (\( currency, value ) -> [ "Financial original currency", label, currency, amount value ]))
        stageRows ( stage, count ) =
            [ [ "Pipeline", stage ++ " count", "", String.fromInt count ] ] ++ (Dict.get stage data.stageCurrencies |> Maybe.withDefault Dict.empty |> Dict.toList |> List.map (\( currency, value ) -> [ "Pipeline", stage ++ " value", currency, amount value ]))
        rows =
            [ [ "ECC Workspace management report" ], [ "Snapshot UTC", data.meta.generatedAt ], [ "Scope", data.meta.scopeLabel ], [ "Reporting currency", data.meta.currency ], [ "Activity from", model.from ], [ "Activity to", model.to ], [ "Conversion gaps", if List.isEmpty data.meta.missingRates then "None" else String.join ", " data.meta.missingRates ], [], [ "Section", "Metric", "Currency", "Value" ] ]
                ++ countRows
                ++ List.concatMap financeRows [ ( "Open pipeline", f.pipeline, f.pipelineTotal ), ( "Won deal value", f.won, f.wonTotal ), ( "Outstanding invoices", f.balance, f.balanceTotal ) ]
                ++ List.concatMap stageRows (Dict.toList data.stageCounts)
                ++ (Dict.toList data.caseStages |> List.map (\( stage, count ) -> [ "Application stage", stage, "", String.fromInt count ]))
                ++ (activity model data |> List.map (\( date, count ) -> [ "Period activity", date, "", String.fromInt count ]))
                ++ [ [], [ "Methodology", "Snapshot totals are not restricted by activity dates. Activity measures new leads, students, applications, deals, schools and agents." ] ]
        escape value =
            let safe = if List.member (String.left 1 (String.trimLeft value)) [ "=", "+", "@", "-" ] then "'" ++ value else value in
            "\"" ++ String.replace "\"" "\"\"" safe ++ "\""
    in
    "\u{FEFF}" ++ String.join "\u{000D}\n" (List.map (List.map escape >> String.join ",") rows)


metric : String -> String -> String -> Html Msg
metric title value note =
    div [ A.class "metric" ] [ span [ A.class "label" ] [ text title ], strong [ A.class "value" ] [ text value ], small [] [ text note ] ]


reportTable : String -> List String -> List (List String) -> Html Msg
reportTable title headings rows =
    div [ A.class "table-scroll" ]
        [ table []
            [ caption [] [ text title ]
            , thead [] [ tr [] (List.map (\heading -> th [ A.scope "col" ] [ text heading ]) headings) ]
            , tbody [] (if List.isEmpty rows then [ tr [] [ td [ A.colspan (List.length headings) ] [ text "No records in this snapshot." ] ] ] else List.map (\row -> tr [] (List.indexedMap (\index cell -> if index == 0 then th [ A.scope "row" ] [ text cell ] else td [] [ text cell ]) row)) rows)
            ]
        ]


snapshotView : Model -> Snapshot -> List (Html Msg)
snapshotView model data =
    let
        f = data.financial
        financialMetric ( ( title, note ), values, total ) = metric title (if complete data values then data.meta.currency ++ " " ++ amount total else currencies values) note
        rows = activity model data
        invalid = not (Date.valid model.from && Date.valid model.to) || model.from > model.to
        dateField title value msg = label [] [ text title, input [ A.type_ "date", A.value value, A.max data.meta.today, A.attribute "aria-label" ("Activity " ++ String.toLower title), onInput msg ] [] ]
        stageOrder stage = List.indexedMap Tuple.pair [ "Lead", "Qualified", "Proposal", "Negotiation", "Won", "Lost" ] |> List.filter (\( _, name ) -> name == stage) |> List.head |> Maybe.map Tuple.first |> Maybe.withDefault 99
    in
    [ if List.isEmpty data.meta.missingRates then text "" else div [ A.class "warning", A.attribute "role" "note" ] [ text ("Conversion unavailable for " ++ String.join ", " data.meta.missingRates ++ ". Values are shown separately by currency where conversion is incomplete. Add the required exchange rates before relying on consolidated totals.") ]
    , section [ A.class "section", A.attribute "aria-label" "Current position" ]
        [ h3 [] [ text "Current position" ], p [ A.class "note" ] [ text "All accessible records at the snapshot time. These figures are not restricted by the activity dates below." ]
        , div [ A.class "metrics" ] [ metric "Contacts" (String.fromInt data.counts.contacts) "Client relationships", metric "Students" (String.fromInt data.counts.students) "Student profiles", metric "Active applications" (String.fromInt data.counts.activeCases) "Excludes approved, refused and closed", metric "Open tasks" (String.fromInt data.counts.openTasks) "Tasks awaiting completion" ] ]
    , section [ A.class "section", A.attribute "aria-label" "Financial position" ]
        [ h3 [] [ text "Financial position" ], p [ A.class "note" ] [ text ("Reporting currency: " ++ data.meta.currency ++ " · Converted using the latest configured exchange rates. Missing conversions remain separated.") ]
        , div [ A.class "metrics financial" ] (List.map financialMetric [ ( ( "Open pipeline", "Deals excluding Won and Lost" ), f.pipeline, f.pipelineTotal ), ( ( "Won deal value", "Won deals; not cash received" ), f.won, f.wonTotal ), ( ( "Outstanding invoices", "Positive balances; not an aging report" ), f.balance, f.balanceTotal ) ]) ]
    , div [ A.class "columns section" ]
        [ section [ A.class "panel" ] [ h3 [] [ text "Commercial pipeline" ], p [ A.class "note" ] [ text "Stage values retain their original currencies." ], reportTable "Deals by current stage" [ "Stage", "Deals", "Value" ] (Dict.toList data.stageCounts |> List.sortBy (\( stage, _ ) -> ( stageOrder stage, stage )) |> List.map (\( stage, count ) -> [ stage, String.fromInt count, currencies (Dict.get stage data.stageCurrencies |> Maybe.withDefault Dict.empty) ])) ]
        , section [ A.class "panel" ] [ h3 [] [ text "Application progress" ], p [ A.class "note" ] [ text (String.fromInt data.counts.totalCases ++ " applications across all recorded stages.") ], reportTable "Applications by current stage" [ "Stage", "Applications", "Share" ] (Dict.toList data.caseStages |> List.map (\( stage, count ) -> [ if stage == "" then "Unspecified" else stage, String.fromInt count, if data.counts.totalCases == 0 then "—" else amount (100 * toFloat count / toFloat data.counts.totalCases) ++ "%" ])) ] ]
    , section [ A.class "panel section", A.attribute "aria-label" "Recorded activity" ]
        [ h3 [] [ text "Recorded activity" ], p [ A.class "note" ] [ text "Creation dates for leads, students, applications, deals, schools and agents. This measures new records, rather than edits or completed work." ]
        , div [ A.class "filters" ] [ label [] [ text "Activity period", select [ A.attribute "aria-label" "Activity period", A.value model.period, onInput Period ] (List.map (\( value, title ) -> option [ A.value value, A.selected (value == model.period) ] [ text title ]) [ ( "30", "Last 30 days" ), ( "90", "Last 90 days" ), ( "all", "All recorded activity" ), ( "custom", "Custom dates" ) ]) ], dateField "From" model.from From, dateField "To" model.to To ]
        , p [ A.class "note" ] [ text (model.from ++ " to " ++ model.to ++ " · Inclusive workspace dates") ]
        , if invalid then p [ A.class "status error", A.attribute "role" "alert" ] [ text "Choose valid dates with an end date on or after the start date." ] else div [] [ p [ A.class "activity-total" ] [ text (String.fromInt (List.sum (List.map Tuple.second rows))) ], p [ A.class "note" ] [ text "New records during this period" ], if List.isEmpty rows then p [ A.class "activity-empty" ] [ text "No new records were recorded during this period." ] else div [ A.class "activity-table" ] [ reportTable "Daily new records" [ "Date", "New records" ] (List.map (\( date, count ) -> [ date, String.fromInt count ]) rows) ] ] ]
    , footer [ A.class "methodology" ] [ strong [] [ text "Reporting notes" ], p [] [ text "This report reflects your account’s record permissions, not necessarily the entire organization. Current financial and stage figures are point-in-time totals. Activity dates affect only new-record counts. Collections, revenue recognition, historical stage movements and trends are not inferred from these figures." ], p [] [ text ("Generated " ++ data.meta.generatedAt ++ " UTC · Reporting currency " ++ data.meta.currency ++ " · " ++ (if List.isEmpty data.meta.missingRates then "Required currencies have configured conversion rates." else "Conversion gaps: " ++ String.join ", " data.meta.missingRates)) ] ]
    ]


view : Model -> Html Msg
view model =
    article [ A.id "management-report", A.class "management-report report", A.attribute "aria-label" "Workspace management report" ]
        ([ header [ A.class "header" ]
            [ div [] [ p [ A.class "eyebrow" ] [ text "ECC · Management reporting" ], h2 [] [ text "Workspace performance" ], p [ A.class "subtitle" ] [ text "Current position, commercial results and recorded activity." ], model.data |> Maybe.map (\data -> p [ A.class "meta" ] [ text (data.meta.scopeLabel ++ " · Snapshot " ++ data.meta.generatedAt ++ " UTC") ]) |> Maybe.withDefault (text "") ]
            , div [ A.class "actions" ] [ button [ A.type_ "button", A.disabled model.loading, onClick Refresh ] [ text (if model.loading then "Refreshing…" else "Refresh") ], button [ A.type_ "button", A.class "primary", A.disabled (not (canExport model)), onClick Print ] [ text "Print / Save PDF" ], button [ A.type_ "button", A.disabled (not (canExport model)), onClick Download ] [ text "Download report CSV" ] ] ]
        , if model.error /= "" then p [ A.class "status error", A.attribute "role" "alert" ] [ text (model.error ++ (if model.data == Nothing then "" else " The previous snapshot is shown below; exports are unavailable until refresh succeeds.")) ] else if model.loading then p [ A.class "status", A.attribute "role" "status" ] [ text "Preparing your report…" ] else text ""
        , if model.printError then p [ A.class "status error", A.attribute "role" "alert" ] [ text "Allow pop-ups to open the printable report." ] else text ""
        ] ++ (model.data |> Maybe.map (snapshotView model) |> Maybe.withDefault []))
