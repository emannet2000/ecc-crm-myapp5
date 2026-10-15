port module RecordBrowser exposing (Model, Msg(..), Query, decoder, init, main, recordLink, update, view)

import Browser
import Char
import Dict exposing (Dict)
import Frontend.Http as Request
import Html exposing (..)
import Html.Attributes as A
import Html.Events
import Html.Events exposing (onClick, onInput, onSubmit)
import Json.Decode as D
import Json.Encode as E
import Set exposing (Set)
import Url


port queryChanged : Query -> Cmd msg


type alias Query =
    { entity : String, search : String, status : String, sort : String, direction : String, columns : List String, page : Int }


type alias Flags =
    { userId : String, modules : List String, payments : Bool, query : Query }


type alias Page =
    { rows : List (Dict String D.Value), total : Int }


type alias Model =
    { userId : String, modules : List String, payments : Bool, query : Query, searchInput : String, statusInput : String, data : Maybe Page, loading : Bool, generation : Int, error : String, notice : String, checkout : Set String }


type Msg
    = Module String
    | Search String
    | Status String
    | Apply
    | Sort String
    | Direction String
    | Column String Bool
    | Next
    | Previous
    | Refresh
    | Loaded Int Query (Result String Page)
    | Checkout String
    | CheckedOut String (Result String String)


init : Flags -> ( Model, Cmd Msg )
init flags =
    let
        query = flags.query
        sanitized = { query | entity = if List.member query.entity flags.modules then query.entity else List.head flags.modules |> Maybe.withDefault "contacts", page = max 0 query.page, direction = if query.direction == "desc" then "desc" else "asc" }
    in
    fetch { userId = flags.userId, modules = flags.modules, payments = flags.payments, query = sanitized, searchInput = sanitized.search, statusInput = sanitized.status, data = Nothing, loading = False, generation = 0, error = "", notice = "", checkout = Set.empty }


decoder : String -> D.Decoder Page
decoder entity =
    D.map2 Page (D.field entity (D.list (D.dict D.value))) (D.field "total" D.int)
        |> D.andThen (\page -> if page.total < 0 then D.fail "Invalid record count" else D.succeed page)


fetch : Model -> ( Model, Cmd Msg )
fetch model =
    let
        q = model.query
        generation = model.generation + 1
        url = "/api/" ++ Url.percentEncode q.entity ++ "?limit=25&offset=" ++ String.fromInt (q.page * 25) ++ "&q=" ++ Url.percentEncode q.search ++ "&sort=" ++ Url.percentEncode q.sort ++ "&direction=" ++ q.direction ++ "&filterStatus=" ++ Url.percentEncode q.status
    in
    ( { model | loading = True, generation = generation, error = "", data = Nothing }, Cmd.batch [ queryChanged q, Request.get url (decoder q.entity) (Loaded generation q) ] )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let q = model.query in
    case msg of
        Module entity ->
            if List.member entity model.modules then fetch { model | query = { q | entity = entity, page = 0, columns = [], sort = "", status = "" }, statusInput = "" } else ( model, Cmd.none )
        Search value -> ( { model | searchInput = value }, Cmd.none )
        Status value -> ( { model | statusInput = value }, Cmd.none )
        Apply -> fetch { model | query = { q | search = model.searchInput, status = model.statusInput, page = 0 } }
        Sort field -> fetch { model | query = { q | sort = field, direction = if q.sort == field && q.direction == "asc" then "desc" else "asc", page = 0 } }
        Direction direction -> fetch { model | query = { q | direction = if direction == "desc" then "desc" else "asc", page = 0 } }
        Column field enabled ->
            let selected = if List.isEmpty q.columns then defaultColumns q.entity (model.data |> Maybe.map .rows |> Maybe.withDefault []) else q.columns
                columns = if enabled then if List.member field selected then selected else selected ++ [ field ] else List.filter ((/=) field) selected
            in
            if List.isEmpty columns then ( model, Cmd.none ) else ( { model | query = { q | columns = columns } }, queryChanged { q | columns = columns } )
        Next ->
            if not model.loading && (model.data |> Maybe.map (\page -> (q.page + 1) * 25 < page.total) |> Maybe.withDefault False) then fetch { model | query = { q | page = q.page + 1 } } else ( model, Cmd.none )
        Previous -> if not model.loading && q.page > 0 then fetch { model | query = { q | page = q.page - 1 } } else ( model, Cmd.none )
        Refresh -> fetch model
        Loaded generation query result ->
            if generation /= model.generation || { query | columns = model.query.columns } /= model.query then ( model, Cmd.none )
            else case result of
                Err message -> ( { model | loading = False, error = message }, Cmd.none )
                Ok page ->
                    if q.page > 0 && List.isEmpty page.rows && q.page * 25 >= page.total then fetch { model | query = { q | page = max 0 ((page.total - 1) // 25) } }
                    else ( { model | loading = False, data = Just page }, Cmd.none )
        Checkout id ->
            if not model.payments || q.entity /= "invoices" || Set.member id model.checkout then ( model, Cmd.none )
            else ( { model | checkout = Set.insert id model.checkout, notice = "" }, Request.post ("/api/invoices/" ++ Url.percentEncode id ++ "/checkout") (E.object []) (D.field "url" D.string) (CheckedOut id) )
        CheckedOut id result ->
            ( { model | checkout = Set.remove id model.checkout, notice = case result of
                Ok url -> "Payment link: " ++ url
                Err message -> message }, Cmd.none )


string : String -> Dict String D.Value -> String
string key row =
    Dict.get key row |> Maybe.andThen (D.decodeValue D.string >> Result.toMaybe) |> Maybe.withDefault ""


recordLink : String -> Dict String D.Value -> String
recordLink entity row =
    let path module_ key = "/" ++ module_ ++ "/" ++ Url.percentEncode (string key row) in
    case entity of
        "tasks" -> "/tasks"
        "documents" -> if string "caseId" row /= "" then path "cases" "caseId" ++ "#record-tools?tab=documents" else if string "leadId" row /= "" then path "leads" "leadId" ++ "#record-tools?tab=documents" else "/workspace?tab=documents"
        "payments" -> if string "invoiceId" row == "" then "/invoices" else path "invoices" "invoiceId"
        "activities" -> if string "dealId" row /= "" then path "deals" "dealId" else if string "contactId" row /= "" then path "contacts" "contactId" else "/contacts"
        _ -> path entity "id"


human : String -> String
human key =
    if key == "id" then "Record ID" else if key == "cases" then "Applications" else
    String.toList key |> List.indexedMap (\index char -> if Char.isUpper char && index > 0 then " " ++ String.fromChar char else String.fromChar char) |> String.concat |> String.replace "_" " " |> (\label -> String.toUpper (String.left 1 label) ++ String.dropLeft 1 label)


scalar : D.Value -> Maybe String
scalar value =
    D.decodeValue (D.oneOf [ D.string, D.float |> D.map String.fromFloat, D.bool |> D.map (\yes -> if yes then "Yes" else "No"), D.null "—" ]) value |> Result.toMaybe


availableColumns : List (Dict String D.Value) -> List String
availableColumns rows =
    rows |> List.concatMap Dict.toList |> List.filter (\( key, value ) -> not (List.member key [ "orgId", "ownerId", "teamId", "visibility", "openingReceived", "ledgerInitialized" ]) && scalar value /= Nothing) |> List.map Tuple.first |> Set.fromList |> Set.toList


defaultColumns : String -> List (Dict String D.Value) -> List String
defaultColumns entity rows =
    case entity of
        "deals" -> [ "title", "currency", "value", "stage", "closeDate", "owner", "id" ]
        "invoices" -> [ "invoiceNumber", "clientName", "currency", "balance", "paymentMilestone", "id" ]
        _ ->
            let preferred = [ "name", "title", "email", "phone", "company", "stage", "status", "createdAt", "id" ]
                available = availableColumns rows
            in
            if List.isEmpty available then [ "id" ] else List.take 7 (List.filter (\key -> List.member key available) preferred ++ List.filter (\key -> not (List.member key preferred)) available)


view : Model -> Html Msg
view model =
    let
        q = model.query
        rows = model.data |> Maybe.map .rows |> Maybe.withDefault []
        columns = if List.isEmpty q.columns then defaultColumns q.entity rows else q.columns
        options = availableColumns rows
        total = model.data |> Maybe.map .total |> Maybe.withDefault 0
        button_ title msg disabled = button [ A.type_ "button", A.class "secondary", A.disabled disabled, onClick msg ] [ text title ]
    in
    section [ A.class "record-browser-elm" ]
        [ h2 [] [ text "Browse records" ]
        , form [ A.class "toolbar", onSubmit Apply ]
            [ label [] [ text "Module", select [ A.attribute "aria-label" "Module", A.value q.entity, onInput Module ] (List.map (\entity -> option [ A.value entity, A.selected (entity == q.entity) ] [ text (human entity) ]) model.modules) ]
            , label [] [ text "Search records", input [ A.type_ "search", A.attribute "aria-label" "Search records", A.value model.searchInput, onInput Search ] [] ]
            , label [] [ text "Status filter", input [ A.attribute "aria-label" "Status filter", A.value model.statusInput, onInput Status ] [] ]
            , button [ A.type_ "submit", A.class "secondary" ] [ text "Apply filters" ]
            , label [] [ text "Sort by", select [ A.attribute "aria-label" "Sort field", A.value q.sort, onInput Sort ] (option [ A.value "" ] [ text "Default order" ] :: List.map (\key -> option [ A.value key, A.selected (key == q.sort) ] [ text (human key) ]) options) ]
            , label [] [ text "Sort direction", select [ A.attribute "aria-label" "Sort direction", A.value q.direction, onInput Direction ] [ option [ A.value "asc", A.selected (q.direction == "asc") ] [ text "Ascending" ], option [ A.value "desc", A.selected (q.direction == "desc") ] [ text "Descending" ] ] ]
            , button_ "Refresh records" Refresh model.loading
            ]
        , if List.isEmpty options then text "" else details [] [ summary [] [ text "Displayed columns" ], div [ A.class "column-options" ] (List.map (\key -> label [] [ input [ A.type_ "checkbox", A.checked (List.member key columns), Html.Events.onCheck (Column key) ] [], text (human key) ]) options) ]
        , if model.error /= "" then div [ A.attribute "role" "alert" ] [ p [] [ text model.error ], button_ "Retry" Refresh False ] else if model.loading then p [ A.attribute "role" "status" ] [ text "Loading records…" ] else text ""
        , if model.notice == "" then text "" else p [ A.attribute "role" "status" ] [ text model.notice ]
        , if model.loading || model.error /= "" then text "" else if List.isEmpty rows then p [] [ text "No matching records." ] else div [ A.class "table-wrap" ]
            [ table []
                [ thead [] [ tr [] (List.map (\key -> th [ A.scope "col" ] [ button_ (human key ++ (if q.sort == key then if q.direction == "asc" then " ↑" else " ↓" else "")) (Sort key) False ]) columns ++ [ th [ A.scope "col" ] [ text "Actions" ] ]) ]
                , tbody [] (List.map (\row -> let id = string "id" row in tr [] (List.map (\key -> td [] [ text (Dict.get key row |> Maybe.andThen scalar |> Maybe.withDefault "—") ]) columns ++ [ td [] ([ a [ A.href (recordLink q.entity row), A.target "_top" ] [ text "Open record" ] ] ++ (if q.entity == "invoices" then [ a [ A.href ("/api/invoices/" ++ Url.percentEncode id ++ "/pdf"), A.download "invoice.pdf" ] [ text "PDF" ] ] ++ (if model.payments then [ button_ "Create payment link" (Checkout id) (Set.member id model.checkout) ] else []) else [])) ])) rows)
                ] ]
        , div [ A.class "toolbar" ] [ button_ "Previous" Previous (model.loading || q.page == 0), span [] [ text (String.fromInt total ++ " records · page " ++ String.fromInt (q.page + 1)) ], button_ "Next" Next (model.loading || (q.page + 1) * 25 >= total) ]
        ]


main : Program Flags Model Msg
main =
    Browser.element { init = init, update = update, view = view, subscriptions = \_ -> Sub.none }
