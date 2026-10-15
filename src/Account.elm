module Account exposing (Mode(..), Msg(..), Model, decodeSuccess, init, main, update)

import Browser
import Browser.Navigation as Nav
import Dict exposing (Dict)
import Html exposing (..)
import Html.Attributes exposing (alt, attribute, class, disabled, href, id, maxlength, minlength, name, required, src, style, type_, value)
import Html.Events exposing (onInput, onSubmit)
import Http
import Json.Decode as D
import Json.Encode as E
import Url


type Mode
    = Forgot
    | Reset
    | Invite
    | Sso


type alias Flags =
    { path : String, query : String }


type alias Model =
    { mode : Mode, token : String, fields : Dict String String, busy : Bool, message : String, error : Bool }


type Msg
    = Changed String String
    | Submit
    | Saved (Result String String)


init : Flags -> ( Model, Cmd Msg )
init flags =
    let
        mode =
            if String.contains "invite" flags.path then Invite
            else if String.contains "sso" flags.path then Sso
            else if String.contains "reset" flags.path then Reset
            else Forgot
        token =
            flags.query
                |> String.dropLeft 1
                |> String.split "&"
                |> List.filterMap (\part -> if String.startsWith "token=" part then Url.percentDecode (String.replace "+" " " (String.dropLeft 6 part)) else Nothing)
                |> List.head
                |> Maybe.withDefault ""
    in
    ( { mode = mode, token = token, fields = Dict.empty, busy = False, message = "", error = False }, Cmd.none )


fieldValue : String -> Model -> String
fieldValue key model =
    Dict.get key model.fields |> Maybe.withDefault ""


decodeSuccess : Mode -> String -> Result String String
decodeSuccess mode body =
    let
        decoder =
            if mode == Sso then
                D.field "status" D.string
                    |> D.andThen (\status -> if status == "ok" then D.succeed "Signed in." else D.fail "Unexpected sign-in status")
            else
                D.field "message" D.string
                    |> D.andThen (\message -> if String.isEmpty (String.trim message) then D.fail "Missing confirmation" else D.succeed message)
    in
    D.decodeString decoder body
        |> Result.mapError (\_ -> "The server returned an unexpected response. Please try again.")


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Changed key field ->
            if model.busy then ( model, Cmd.none ) else ( { model | fields = Dict.insert key field model.fields }, Cmd.none )
        Submit ->
            if model.busy then ( model, Cmd.none )
            else
                let
                    path = case model.mode of
                        Forgot -> "/api/forgot-password"
                        Reset -> "/api/reset-password"
                        Invite -> "/api/invites/accept"
                        Sso -> "/api/sso/finish"
                    body = ( "token", E.string model.token ) :: (model.fields |> Dict.toList |> List.map (Tuple.mapSecond E.string))
                    expectation =
                        Http.expectStringResponse Saved
                            (\response ->
                                case response of
                                    Http.GoodStatus_ _ result -> decodeSuccess model.mode result
                                    Http.BadStatus_ _ result -> Err (D.decodeString (D.oneOf [ D.field "message" D.string, D.field "error" D.string ]) result |> Result.withDefault "Please try again.")
                                    Http.Timeout_ -> Err "The request timed out. Please try again."
                                    _ -> Err "Could not connect. Please try again."
                            )
                in
                ( { model | busy = True, message = "Working…", error = False }
                , Http.post { url = path, body = Http.jsonBody (E.object body), expect = expectation }
                )
        Saved result ->
            case result of
                Err message -> ( { model | busy = False, error = True, message = message ++ " Your entries are kept." }, Cmd.none )
                Ok message ->
                    ( { model | busy = False, error = False, message = message, fields = Dict.remove "password" model.fields }
                    , if model.mode == Sso then Nav.load "/" else Cmd.none
                    )


view : Model -> Html Msg
view model =
    let
        titleValue = case model.mode of
            Forgot -> "Forgot your password?"
            Reset -> "Choose a new password"
            Invite -> "Join your workspace"
            Sso -> "Verify your sign-in"
        description = case model.mode of
            Forgot -> "Enter your email. If an account exists, a recovery link will be queued for delivery."
            Sso -> "Enter your authenticator or recovery code."
            _ -> "Use at least 12 characters for your password."
        fields = case model.mode of
            Forgot -> [ ( "email", "Email", "email" ) ]
            Sso -> [ ( "code", "Authenticator / recovery code", "text" ) ]
            Invite -> [ ( "name", "Full name", "text" ), ( "password", "Password", "password" ) ]
            Reset -> [ ( "password", "New password", "password" ) ]
        field ( key, titleText, kind ) =
            label [ class "wide" ]
                [ text titleText
                , input ([ name key, type_ kind, required True, value (fieldValue key model), onInput (Changed key), disabled model.busy ] ++ (if kind == "password" then [ minlength 12, maxlength 72, attribute "autocomplete" "new-password" ] else [])) []
                ]
    in
    main_ [ class "tools", style "max-width" "540px", style "padding-top" "10vh" ]
        [ p [ class "eyebrow" ] [ text "ECC CRM" ]
        , section [ class "card" ]
            [ img [ class "aux-brand-logo", src "/public/icons/ecc-192.png", alt "ECC Consulting Global emblem" ] []
            , h1 [ id "title" ] [ text titleValue ]
            , p [ id "description" ] [ text description ]
            , form [ id "form", onSubmit Submit ]
                [ div [ id "fields", class "fields" ] (List.map field fields)
                , div [ class "actions" ] [ button [ id "submit", type_ "submit", disabled model.busy ] [ text (if model.busy then "Working…" else "Continue") ], a [ href "/" ] [ text "Back to sign in" ] ]
                ]
            , div [ id "notice", attribute "role" "status", attribute "aria-live" "polite", class (if model.error then "error" else "") ] [ text model.message ]
            ]
        ]


main : Program Flags Model Msg
main =
    Browser.element { init = init, update = update, view = view, subscriptions = \_ -> Sub.none }
