port module AdministrationChecks exposing (main)

import Account
import TeamChat as Chat
import Administration as Admin
import Dict
import Json.Decode as D
import Json.Encode as E
import Platform
import DashboardChecks
import RecordBrowserChecks
import ReportChecks
import Random

port results : E.Value -> Cmd msg

step msg model =
    Admin.update msg model |> Tuple.first

fields model =
    model.draft |> Maybe.map .values |> Maybe.withDefault Dict.empty

has key expected model =
    Dict.get key (fields model) == Just expected

fixture =
    """{"currentUserId":"admin","organization":[{"name":"Workspace","timezone":"Asia/Manila","currency":"PHP","ipAllowlist":""}],"teams":[{"id":"team","name":"Advising"}],"accessLevels":[{"id":"admin","name":"Administrator"},{"id":"member","name":"Member"},{"id":"manager","name":"Manager"}],"users":[{"id":"admin","name":"Admin","email":"admin@test.invalid","role":"admin","teamId":"team","disabled":false,"accessVersion":"admin-v1"},{"id":"member","name":"Member","email":"member@test.invalid","role":"member","teamId":"team","disabled":false,"accessVersion":"member-v1"}],"sessions":[],"changes":[],"security":[]}"""

checks data =
    let
        loaded = step (Admin.Loaded 0 (Ok data)) Admin.init
        editing = loaded |> step (Admin.Request (Admin.Manage "member"))
        dirty = editing |> step (Admin.Changed "name" "Updated member")
        leave = dirty |> step (Admin.Request (Admin.Switch "teams"))
        stay = leave |> step Admin.Stay
        discard = leave |> step Admin.Discard
        saving = leave |> step Admin.SaveAndContinue
        failed = saving |> step (Admin.Saved saving.generation (Err "This user's access changed. Refresh administration before saving again."))
        saved = saving |> step (Admin.Saved saving.generation (Ok (E.object [])))
        continued = saved |> step (Admin.Loaded saved.generation (Ok data))
        roleChange = editing |> step (Admin.Changed "role" "manager") |> step (Admin.Request (Admin.Switch "settings")) |> step Admin.SaveAndContinue
        cancelled = roleChange |> step Admin.Cancel
        confirmed = roleChange |> step Admin.Confirm
        confirmedSaved = confirmed |> step (Admin.Saved confirmed.generation (Ok (E.object [])))
        confirmedLoaded = confirmedSaved |> step (Admin.Loaded confirmedSaved.generation (Ok data))
        creating = loaded |> step (Admin.Request Admin.Create) |> step (Admin.Changed "name" "New user")
        invalid = creating |> step (Admin.Request (Admin.Switch "teams")) |> step Admin.SaveAndContinue
        settings = loaded |> step (Admin.Request (Admin.Switch "settings")) |> step (Admin.Changed "timezone" "Europe/London")
        refreshing = settings |> step (Admin.Request Admin.Refresh)
        switchingUser = dirty |> step (Admin.Request (Admin.Manage "admin"))
        switchingCreate = dirty |> step (Admin.Request Admin.Create)
        closing = dirty |> step (Admin.Request Admin.Close)
        signingOut = dirty |> step (Admin.Request Admin.SignOut)
        signedOut = signingOut |> step Admin.Discard
        stale = dirty |> step (Admin.Loaded -1 (Ok data))
        retry = saving |> step (Admin.Saved saving.generation (Err "session-expired"))
        retryFailed = retry |> step (Admin.Saved retry.generation (Err "session-expired"))
    in
    [ ( "Opening an unchanged form does not prompt", not (Admin.dirty editing) )
    , ( "Actual edits mark the form dirty", Admin.dirty dirty )
    , ( "Returning to original values clears dirty state", not (Admin.dirty (dirty |> step (Admin.Changed "name" "Member"))) )
    , ( "Switching sections keeps the form until a decision", leave.tab == "users" && leave.pending /= Nothing && has "name" "Updated member" leave )
    , ( "Stay keeps entries and cancels navigation", stay.pending == Nothing && has "name" "Updated member" stay )
    , ( "Discard continues to the requested section", discard.tab == "teams" && not (Admin.dirty discard) )
    , ( "Save blocks navigation while the request is pending", saving.busy && saving.tab == "users" && saving.afterSave /= Nothing )
    , ( "Failed save preserves the draft and cancels navigation", not failed.busy && failed.tab == "users" && has "name" "Updated member" failed && failed.afterSave == Nothing && failed.error )
    , ( "Successful save continues after reloading", continued.tab == "teams" && continued.afterSave == Nothing && not continued.busy )
    , ( "Role changes still require account confirmation", roleChange.confirmation /= Nothing && not roleChange.busy && roleChange.tab == "users" )
    , ( "Cancelling account confirmation keeps the edited form", cancelled.confirmation == Nothing && cancelled.afterSave == Nothing && has "role" "manager" cancelled )
    , ( "Confirmed access save continues to the requested section", confirmedLoaded.tab == "settings" && has "timezone" "Asia/Manila" confirmedLoaded )
    , ( "Validation failures keep the new-user draft", invalid.error && not invalid.busy && has "name" "New user" invalid && invalid.tab == "users" && invalid.afterSave == Nothing )
    , ( "Refresh prompts without replacing settings", refreshing.pending /= Nothing && has "timezone" "Europe/London" refreshing )
    , ( "Managing a different account prompts before replacing edits", switchingUser.pending /= Nothing && has "name" "Updated member" switchingUser )
    , ( "Add user prompts before replacing edits", switchingCreate.pending /= Nothing && has "name" "Updated member" switchingCreate )
    , ( "Close prompts before replacing edits", closing.pending /= Nothing && has "name" "Updated member" closing )
    , ( "Sign out prompts and only proceeds after a decision", signingOut.pending /= Nothing && not signingOut.signOut && signedOut.signOut )
    , ( "Obsolete replies cannot replace drafts", has "name" "Updated member" stale )
    , ( "A second expired-session response stops retrying and preserves edits", retry.retried && not retryFailed.busy && retryFailed.error && has "name" "Updated member" retryFailed )
    ]

propertyChecks data =
    let
        generator = Random.list 1000 (Random.pair (Random.int 0 6) (Random.list 24 (Random.int 32 1024)))
        ( samples, _ ) = Random.step generator (Random.initialSeed 20261014)
        run index ( actionNumber, characters ) =
            let
                entry = "Draft " ++ String.fromList (List.map Char.fromCode characters)
                action = case actionNumber of
                    0 -> Admin.Switch "teams"
                    1 -> Admin.Switch "settings"
                    2 -> Admin.Refresh
                    3 -> Admin.Close
                    4 -> Admin.Create
                    5 -> Admin.Manage "admin"
                    _ -> Admin.SignOut
                edited = Admin.init |> step (Admin.Loaded 0 (Ok data)) |> step (Admin.Request (Admin.Manage "member")) |> step (Admin.Changed "name" entry)
                guarded = edited |> step (Admin.Request action)
                stayed = guarded |> step Admin.Stay
                saving = guarded |> step Admin.SaveAndContinue
                failed = saving |> step (Admin.Saved saving.generation (Err "Injected save failure"))
            in
            ( "Property seed 20261014 case " ++ String.fromInt index ++ ": failed saves and Stay preserve drafts for every navigation action"
            , guarded.pending /= Nothing && has "name" entry guarded && stayed.pending == Nothing && has "name" entry stayed && has "name" entry failed && failed.tab == "users" && failed.afterSave == Nothing && not failed.signOut
            )
    in
    List.indexedMap run samples

chatChecks =
    let
        peer = { id = "peer", name = "Colleague", role = "member", unread = 2 }
        other = { id = "other", name = "Other colleague", role = "member", unread = 0 }
        started = Chat.start "self" Chat.init |> Tuple.first
        selected = Chat.update (Chat.Choose peer) started |> Tuple.first
        drafted = Chat.update (Chat.Changed "Unsent draft") selected |> Tuple.first
        switched = Chat.update (Chat.Choose other) drafted |> Tuple.first
        returned = Chat.update (Chat.Choose peer) switched |> Tuple.first
        sending = Chat.update (Chat.ClientId "self" "peer" "Unsent draft" [ 1, 2, 3, 4 ]) drafted |> Tuple.first
        pending = { userId = "self", peer = "peer", body = "Unsent draft", clientId = "elm-1-2-3-4" }
        failed = Chat.update (Chat.Sent pending (Err "Offline")) sending |> Tuple.first
        retried = Chat.update Chat.Send failed |> Tuple.first
        changed = Chat.update (Chat.Changed "Newer draft") sending |> Tuple.first
        succeeded = Chat.update (Chat.Sent pending (Ok ())) changed |> Tuple.first
        stale = Chat.update (Chat.MessagesLoaded "self" (selected.generation - 1) False (Ok [ { id = 1, senderId = "peer", body = "Old", createdAt = "2026-10-14T00:00:00Z" } ])) selected |> Tuple.first
        newUser = Chat.start "new-user" drafted |> Tuple.first
        foreign = Chat.update (Chat.PeopleLoaded "self" newUser.rosterRequest 0 (Ok [ peer ])) newUser |> Tuple.first
        foreignSend = Chat.update (Chat.Sent pending (Ok ())) newUser |> Tuple.first
    in
    [ ( "Chat keeps unsent drafts when switching colleagues", Dict.get "peer" returned.drafts == Just "Unsent draft" )
    , ( "Chat keeps the draft after a failed send", Dict.get "peer" failed.drafts == Just "Unsent draft" && not failed.sending )
    , ( "Chat retries with the same message identifier", retried.pending == failed.pending && retried.sending )
    , ( "Successful send cannot erase newer text", Dict.get "peer" succeeded.drafts == Just "Newer draft" )
    , ( "Late conversation replies cannot replace a new conversation", Dict.isEmpty stale.messages )
    , ( "Chat drafts do not cross signed-in accounts", Dict.isEmpty newUser.drafts )
    , ( "Late colleague replies from another account are ignored", Dict.isEmpty foreign.people )
    , ( "Late send replies from another account are ignored", foreignSend.userId == "new-user" && Dict.isEmpty foreignSend.drafts )
    ]

accountChecks =
    let
        invite = Account.init { path = "/accept-invite", query = "?token=private%2Btoken" } |> Tuple.first
        drafted = Account.update (Account.Changed "password" "SecretPassword123!") invite |> Tuple.first
        failed = Account.update (Account.Saved (Err "Link expired")) drafted |> Tuple.first
        saved = Account.update (Account.Saved (Ok "Accepted")) drafted |> Tuple.first
    in
    [ ( "Invitation mode decodes its token correctly", invite.mode == Account.Invite && invite.token == "private+token" )
    , ( "Account recovery keeps entries after failed saves", Dict.get "password" failed.fields == Just "SecretPassword123!" && failed.error )
    , ( "Successful account changes clear the password from form state", Dict.get "password" saved.fields == Nothing )
    , ( "Recovery requires a valid confirmation", Account.decodeSuccess Account.Reset "{\"message\":\"Password changed\"}" == Ok "Password changed" )
    , ( "SSO requires the server success status", Account.decodeSuccess Account.Sso "{\"status\":\"ok\"}" == Ok "Signed in." )
    , ( "Malformed recovery responses retain the password", List.all (\body -> let result = Account.decodeSuccess Account.Reset body in (Account.update (Account.Saved result) drafted |> Tuple.first).fields == drafted.fields && Result.toMaybe result == Nothing) [ "<html>Unavailable</html>", "null", "{}", "{\"message\":5}", "{\"message\":\" \"}" ] )
    , ( "SSO rejects malformed or unsuccessful responses", List.all (\body -> Result.toMaybe (Account.decodeSuccess Account.Sso body) == Nothing) [ "{}", "{\"status\":\"failed\"}", "{\"message\":\"ok\"}", "invalid" ] )
    ]

main =
    Platform.worker
        { init = \() ->
            let
                output =
                    case D.decodeString Admin.decoder fixture of
                        Ok data -> checks data ++ chatChecks ++ accountChecks ++ propertyChecks data ++ ReportChecks.checks ++ RecordBrowserChecks.checks ++ DashboardChecks.checks
                        Err _ -> [ ( "Fixture decodes", False ) ]
            in
            ( (), results (E.list (\( name, passed ) -> E.object [ ( "name", E.string name ), ( "passed", E.bool passed ) ]) output) )
        , update = \_ model -> ( model, Cmd.none )
        , subscriptions = \_ -> Sub.none
        }
