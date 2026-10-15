module Administration exposing (Action(..), Model, Msg(..), decoder, dirty, init, securityEventLabel, securityTime, update, view)

import Browser.Navigation as Nav
import Dict exposing (Dict)
import Html exposing (Html, a, button, datalist, div, form, h2, h3, header, input, label, nav, option, p, section, select, strong, table, tbody, td, text, th, thead, tr)
import Html.Attributes as A
import Html.Events exposing (onClick, onInput, onSubmit)
import Http
import Json.Decode as D
import Json.Encode as E
import Process
import Task


type alias Snapshot =
    { currentUserId : String
    , users : List D.Value
    , teams : List D.Value
    , levels : List D.Value
    , organization : List D.Value
    , sessions : List D.Value
    , changes : List D.Value
    , security : List D.Value
    }


type Kind
    = NewUser
    | EditUser String
    | NewTeam
    | Workspace


type alias Draft =
    { kind : Kind, values : Dict String String, original : Dict String String }


type alias Mutation =
    { path : String, method : String, payload : E.Value, userId : Maybe String, message : String }


type Action
    = Switch String
    | Refresh
    | Create
    | Manage String
    | Close
    | Account Mutation
    | Exit String
    | SignOut


type Msg
    = Start
    | Navigate String
    | Request Action
    | Changed String String
    | Search String
    | FilterRole String
    | FilterStatus String
    | Save
    | SaveAndContinue
    | Discard
    | Stay
    | Confirm
    | Cancel
    | Loaded Int (Result String Snapshot)
    | Saved Int (Result String D.Value)
    | Refreshed Int Bool String E.Value (Maybe String) (Result String ())


type alias Model =
    { data : Maybe Snapshot
    , tab : String
    , draft : Maybe Draft
    , pending : Maybe Action
    , afterSave : Maybe Action
    , confirmation : Maybe Mutation
    , loading : Bool
    , busy : Bool
    , generation : Int
    , notice : String
    , error : Bool
    , invitation : String
    , search : String
    , role : String
    , status : String
    , retried : Bool
    , signOut : Bool
    }


init : Model
init =
    { data = Nothing, tab = "users", draft = Nothing, pending = Nothing, afterSave = Nothing, confirmation = Nothing, loading = False, busy = False, generation = 0, notice = "", error = False, invitation = "", search = "", role = "", status = "", retried = False, signOut = False }


str : String -> D.Value -> String
str key json =
    D.decodeValue (D.field key (D.oneOf [ D.string, D.int |> D.map String.fromInt ])) json |> Result.withDefault ""


bool : String -> D.Value -> Bool
bool key json =
    D.decodeValue (D.field key D.bool) json |> Result.withDefault False


rows : String -> D.Decoder (List D.Value)
rows key =
    D.field key (D.list D.value)


decoder : D.Decoder Snapshot
decoder =
    D.map8 (\id users teams levels organization sessions changes security -> Snapshot id users teams levels organization sessions changes security)
        (D.field "currentUserId" D.string)
        (rows "users")
        (rows "teams")
        (rows "accessLevels")
        (rows "organization")
        (rows "sessions")
        (rows "changes")
        (rows "security")


expect : D.Decoder a -> (Result String a -> msg) -> Http.Expect msg
expect dec toMsg =
    Http.expectStringResponse toMsg
        (\response ->
            case response of
                Http.GoodStatus_ _ body ->
                    D.decodeString dec body |> Result.mapError (\_ -> "Could not read the response. Please retry.")

                Http.BadStatus_ metadata body ->
                    if metadata.statusCode == 401 then
                        Err "session-expired"

                    else
                        Err (D.decodeString (D.field "error" D.string) body |> Result.withDefault "Could not complete this request. Please retry.")

                Http.Timeout_ ->
                    Err "The request timed out. Please retry."

                Http.NetworkError_ ->
                    Err "Could not connect. Please retry."

                Http.BadUrl_ _ ->
                    Err "Could not open the request."
        )


send : Int -> Bool -> String -> E.Value -> Maybe String -> Model -> Cmd Msg
send generation writing path payload target model =
    let
        version =
            model.data
                |> Maybe.map (.users >> List.filter (\u -> Just (str "id" u) == target) >> List.head >> Maybe.map (str "accessVersion") >> Maybe.withDefault "")
                |> Maybe.withDefault ""

        headers =
            if version == "" then
                []

            else
                [ Http.header "If-Match" version ]
    in
    Http.request
        { method = if writing then str "method" payload else "GET"
        , headers = headers
        , url = path
        , body = if writing then Http.jsonBody (D.decodeValue (D.field "body" D.value) payload |> Result.withDefault E.null) else Http.emptyBody
        , expect = if writing then expect D.value (Saved generation) else expect decoder (Loaded generation)
        , timeout = Just 20000
        , tracker = Nothing
        }


refreshSession : Int -> Bool -> String -> E.Value -> Maybe String -> Cmd Msg
refreshSession generation writing path payload target =
    Http.post
        { url = "/api/session/refresh", body = Http.emptyBody, expect = expect (D.succeed ()) (Refreshed generation writing path payload target) }


load : Model -> ( Model, Cmd Msg )
load model =
    let
        next = { model | loading = True, retried = False, generation = model.generation + 1 }
    in
    ( next, send next.generation False "/api/admin/system" E.null Nothing next )


dirty : Model -> Bool
dirty model =
    model.draft |> Maybe.map (\draft -> draft.values /= draft.original) |> Maybe.withDefault False


newDraft : Kind -> List ( String, String ) -> Draft
newDraft kind values =
    let
        fields = Dict.fromList values
    in
    Draft kind fields fields


find : String -> List D.Value -> Maybe D.Value
find id =
    List.filter (\entry -> str "id" entry == id) >> List.head


perform : Action -> Model -> ( Model, Cmd Msg )
perform action model =
    let
        clean = { model | pending = Nothing, afterSave = Nothing, confirmation = Nothing, draft = Nothing }
    in
    case action of
        Refresh ->
            load clean

        SignOut ->
            ( { clean | signOut = True }, Cmd.none )

        Exit path ->
            ( clean, Process.sleep 0 |> Task.perform (\_ -> Navigate path) )

        Account mutation ->
            ( { clean | confirmation = Just mutation }, Cmd.none )

        _ ->
            case model.data of
                Nothing ->
                    ( clean, Cmd.none )

                Just data ->
                    case action of
                        Switch tab ->
                            let
                                draft =
                                    if tab == "settings" then
                                        List.head data.organization |> Maybe.map (\org -> newDraft Workspace (List.map (\key -> ( key, str key org )) [ "name", "timezone", "currency", "ipAllowlist" ]))

                                    else if tab == "teams" then
                                        Just (newDraft NewTeam [ ( "name", "" ) ])

                                    else
                                        Nothing
                            in
                            ( { clean | tab = tab, draft = draft }, Cmd.none )

                        Create ->
                            ( { clean | tab = "users", draft = Just (newDraft NewUser [ ( "name", "" ), ( "email", "" ), ( "password", "" ), ( "role", "member" ), ( "teamId", "" ) ]) }, Cmd.none )

                        Manage id ->
                            ( { clean | tab = "users", draft = find id data.users |> Maybe.map (\u -> newDraft (EditUser id) (List.map (\key -> ( key, str key u )) [ "name", "role", "teamId" ])) }, Cmd.none )

                        _ ->
                            ( clean, Cmd.none )


value : String -> Draft -> String
value key draft =
    Dict.get key draft.values |> Maybe.withDefault ""


saveDraft : Model -> ( Model, Cmd Msg )
saveDraft model =
    case model.draft of
        Nothing ->
            ( model, Cmd.none )

        Just draft ->
            let
                fields = draft.values |> Dict.toList |> List.map (Tuple.mapSecond E.string) |> E.object
                mutation path method target message = Mutation path method fields target message
                account = case draft.kind of
                    EditUser id -> model.data |> Maybe.andThen (.users >> find id)
                    _ -> Nothing
                requiresConfirmation =
                    case ( draft.kind, account, model.data ) of
                        ( EditUser id, Just user, Just data ) -> value "role" draft /= str "role" user || id == data.currentUserId
                        _ -> False
                request =
                    case draft.kind of
                        NewUser -> mutation "/api/admin/users" "POST" Nothing ""
                        EditUser id -> mutation ("/api/admin/users/" ++ id) "PATCH" (Just id) "Save these access changes and sign out this user's existing sessions?"
                        NewTeam -> mutation "/api/admin/teams" "POST" Nothing ""
                        Workspace -> mutation "/api/admin/organization" "PUT" Nothing ""
                validation =
                    if String.trim (value "name" draft) == "" then "Enter a name before saving."
                    else if draft.kind == NewUser && (not (String.contains "@" (value "email" draft)) || (value "password" draft /= "" && String.length (value "password" draft) < 12)) then "Enter a valid email and use at least 12 characters for an initial password, or leave it empty."
                    else if draft.kind == Workspace && String.trim (value "timezone" draft) == "" then "Choose a timezone before saving."
                    else ""
            in
            if validation /= "" then
                ( { model | notice = validation, error = True, pending = Nothing, afterSave = Nothing }, Cmd.none )
            else if requiresConfirmation then
                ( { model | pending = Nothing, confirmation = Just request }, Cmd.none )
            else
                write request { model | pending = Nothing }


write : Mutation -> Model -> ( Model, Cmd Msg )
write mutation model =
    let
        payload = E.object [ ( "method", E.string mutation.method ), ( "body", mutation.payload ) ]
        next = { model | busy = True, retried = False, generation = model.generation + 1, notice = "Saving…", error = False, confirmation = Just mutation }
    in
    ( next, send next.generation True mutation.path payload mutation.userId next )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Loaded generation result ->
            if generation /= model.generation then ( model, Cmd.none )
            else case result of
                Err "session-expired" ->
                    if model.retried then ( { model | loading = False, notice = "Your session expired. Sign in again.", error = True }, Cmd.none )
                    else ( { model | retried = True }, refreshSession generation False "/api/admin/system" E.null Nothing )
                Err message -> ( { model | loading = False, notice = message, error = True, afterSave = Nothing }, Cmd.none )
                Ok data ->
                    let
                        loaded = { model | data = Just data, loading = False }
                    in
                    case model.afterSave of
                        Just action -> perform action loaded
                        Nothing -> perform (Switch model.tab) loaded

        Saved generation result ->
            if generation /= model.generation then ( model, Cmd.none )
            else case result of
                Err "session-expired" ->
                    if model.retried then
                        ( { model | busy = False, confirmation = Nothing, afterSave = Nothing, notice = "Your session expired. Sign in again. Your entries are kept on this screen.", error = True }, Cmd.none )
                    else case model.confirmation of
                        Just mutation -> ( { model | retried = True }, refreshSession generation True mutation.path (E.object [ ( "method", E.string mutation.method ), ( "body", mutation.payload ) ]) mutation.userId )
                        Nothing -> ( model, Cmd.none )
                Err message -> ( { model | busy = False, confirmation = Nothing, afterSave = Nothing, notice = message ++ " Your entries are kept.", error = True }, Cmd.none )
                Ok resultValue ->
                    let
                        selfChange = case ( model.data, model.confirmation ) of
                            ( Just data, Just mutation ) -> mutation.userId == Just data.currentUserId && (mutation.method == "PATCH" || String.endsWith "/revoke-sessions" mutation.path)
                            _ -> False
                        saved = { model | busy = False, draft = Nothing, confirmation = Nothing, notice = if str "message" resultValue == "" then "Changes saved." else str "message" resultValue, invitation = str "inviteLink" resultValue, error = False }
                    in
                    if selfChange then perform (Exit "/") saved else load saved

        Refreshed generation writing path payload target result ->
            if generation /= model.generation then ( model, Cmd.none )
            else case result of
                Ok _ -> ( model, send generation writing path payload target model )
                Err "session-expired" -> ( { model | busy = False, loading = False, confirmation = Nothing, afterSave = Nothing, notice = "Your session expired. Sign in again. Your entries are kept on this screen.", error = True }, Cmd.none )
                Err message -> ( { model | busy = False, loading = False, confirmation = Nothing, afterSave = Nothing, notice = message ++ " Your entries are kept on this screen.", error = True }, Cmd.none )

        Navigate path ->
            ( model, Nav.load path )

        _ ->
            if model.busy || model.loading then ( model, Cmd.none )
            else case msg of
                Start -> load { init | generation = model.generation }
                Request action ->
                    if dirty model then ( { model | pending = Just action, confirmation = Nothing, afterSave = Nothing }, Cmd.none ) else perform action model
                Changed key nextValue -> ( { model | draft = Maybe.map (\draft -> { draft | values = Dict.insert key nextValue draft.values }) model.draft }, Cmd.none )
                Search query -> ( { model | search = query }, Cmd.none )
                FilterRole role -> ( { model | role = role }, Cmd.none )
                FilterStatus status -> ( { model | status = status }, Cmd.none )
                Save -> saveDraft { model | afterSave = Nothing }
                SaveAndContinue -> saveDraft { model | afterSave = model.pending }
                Discard -> case model.pending of
                    Just action -> perform action model
                    Nothing -> ( model, Cmd.none )
                Stay -> ( { model | pending = Nothing, afterSave = Nothing }, Cmd.none )
                Confirm -> case model.confirmation of
                    Just mutation -> write mutation model
                    Nothing -> ( model, Cmd.none )
                Cancel -> ( { model | confirmation = Nothing, afterSave = Nothing }, Cmd.none )
                _ -> ( model, Cmd.none )


btn : Model -> String -> Msg -> Html Msg
btn model title msg =
    button [ A.type_ "button", A.class "secondary", A.disabled (model.busy || model.loading), onClick msg ] [ text title ]


card : String -> String -> List (Html Msg) -> Html Msg
card title description children =
    section [ A.class "card" ] ([ h3 [] [ text title ], p [] [ text description ] ] ++ children)


textField : Model -> Draft -> String -> String -> String -> Html Msg
textField model draft key title kind =
    label []
        [ text title
        , input
            ([ A.name key, A.type_ kind, A.value (value key draft), onInput (Changed key), A.disabled (model.busy || model.loading || model.pending /= Nothing || model.confirmation /= Nothing), A.required (List.member key [ "name", "email", "timezone" ]), A.minlength (if key == "password" then 12 else 0), A.attribute "autocomplete" (if key == "password" then "new-password" else "off") ] ++ (if key == "timezone" then [ A.attribute "list" "workspace-timezones", A.attribute "aria-describedby" "workspace-timezone-help" ] else [])) []
        ]


choice : Model -> String -> String -> List ( String, String ) -> String -> (String -> Msg) -> Html Msg
choice model key title options selected changed =
    label [] [ text title, select [ A.name key, A.value selected, onInput changed, A.disabled (model.busy || model.loading || model.pending /= Nothing || model.confirmation /= Nothing) ] (List.map (\( id, titleValue ) -> option [ A.value id, A.selected (selected == id) ] [ text titleValue ]) options) ]


named : String -> List D.Value -> String
named id values =
    find id values |> Maybe.map (str "name") |> Maybe.withDefault "No team"


timezoneField : Model -> Draft -> Html Msg
timezoneField model draft =
    div []
        [ textField model draft "timezone" "Workspace timezone — choose a city or enter a zone" "text"
        , datalist [ A.id "workspace-timezones" ]
            (List.map (\( zone, city ) -> option [ A.value zone, A.attribute "label" city ] [ text city ])
                [ ( "Asia/Manila", "Manila, Philippines" )
                , ( "Asia/Singapore", "Singapore" )
                , ( "Asia/Hong_Kong", "Hong Kong" )
                , ( "Asia/Kuala_Lumpur", "Kuala Lumpur, Malaysia" )
                , ( "Asia/Bangkok", "Bangkok, Thailand" )
                , ( "Asia/Jakarta", "Jakarta, Indonesia" )
                , ( "Asia/Tokyo", "Tokyo, Japan" )
                , ( "Asia/Seoul", "Seoul, South Korea" )
                , ( "Asia/Kolkata", "India" )
                , ( "Asia/Dubai", "Dubai, UAE" )
                , ( "Australia/Sydney", "Sydney, Australia" )
                , ( "Australia/Brisbane", "Brisbane, Australia" )
                , ( "Australia/Perth", "Perth, Australia" )
                , ( "Pacific/Auckland", "Auckland, New Zealand" )
                , ( "Europe/London", "London, United Kingdom" )
                , ( "Europe/Paris", "Paris, France" )
                , ( "Europe/Berlin", "Berlin, Germany" )
                , ( "America/New_York", "New York, United States" )
                , ( "America/Chicago", "Chicago, United States" )
                , ( "America/Denver", "Denver, United States" )
                , ( "America/Los_Angeles", "Los Angeles, United States" )
                , ( "America/Toronto", "Toronto, Canada" )
                , ( "America/Vancouver", "Vancouver, Canada" )
                , ( "UTC", "Coordinated Universal Time" )
                ]
            )
        , p [ A.id "workspace-timezone-help" ] [ text "Start typing a zone to see suggestions. Other valid IANA zones are accepted. Daylight-saving rules follow the selected zone automatically; there is no separate switch. This setting controls workspace dates." ]
        ]


formView : Model -> Snapshot -> Draft -> Html Msg
formView model data draft =
    let
        teams = ( "", "No team" ) :: List.map (\team -> ( str "id" team, str "name" team )) data.teams
        roles = List.map (\role -> ( str "id" role, str "name" role )) data.levels
        dropdown key fieldTitle options = choice model key fieldTitle options (value key draft) (Changed key)
        name = textField model draft "name" "Full name" "text"
        ( title, description, ( fields, saveLabel ) ) =
            case draft.kind of
                NewUser -> ( "Add a user", "Leave the password empty for a single-use invitation lasting 72 hours. Email delivery requires SMTP; invitations can also be shared manually.", ( [ name, textField model draft "email" "Email" "email", dropdown "role" "Access level" roles, dropdown "teamId" "Team" teams, textField model draft "password" "Initial password (optional)" "password" ], "Create user" ) )
                EditUser _ -> ( "Manage account", "Saving access changes signs this user out on all devices. Keep at least one active Administrator.", ( [ name, dropdown "role" "Access level" roles, dropdown "teamId" "Team" teams ], "Save access" ) )
                NewTeam -> ( "Create a team", "Team assignments are managed under Users.", ( [ textField model draft "name" "Team name" "text" ], "Create team" ) )
                Workspace -> ( "Workspace settings", "Choose the location whose dates your workspace should use. Leave allowed networks empty for unrestricted access; an allowlist must include your current network.", ( [ textField model draft "name" "Workspace name" "text", timezoneField model draft, dropdown "currency" "Reporting currency" (List.map (\currency -> ( currency, currency )) [ "USD", "EUR", "GBP", "CAD", "AUD", "NZD", "PHP", "SGD", "INR", "JPY", "CNY", "AED", "HKD", "CHF", "KRW", "MYR", "THB", "IDR" ]), textField model draft "ipAllowlist" "Allowed IP addresses / CIDRs" "text" ], "Save settings" ) )
    in
    card title description
        [ form [ onSubmit Save ]
            [ div [ A.class "fields" ] fields
            , button [ A.type_ "submit", A.disabled (model.busy || model.loading) ] [ text saveLabel ]
            ]
        , case draft.kind of
            EditUser id ->
                case find id data.users of
                    Just user -> accountActions model user
                    Nothing -> text ""
            NewUser -> btn model "Close" (Request Close)
            _ -> text ""
        ]


accountActions : Model -> D.Value -> Html Msg
accountActions model user =
    let
        id = str "id" user
        base = "/api/admin/users/" ++ id
        action title path method payload message = btn model title (Request (Account (Mutation path method payload (Just id) message)))
        disabled = bool "disabled" user
        invited = disabled && str "invitationExpiresAt" user /= ""
    in
    div [ A.class "admin-actions" ]
        ([ if invited then action "Renew invitation" (base ++ "/invitation") "POST" (E.object []) "Replace the previous invitation with a new 72-hour link?"
           else action (if disabled then "Enable account" else "Disable account") base "PATCH" (E.object [ ( "disabled", E.bool (not disabled) ) ]) (if disabled then "Enable sign-in for this account?" else "Disable sign-in and revoke sessions and access links for this account?")
         ]
            ++ (if invited then [ action "Cancel invitation" base "PATCH" (E.object [ ( "disabled", E.bool True ) ]) "Cancel the invitation and keep this account disabled?" ] else [])
            ++ (if not disabled then [ action "Sign out all devices" (base ++ "/revoke-sessions") "POST" (E.object []) "Sign out all devices for this user?", action "Send password recovery" (base ++ "/password-reset") "POST" (E.object []) "Queue a password recovery email to the account owner's email? The link expires in 30 minutes." ] else [])
            ++ (if bool "twoFactorEnabled" user then [ action "Reset two-factor authentication" base "PATCH" (E.object [ ( "resetTwoFactor", E.bool True ) ]) "Remove two-factor authentication and recovery codes and sign out all devices?" ] else [])
            ++ [ btn model "Close" (Request Close) ]
        )


tableView : List String -> List (List (Html Msg)) -> Html Msg
tableView titles entries =
    if List.isEmpty entries then p [] [ text "No matching entries." ]
    else div [ A.class "table-wrap" ] [ table [] [ thead [] [ tr [] (List.map (\title -> th [ A.scope "col" ] [ text title ]) titles) ], tbody [] (List.map (\cells -> tr [] (List.map (\cell -> td [] [ cell ]) cells)) entries) ] ]


jsonTable : List ( String, String ) -> List D.Value -> Html Msg
jsonTable columns entries =
    tableView (List.map Tuple.second columns) (List.map (\row -> List.map (\( key, _ ) -> text (if str key row == "" then "—" else str key row)) columns) entries)


securityTime : String -> String
securityTime timestamp =
    if timestamp == "" then "—"
    else if String.endsWith "Z" timestamp && String.contains "T" timestamp then
        String.replace "T" " " (String.dropRight 1 timestamp) ++ " UTC"
    else timestamp


securityEventLabel : List D.Value -> String -> String
securityEventLabel users event =
    let
        code = String.split ":" event |> List.head |> Maybe.withDefault event
        target = String.split ":" event |> List.drop 1 |> String.join ":"
        person = users |> List.filter (\user -> str "id" user == target) |> List.head |> Maybe.map (str "name") |> Maybe.withDefault target
        labels = Dict.fromList
            [ ( "login.succeeded", "Signed in" ), ( "login.failed", "Sign-in failed" )
            , ( "login.ip_denied", "Sign-in blocked by IP policy" ), ( "login.sso_mfa", "Signed in with SSO and two-factor authentication" )
            , ( "login.oidc", "Signed in with OpenID Connect" ), ( "login.saml", "Signed in with SAML" )
            , ( "account.created", "Account created" ), ( "invite.accepted", "Invitation accepted" )
            , ( "two_factor.enabled", "Two-factor authentication enabled" ), ( "two_factor.disabled", "Two-factor authentication disabled" )
            , ( "password_reset.requested", "Password reset requested" ), ( "password_reset.completed", "Password reset completed" )
            , ( "admin.user_created", "User created" ), ( "admin.user_updated", "User access updated" )
            , ( "admin.sessions_revoked", "Signed out all devices" )
            , ( "admin.reset_link_created", "Password reset link created" ), ( "admin.invite_link_created", "Invitation link created" )
            , ( "trash.policy_updated", "Trash retention policy updated" ), ( "trash.purged", "Trash purged" )
            , ( "escalation.rule_saved", "Escalation rule saved" ), ( "application.gate_policy_updated", "Application stage policy updated" )
            ]
    in
    case Dict.get code labels of
        Just title -> title ++ (if target == "" then "" else ": " ++ person)
        Nothing -> event


content : Model -> Snapshot -> List (Html Msg)
content model data =
    let
        draft = model.draft |> Maybe.map (formView model data) |> Maybe.withDefault (text "")
    in
    case model.tab of
        "users" ->
            let
                matching = data.users |> List.filter (\u -> (model.search == "" || String.contains (String.toLower model.search) (String.toLower (str "name" u ++ " " ++ str "email" u))) && (model.role == "" || model.role == str "role" u) && (model.status == "" || model.status == str "status" u))
            in
            [ div [ A.class "toolbar" ]
                [ label [] [ text "Search users", input [ A.type_ "search", A.value model.search, onInput Search, A.disabled model.busy ] [] ]
                , choice model "roleFilter" "Access level" (( "", "All levels" ) :: List.map (\role -> ( str "id" role, str "name" role )) data.levels) model.role FilterRole
                , choice model "statusFilter" "Status" (List.map (\status -> ( status, if status == "" then "All statuses" else status )) [ "", "Active", "Invited", "Invitation expired", "Disabled" ]) model.status FilterStatus
                , btn model "Add user" (Request Create)
                ]
            , draft
            , p [] [ text (String.fromInt (List.length matching) ++ " of " ++ String.fromInt (List.length data.users) ++ " users") ]
            , tableView [ "Name", "Email", "Access level", "Team", "Status", "2FA", "Sessions", "Actions" ] (List.map (\u -> [ text (str "name" u), text (str "email" u), text (named (str "role" u) data.levels), text (named (str "teamId" u) data.teams), text (str "status" u), text (if bool "twoFactorEnabled" u then "Enabled" else "Off"), text (str "activeSessions" u), button [ A.type_ "button", A.class "secondary", A.attribute "aria-label" ("Manage " ++ str "name" u), A.disabled (model.busy || model.loading), onClick (Request (Manage (str "id" u))) ] [ text "Manage" ] ]) matching)
            ]
        "teams" ->
            [ card "Teams" "Team assignment controls which team-shared records a user can read. Change assignments from Users." [ tableView [ "Team", "Users" ] (List.map (\team -> [ text (str "name" team), text (String.fromInt (List.length (List.filter (\u -> str "teamId" u == str "id" team) data.users))) ]) data.teams) ], draft ]
        "levels" ->
            [ card "Access levels" "These four levels are enforced by the server. Reports and exports contain only records the user can read." [ tableView [ "Level", "Read records", "Create / edit / delete", "Client invitations / trash", "Manage users", "Workspace settings" ] (List.map (\level -> List.map (\key -> text (str key level)) [ "name", "read", "write" ] ++ List.map (\key -> text (if bool key level then "Allowed" else "No")) [ "recovery", "users", "settings" ]) data.levels) ]
            , card "Record visibility" "Administrator and Manager roles can access all records in their workspace. Member and Viewer access follows record ownership and visibility." [ tableView [ "Visibility", "Who can read" ] (List.map (List.map text) [ [ "Private", "Owner, Administrators and Managers" ], [ "Team", "Owner, matching team, Administrators and Managers" ], [ "Organization", "All users in this workspace" ] ]), link model "Manage record ownership and visibility" "/workspace?tab=team" ]
            ]
        "security" ->
            [ card "Active sessions" "The 100 most recently active sessions in this workspace. Account access changes revoke all previous sessions." [ tableView [ "User", "Browser / device", "IP address", "Last active (UTC)", "Actions" ] (List.map (\row -> List.map (\key -> text (str key row)) [ "name", "userAgent", "ip" ] ++ [ text (securityTime (str "lastSeen" row)) ] ++ [ btn model "Sign out all devices" (Request (Account (Mutation ("/api/admin/users/" ++ str "userId" row ++ "/revoke-sessions") "POST" (E.object []) (Just (str "userId" row)) ("Sign out all devices for " ++ str "name" row ++ "?")))) ]) data.sessions) ]
            , card "User access history" "The 100 most recent user changes, with the administrator who made each change." [ jsonTable [ ( "actor", "Changed by" ), ( "label", "User" ), ( "action", "Action" ), ( "occurredAt", "When (UTC)" ) ] (List.map (\row -> E.object [ ( "actor", E.string (str "actor" row) ), ( "label", E.string (str "label" row) ), ( "action", E.string (str "action" row) ), ( "occurredAt", E.string (securityTime (str "occurredAt" row)) ) ]) data.changes) ]
            , card "Login and security history" "The 100 most recent security events in this workspace." [ tableView [ "User / actor", "Event", "IP address", "When (UTC)" ] (List.map (\row -> [ text (str "name" row), text (securityEventLabel data.users (str "event" row)), text (str "ip" row), text (securityTime (str "occurredAt" row)) ]) data.security) ]
            ]
        "settings" ->
            [ draft, card "Integrations" "Configure email delivery, AI assistance and webhooks." [ link model "Open integration settings" "/workspace?tab=integrations" ], card "Workspace readiness" "Review setup, delivery failures, backup status and isolated restore verification." [ link model "Getting started & readiness" "/workspace?tab=readiness" ] ]
        _ -> []


link : Model -> String -> String -> Html Msg
link model title path =
    button [ A.type_ "button", A.class "secondary", A.disabled (model.busy || model.loading), onClick (Request (Exit path)) ] [ text title ]


view : Model -> Html Msg
view model =
    div [ A.class "administration-elm" ]
        [ Html.node "link" [ A.rel "stylesheet", A.href "/public/administration-elm.css" ] []
        , section [ A.class "tools administration", A.attribute "aria-busy" (if model.busy || model.loading then "true" else "false") ]
            [ header [] [ div [] [ h2 [] [ text "System administration" ], p [] [ text "Manage workspace users, access, teams, security and settings." ] ], btn model "Refresh" (Request Refresh) ]
            , div [ A.id "notice", A.attribute "role" "status", A.attribute "aria-live" "polite", A.class (if model.error then "error" else "") ]
                ([ text model.notice ] ++ (if model.invitation == "" then [] else [ p [] [ text "Share this private invitation with the intended user. It expires in 72 hours." ], input [ A.type_ "text", A.readonly True, A.attribute "aria-label" "Private invitation link", A.value model.invitation ] [] ]))
            , case model.pending of
                Just _ -> card "Unsaved changes" "Save your changes before continuing, discard them, or stay on this form." [ div [ A.attribute "role" "alert" ] [ btn model "Save" SaveAndContinue, btn model "Discard" Discard, btn model "Stay" Stay ] ]
                Nothing -> text ""
            , case model.confirmation of
                Just mutation -> if model.busy then text "" else card "Confirm account change" mutation.message [ div [ A.attribute "role" "alert" ] [ btn model "Confirm" Confirm, btn model "Cancel" Cancel ] ]
                Nothing -> text ""
            , if model.loading then p [ A.attribute "role" "status" ] [ text "Loading administration…" ] else text ""
            , case model.data of
                Nothing -> text ""
                Just data ->
                    div []
                        [ div [ A.class "admin-metrics" ] (List.map (\( title, count ) -> card title "" [ strong [ A.class "metric" ] [ text (String.fromInt count) ] ]) [ ( "Users", List.length data.users ), ( "Active", List.length (List.filter (\u -> not (bool "disabled" u)) data.users) ), ( "Administrators", List.length (List.filter (\u -> not (bool "disabled" u) && str "role" u == "admin") data.users) ), ( "Awaiting invitation", List.length (List.filter (\u -> bool "disabled" u && str "invitationExpiresAt" u /= "") data.users) ) ])
                        , nav [ A.attribute "aria-label" "Administration sections" ] (List.map (\( key, title ) -> button [ A.type_ "button", A.disabled (model.busy || model.loading), A.attribute "aria-current" (if key == model.tab then "page" else "false"), onClick (if key == model.tab then Stay else Request (Switch key)) ] [ text title ]) [ ( "users", "Users" ), ( "levels", "Access levels" ), ( "teams", "Teams" ), ( "security", "Security" ), ( "settings", "Workspace settings" ) ])
                        , div [] (content model data)
                        ]
            ]
        ]
