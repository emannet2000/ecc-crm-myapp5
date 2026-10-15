module ClientPortal exposing (Error(..), Model, Msg(..), Snapshot, decoder, dirty, init, main, update, validMessage, view)

import Browser
import Char
import Dict exposing (Dict)
import File exposing (File)
import Frontend.Money as Money
import Html exposing (..)
import Html.Attributes as A
import Html.Events
import Html.Events exposing (onClick, onInput, onSubmit)
import Html.Keyed as Keyed
import Http
import Json.Decode as D
import Json.Encode as E
import Ports
import Url


type alias Snapshot =
    { email : String, student : Maybe D.Value, cases : List D.Value, documents : List D.Value, invoices : List D.Value, messages : List D.Value }


type Error = Failure Int String


type alias Model =
    { data : Maybe Snapshot, drafts : Dict String String, files : Dict String File, resets : Dict String Int, busy : Bool, generation : Int, notice : String, error : Bool, pendingLogout : Bool, signedOut : Bool }


type Msg
    = Loaded Int (Result Error Snapshot)
    | Exchanged (Result Error ())
    | Changed String String
    | SelectedFile String (Maybe File)
    | Refresh
    | Send String
    | Sent String (Result Error ())
    | Upload String
    | Uploaded String (Result Error ())
    | Logout
    | Stay
    | DiscardAndLogout
    | LoggedOut (Result Error ())


decoder : D.Decoder Snapshot
decoder =
    D.map6 Snapshot (D.field "email" D.string) (D.field "student" (D.nullable D.value)) (D.field "cases" (D.list D.value)) (D.field "documents" (D.list D.value)) (D.field "invoices" (D.list D.value)) (D.field "messages" (D.list D.value))


empty : Model
empty =
    { data = Nothing, drafts = Dict.empty, files = Dict.empty, resets = Dict.empty, busy = False, generation = 0, notice = "", error = False, pendingLogout = False, signedOut = False }


dirty : Model -> Bool
dirty model =
    Dict.values model.drafts |> List.any (not << String.isEmpty << String.trim) |> (\drafted -> drafted || not (Dict.isEmpty model.files))


validMessage : String -> Bool
validMessage body =
    let
        trimmed = String.trim body
        bytes = String.foldl (\char total -> let code = Char.toCode char in total + (if code < 128 then 1 else if code < 2048 then 2 else if code < 65536 then 3 else 4)) 0 trimmed
    in
    trimmed /= "" && bytes <= 10000


expect : D.Decoder a -> (Result Error a -> msg) -> Http.Expect msg
expect decode received =
    Http.expectStringResponse received
        (\response -> case response of
            Http.GoodStatus_ _ body -> D.decodeString decode body |> Result.mapError (\_ -> Failure 0 "The server returned an unexpected response. Your entries are kept.")
            Http.BadStatus_ metadata body -> Err (Failure metadata.statusCode (D.decodeString (D.field "error" D.string) body |> Result.withDefault "Could not complete the request. Please retry."))
            Http.Timeout_ -> Err (Failure 0 "The request timed out. Your entries are kept.")
            _ -> Err (Failure 0 "Could not connect. Your entries are kept.")
        )


confirmed : String -> D.Decoder ()
confirmed status =
    D.field "status" D.string |> D.andThen (\actual -> if actual == status then D.succeed () else D.fail "Unexpected confirmation")


post : String -> Http.Body -> String -> (Result Error () -> Msg) -> Cmd Msg
post path body status received =
    Http.request { method = "POST", headers = [], url = "/api/portal" ++ path, body = body, expect = expect (confirmed status) received, timeout = Just 60000, tracker = Nothing }


load : Model -> ( Model, Cmd Msg )
load model =
    let generation = model.generation + 1 in
    ( { model | generation = generation, busy = True, error = False }, Http.get { url = "/api/portal/me", expect = expect decoder (Loaded generation) } )


protected : ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
protected ( model, cmd ) =
    ( model, Cmd.batch [ cmd, Ports.protectUnsaved (dirty model || model.busy) ] )


init : { token : String } -> ( Model, Cmd Msg )
init flags =
    protected (if flags.token == "" then load empty else ( { empty | busy = True }, post "/session" (Http.jsonBody (E.object [ ( "token", E.string flags.token ) ])) "ok" Exchanged ))


failed : Error -> Model -> Model
failed (Failure status message) model =
    { model | busy = False, notice = message, error = True, data = if status == 401 then Nothing else model.data }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    protected (step msg model)


step : Msg -> Model -> ( Model, Cmd Msg )
step msg model =
    case msg of
        Exchanged result -> case result of
            Ok _ -> load empty
            Err error -> ( failed error model, Cmd.none )
        Loaded generation result ->
            if generation /= model.generation || model.signedOut then ( model, Cmd.none ) else case result of
                Ok data -> ( { model | data = Just data, busy = False, error = False }, Cmd.none )
                Err error -> ( failed error model, Cmd.none )
        Changed id body -> if model.busy || model.pendingLogout then ( model, Cmd.none ) else ( { model | drafts = Dict.insert id body model.drafts }, Cmd.none )
        SelectedFile id file -> if model.busy || model.pendingLogout then ( model, Cmd.none ) else ( { model | files = case file of
                Just selected -> Dict.insert id selected model.files
                Nothing -> Dict.remove id model.files }, Cmd.none )
        Refresh -> if model.busy || model.signedOut || model.pendingLogout then ( model, Cmd.none ) else load model
        Send id ->
            let body = Dict.get id model.drafts |> Maybe.withDefault ""
                allowed = model.data |> Maybe.map (\data -> List.any (\record -> str "id" record == id) data.cases) |> Maybe.withDefault False
            in
            if model.busy || model.pendingLogout || not allowed then ( model, Cmd.none )
            else if not (validMessage body) then ( { model | error = True, notice = "Enter a response, or shorten it before sending." }, Cmd.none )
            else ( { model | busy = True, error = False, notice = "Sending your response…" }, post "/messages" (Http.jsonBody (E.object [ ( "caseId", E.string id ), ( "body", E.string body ) ])) "received" (Sent id) )
        Sent id result -> case result of
            Ok _ -> load { model | drafts = Dict.remove id model.drafts, notice = "Your response was sent." }
            Err error -> ( failed error model, Cmd.none )
        Upload id ->
            let allowed = model.data |> Maybe.map (\data -> List.any (\record -> str "id" record == id) data.documents) |> Maybe.withDefault False in
            if model.busy || model.pendingLogout || not allowed then ( model, Cmd.none ) else case Dict.get id model.files of
                Nothing -> ( { model | error = True, notice = "Choose a file before uploading." }, Cmd.none )
                Just file -> ( { model | busy = True, error = False, notice = "Uploading your document…" }, post ("/documents/" ++ Url.percentEncode id ++ "/files") (Http.multipartBody [ Http.filePart "file" file ]) "uploaded" (Uploaded id) )
        Uploaded id result -> case result of
            Ok _ -> load { model | files = Dict.remove id model.files, resets = Dict.update id (\count -> Just (Maybe.withDefault 0 count + 1)) model.resets, notice = "Document uploaded. Your adviser will review it." }
            Err error -> ( failed error model, Cmd.none )
        Logout -> if model.busy || model.signedOut then ( model, Cmd.none ) else if dirty model then ( { model | pendingLogout = True }, Cmd.none ) else step DiscardAndLogout model
        Stay -> ( { model | pendingLogout = False }, Cmd.none )
        DiscardAndLogout ->
            if model.busy then ( model, Cmd.none ) else ( { model | busy = True, pendingLogout = False }, post "/logout" (Http.jsonBody (E.object [])) "ok" LoggedOut )
        LoggedOut result -> case result of
            Ok _ -> ( { empty | signedOut = True, generation = model.generation + 1, notice = "You are signed out." }, Cmd.none )
            Err error -> ( failed error model, Cmd.none )


str : String -> D.Value -> String
str key value =
    D.decodeValue (D.field key D.string) value |> Result.withDefault ""


number : String -> D.Value -> Float
number key value =
    D.decodeValue (D.field key D.float) value |> Result.withDefault 0


yes : String -> D.Value -> Bool
yes key value =
    D.decodeValue (D.field key D.bool) value |> Result.withDefault False


rows : String -> D.Value -> List D.Value
rows key value =
    D.decodeValue (D.field key (D.list D.value)) value |> Result.withDefault []


card : String -> List (Html Msg) -> Html Msg
card title children =
    section [ A.class "card" ] (h2 [] [ text title ] :: children)


btn : Model -> String -> Msg -> Html Msg
btn model title msg =
    button [ A.type_ "button", A.class "secondary", A.disabled (model.busy || model.pendingLogout), onClick msg ] [ text title ]


snapshotView : Model -> Snapshot -> Html Msg
snapshotView model data =
    let
        instructions = data.cases |> List.filterMap (\record -> D.decodeValue (D.field "clientTask" D.value) record |> Result.toMaybe |> Maybe.andThen (\task -> if str "instructions" task /= "" && not (yes "done" task) then Just (record, task) else Nothing))
        uploads = List.filter (\record -> yes "required" record && (number "latestVersion" record == 0 || String.toLower (str "status" record) == "rejected")) data.documents
        payments = List.filter (\invoice -> number "balance" invoice > 0) data.invoices
        required = List.filter (yes "required") data.documents
        verified = List.filter (\document -> String.toLower (str "status" document) == "verified") required |> List.length
        taskRows = List.concatMap (\( record, task ) -> [ h3 [] [ text (str "caseNumber" record) ], p [] [ text (str "instructions" task) ], p [] [ text (if str "dueDate" task == "" then "No deadline set" else "Due " ++ str "dueDate" task) ] ]) instructions
            ++ List.concatMap (\document -> [ p [] [ text ("Upload " ++ str "name" document ++ (if str "dueDate" document == "" then "" else " by " ++ str "dueDate" document)) ], p [] [ text (if str "rejectionReason" document == "" then "Upload a clear, complete copy. Your adviser will review it." else "Please correct: " ++ str "rejectionReason" document) ] ]) uploads
            ++ List.concatMap (\invoice -> [ p [] [ text ("Review invoice " ++ str "number" invoice ++ " · " ++ str "currency" invoice ++ " " ++ Money.format (number "balance" invoice) ++ (if str "dueDate" invoice == "" then "" else " · due " ++ str "dueDate" invoice)) ], a [ A.href ("/api/portal/invoices/" ++ Url.percentEncode (str "id" invoice) ++ "/pdf") ] [ text "View payment instructions on invoice" ] ]) payments
        application record =
            let id = str "id" record in
            section [] [ h3 [] [ text (str "caseNumber" record) ], p [] [ text (str "stage" record) ], p [] [ text ("Adviser: " ++ (if str "adviser" record == "" then "Your adviser" else str "adviser" record)) ], p [] [ text (if str "deadline" record == "" then "" else "Due " ++ str "deadline" record) ]
                , form [ onSubmit (Send id) ] [ label [] [ text "Respond to your adviser", textarea [ A.attribute "aria-label" ("Response for " ++ str "caseNumber" record), A.required True, A.maxlength 10000, A.disabled (model.busy || model.pendingLogout), A.value (Dict.get id model.drafts |> Maybe.withDefault ""), onInput (Changed id) ] [] ], button [ A.type_ "submit", A.disabled (model.busy || model.pendingLogout) ] [ text "Send response" ] ] ]
        documentView record =
            let id = str "id" record
                latest = round (number "latestVersion" record)
            in
            section [] [ h3 [] [ text (str "name" record ++ (if yes "required" record then " · Required" else "")) ], p [] [ text (str "caseNumber" record ++ " · " ++ str "status" record) ], if str "rejectionReason" record == "" then text "" else p [] [ text ("Please correct: " ++ str "rejectionReason" record) ]
                , if latest == 0 then text "" else a [ A.href ("/api/portal/documents/" ++ Url.percentEncode id ++ "/files/" ++ String.fromInt latest), A.download "" ] [ text "Download latest version" ]
                , form [ onSubmit (Upload id) ] [ label [] [ text ("Upload " ++ str "name" record), input [ A.type_ "file", A.required True, A.accept ".pdf,.png,.jpg,.jpeg,.docx,.xlsx,.txt,.csv", A.disabled (model.busy || model.pendingLogout), Html.Events.on "change" (D.at [ "target", "files" ] (D.list File.decoder) |> D.map (List.head >> SelectedFile id)) ] [] ], button [ A.type_ "submit", A.disabled (model.busy || model.pendingLogout) ] [ text "Upload version" ] ] ]
    in
    div [ A.id "portal" ]
        [ card (data.student |> Maybe.map (str "name") |> Maybe.withDefault data.email)
            (data.student |> Maybe.map (\student -> p [] [ text (List.filter ((/=) "") (List.map (\key -> str key student) [ "program", "applicationStage", "visaStatus" ]) |> String.join " · ") ] :: List.map (\item -> p [] [ text ((if yes "done" item then "✓ " else "○ ") ++ str "title" item) ]) (rows "preDeparture" student)) |> Maybe.withDefault [])
        , card "What to do next" (if List.isEmpty taskRows then [ p [] [ text "No client actions requested. Your adviser will update this list when something is needed." ] ] else taskRows)
        , card "Document review" [ p [] [ text (String.fromInt verified ++ " of " ++ String.fromInt (List.length required) ++ " required documents verified. Application decisions are shown separately below.") ] ]
        , card "Application progress" [ if List.isEmpty data.cases then p [] [ text "Your adviser will link your application here." ] else Keyed.node "div" [] (List.map (\record -> ( str "id" record, application record )) data.cases) ]
        , card "Requested documents" [ if List.isEmpty data.documents then p [] [ text "No documents requested." ] else Keyed.node "div" [] (List.map (\record -> let id = str "id" record in ( id ++ "-" ++ String.fromInt (Dict.get id model.resets |> Maybe.withDefault 0), documentView record )) data.documents) ]
        , card "Invoices" (if List.isEmpty data.invoices then [ p [] [ text "No invoices issued." ] ] else List.map (\invoice -> section [] [ h3 [] [ text (str "number" invoice) ], p [] [ text (str "currency" invoice ++ " " ++ Money.format (number "balance" invoice) ++ " due" ++ (if str "dueDate" invoice == "" then "" else " · " ++ str "dueDate" invoice)) ], a [ A.href ("/api/portal/invoices/" ++ Url.percentEncode (str "id" invoice) ++ "/pdf"), A.download "invoice.pdf" ] [ text "Download invoice" ] ]) data.invoices)
        , card "Messages with your adviser" (if List.isEmpty data.messages then [ p [] [ text "No messages yet." ] ] else List.map (\message -> article [] [ strong [] [ text (if str "direction" message == "outbound" then "Adviser" else "You") ], p [ A.class "message-body" ] [ text (str "body" message) ], small [] [ text (str "createdAt" message) ] ]) data.messages)
        ]


view : Model -> Html Msg
view model =
    main_ [ A.class "portal-body" ]
        [ header [] [ div [ A.class "tools-brand" ] [ img [ A.class "aux-brand-logo", A.src "/public/icons/ecc-192.png", A.alt "ECC Consulting Global emblem" ] [], div [] [ p [ A.class "eyebrow" ] [ text "ECC CLIENT PORTAL" ], h1 [] [ text "Your application workspace" ] ] ], div [ A.class "actions" ] [ btn model "Refresh" Refresh, btn model "Sign out" Logout ] ]
        , div [ A.id "notice", A.attribute "role" "status", A.attribute "aria-live" "polite", A.class (if model.error then "error" else "") ] [ text model.notice ]
        , if model.pendingLogout then section [ A.attribute "role" "alertdialog", A.attribute "aria-label" "Unsaved portal entries" ] [ h2 [] [ text "Your responses and selected files are not saved" ], p [] [ text "Stay to send your responses or upload your files. Signing out discards these entries." ], button [ A.type_ "button", onClick Stay ] [ text "Stay" ], button [ A.type_ "button", onClick DiscardAndLogout ] [ text "Discard and sign out" ] ] else text ""
        , if model.signedOut then p [] [ text "You are signed out." ] else model.data |> Maybe.map (snapshotView model) |> Maybe.withDefault (p [] [ text (if model.busy then "Loading your workspace…" else "Ask your adviser for a new private invitation if your access expired.") ])
        ]


main : Program { token : String } Model Msg
main =
    Browser.element { init = init, update = update, view = view, subscriptions = \_ -> Sub.none }
