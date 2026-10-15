module Update.Settings exposing (update)

{-| Profile, password and session settings messages.
-}

import Api
import Ports exposing (storeToken)
import Types exposing (..)
import Update.Auth


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpdatedProfileField field value ->
            let
                pf =
                    model.profileForm

                updated =
                    case field of
                        "name" ->
                            { pf | name = value }

                        "email" ->
                            { pf | email = value }

                        _ ->
                            pf
            in
            ( { model
                | profileForm =
                    { updated
                        | errors = List.filter (\( f, _ ) -> f /= field) updated.errors
                        , success = Nothing
                    }
              }
            , Cmd.none
            )

        SubmittedProfile ->
            case model.token of
                Just token ->
                    let
                        pf =
                            model.profileForm

                        errs =
                            List.filterMap identity
                                [ if String.isEmpty (String.trim pf.name) then
                                    Just ( "name", "Name is required." )

                                  else
                                    Nothing
                                , if not (String.contains "@" pf.email && String.contains "." pf.email) then
                                    Just ( "email", "Please enter a valid email." )

                                  else
                                    Nothing
                                ]
                    in
                    if not (List.isEmpty errs) then
                        ( { model | profileForm = { pf | errors = errs } }, Cmd.none )

                    else
                        ( { model
                            | profileForm =
                                { pf
                                    | submitting = True
                                    , errors = []
                                    , success = Nothing
                                }
                          }
                        , Api.updateMe token pf.name pf.email GotUpdatedProfile
                        )

                Nothing ->
                    ( model, Cmd.none )

        GotUpdatedProfile result ->
            let
                pf =
                    model.profileForm
            in
            case result of
                Ok res ->
                    if model.user == Nothing || model.sessionOwner /= Just res.user.id then
                        ( model, Cmd.none )
                    else
                    ( { model
                        | profileForm =
                            { pf
                                | submitting = False
                                , success = Just "Profile updated."
                            }
                        , user = Just res.user
                        , token = Just res.token
                      }
                    , storeToken (Just res.token)
                    )

                Err (FieldErrors fields) ->
                    ( { model
                        | profileForm =
                            { pf | submitting = False, errors = fields }
                      }
                    , Cmd.none
                    )

                Err (GenericError message) ->
                    ( { model
                        | profileForm =
                            { pf
                                | submitting = False
                                , errors = [ ( "form", message ) ]
                            }
                      }
                    , Cmd.none
                    )

        UpdatedPasswordField field value ->
            let
                pf =
                    model.passwordForm

                updated =
                    case field of
                        "current" ->
                            { pf | current = value }

                        "next" ->
                            { pf | next = value }

                        "confirm" ->
                            { pf | confirm = value }

                        _ ->
                            pf
            in
            ( { model
                | passwordForm =
                    { updated
                        | errors = List.filter (\( f, _ ) -> f /= field) updated.errors
                        , success = Nothing
                    }
              }
            , Cmd.none
            )

        SubmittedPassword ->
            case model.token of
                Just token ->
                    let
                        pf =
                            model.passwordForm

                        errs =
                            List.filterMap identity
                                [ if String.isEmpty pf.current then
                                    Just ( "current", "Enter your current password." )

                                  else
                                    Nothing
                                , if String.length pf.next < 12 then
                                    Just ( "next", "New password must be at least 12 characters." )

                                  else
                                    Nothing
                                , if pf.confirm /= pf.next then
                                    Just ( "confirm", "Passwords don't match." )

                                  else
                                    Nothing
                                ]
                    in
                    if not (List.isEmpty errs) then
                        ( { model | passwordForm = { pf | errors = errs } }, Cmd.none )

                    else
                        ( { model
                            | passwordForm =
                                { pf
                                    | submitting = True
                                    , errors = []
                                    , success = Nothing
                                }
                          }
                        , Api.changePassword token pf.current pf.next GotChangedPassword
                        )

                Nothing ->
                    ( model, Cmd.none )

        GotChangedPassword result ->
            let
                pf =
                    model.passwordForm
            in
            case result of
                Ok _ ->
                    let
                        ( signedOut, command ) =
                            Update.Auth.update LoggedOut model
                    in
                    ( { signedOut | alert = Just { kind = AlertSuccess, message = "Password changed. Sign in with your new password." } }, command )

                Err message ->
                    ( { model
                        | passwordForm =
                            { pf
                                | submitting = False
                                , errors = [ ( "form", message ) ]
                            }
                      }
                    , Cmd.none
                    )

        RequestedLogoutAll ->
            ( { model | logoutAllConfirm = True }, Cmd.none )

        CancelledLogoutAll ->
            ( { model | logoutAllConfirm = False }, Cmd.none )

        ConfirmedLogoutAll ->
            case model.token of
                Just token ->
                    ( { model | logoutAllConfirm = False }
                    , Api.logoutAll token GotLogoutAll
                    )

                Nothing ->
                    ( { model | logoutAllConfirm = False }, Cmd.none )

        GotLogoutAll result ->
            case result of
                Ok _ ->
                    ( { model
                        | token = Nothing
                        , user = Nothing
                        , mode = Login
                        , route = Home
                        , contacts = NotAsked
                        , deals = NotAsked
                        , activities = NotAsked
                        , schools = NotAsked
                        , students = NotAsked
                        , agents = NotAsked
                        , leads = NotAsked
                        , toast = Nothing
                        , alert =
                            Just
                                { kind = AlertSuccess
                                , message = "Signed out of all devices."
                                }
                      }
                    , storeToken Nothing
                    )

                Err message ->
                    ( { model | toast = Just ("Sign-out failed: " ++ message) }
                    , Cmd.none
                    )

        _ ->
            ( model, Cmd.none )
