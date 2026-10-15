module Update.Schools exposing (update)

{-| School messages.
-}

import Api
import Types exposing (..)
import Update.Loaders exposing (loadSchools, loadStudents, pageSize)
import Update.Navigation
import Update.Validate exposing (validateSchoolForm)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotSchools result ->
            case result of
                Ok ( items, total ) ->
                    let
                        prev =
                            case model.schools of
                                Success d ->
                                    d

                                _ ->
                                    { items = [], query = "", total = 0, offset = 0, limit = pageSize }
                    in
                    ( { model
                        | schools =
                            Success
                                { items = items
                                , query = prev.query
                                , total = total
                                , offset = prev.offset
                                , limit = pageSize
                                }
                      }
                    , Cmd.none
                    )

                Err message ->
                    ( { model | schools = Failure message }, Cmd.none )

        UpdatedSchoolsQuery q ->
            let
                next =
                    case model.schools of
                        Success data ->
                            Success { data | query = q, offset = 0 }

                        _ ->
                            Success { items = [], query = q, total = 0, offset = 0, limit = pageSize }
            in
            ( { model | schools = next, pendingSchoolsQuery = Just q }, Cmd.none )

        FlushSchoolsSearch ->
            case ( model.token, model.pendingSchoolsQuery ) of
                ( Just t, Just q ) ->
                    ( { model | pendingSchoolsQuery = Nothing }
                    , Api.fetchSchools t q pageSize 0 GotSchools
                    )

                _ ->
                    ( { model | pendingSchoolsQuery = Nothing }, Cmd.none )

        SchoolsPageChanged newOffset ->
            case ( model.token, model.schools ) of
                ( Just t, Success data ) ->
                    ( { model | schools = Success { data | offset = newOffset } }
                    , Api.fetchSchools t data.query pageSize newOffset GotSchools
                    )

                _ ->
                    ( model, Cmd.none )

        OpenedAddSchool ->
            ( { model
                | schoolForm = Just emptySchoolForm
                , editingSchoolId = Nothing
                , toast = Nothing
              }
            , Cmd.none
            )

        OpenedEditSchool school ->
            ( { model
                | schoolForm = Just (schoolToForm school)
                , editingSchoolId = Just school.id
                , toast = Nothing
              }
            , Cmd.none
            )

        OpenedSchoolDetail school ->
            Update.Navigation.update (NavigatedTo (SchoolDetail school.id))
                { model | viewingSchool = Just school, toast = Nothing }

        RequestedCloseSchoolForm ->
            case ( model.schoolForm, model.deletingSchool ) of
                ( _, Just _ ) ->
                    ( { model | deletingSchool = Nothing }, Cmd.none )

                ( Just sf, _ ) ->
                    if sf.dirty && not sf.submitting then
                        ( { model | schoolForm = Just { sf | confirmDiscard = True } }, Cmd.none )

                    else
                        ( { model | schoolForm = Nothing, editingSchoolId = Nothing }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ConfirmedCloseSchoolForm ->
            ( { model | schoolForm = Nothing, editingSchoolId = Nothing }, Cmd.none )

        CancelledCloseSchoolForm ->
            case model.schoolForm of
                Just sf ->
                    ( { model | schoolForm = Just { sf | confirmDiscard = False } }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        UpdatedSchoolFormField field value ->
            case model.schoolForm of
                Just sf ->
                    let
                        updated =
                            case field of
                                "name" ->
                                    { sf | name = value }

                                "countryCode" ->
                                    { sf | countryCode = value }

                                "commissionRate" ->
                                    { sf | commissionRate = value }

                                "contractStatus" ->
                                    { sf | contractStatus = value }

                                "studentsEnrolled" ->
                                    { sf | studentsEnrolled = value }

                                "contactPerson" ->
                                    { sf | contactPerson = value }

                                "website" ->
                                    { sf | website = value }

                                "notes" ->
                                    { sf | notes = value }

                                _ ->
                                    sf
                    in
                    ( { model
                        | schoolForm =
                            Just
                                { updated
                                    | dirty = True
                                    , errors =
                                        List.filter (\( f, _ ) -> f /= field) updated.errors
                                }
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        SubmittedSchoolForm ->
            case ( model.schoolForm, model.token ) of
                ( Just sf, Just token ) ->
                    let
                        ( validated, ok ) =
                            validateSchoolForm sf
                    in
                    if not ok then
                        ( { model | schoolForm = Just validated }, Cmd.none )

                    else
                        let
                            cmd =
                                case model.editingSchoolId of
                                    Just id ->
                                        Api.updateSchool token id validated GotSavedSchool

                                    Nothing ->
                                        Api.createSchool token validated GotSavedSchool
                        in
                        ( { model | schoolForm = Just { validated | submitting = True } }, cmd )

                _ ->
                    ( model, Cmd.none )

        GotSavedSchool result ->
            case result of
                Ok school ->
                    let
                        verb =
                            if model.editingSchoolId /= Nothing then
                                "Updated "

                            else
                                "Added "

                        fresh =
                            { model
                                | schoolForm = Nothing
                                , editingSchoolId = Nothing
                                , viewingSchool =
                                    case model.route of
                                        SchoolDetail id ->
                                            if id == school.id then
                                                Just school

                                            else
                                                model.viewingSchool

                                        _ ->
                                            model.viewingSchool
                                , toast = Just (verb ++ school.name)
                            }
                    in
                    ( fresh, Tuple.second (loadSchools fresh) )

                Err (FieldErrors fields) ->
                    case model.schoolForm of
                        Just sf ->
                            ( { model | schoolForm = Just { sf | submitting = False, errors = fields } }, Cmd.none )

                        Nothing ->
                            ( model, Cmd.none )

                Err (GenericError message) ->
                    case model.schoolForm of
                        Just sf ->
                            ( { model
                                | schoolForm =
                                    Just { sf | submitting = False, errors = [ ( "form", message ) ] }
                              }
                            , Cmd.none
                            )

                        Nothing ->
                            ( model, Cmd.none )

        RequestedDeleteSchool school ->
            ( { model | deletingSchool = Just school }, Cmd.none )

        CancelledDeleteSchool ->
            ( { model | deletingSchool = Nothing }, Cmd.none )

        ConfirmedDeleteSchool ->
            case ( model.deletingSchool, model.token ) of
                ( Just school, Just token ) ->
                    ( model, Api.deleteSchool token school.id (GotDeletedSchool school.id school.name) )

                _ ->
                    ( model, Cmd.none )

        GotDeletedSchool deletedId name result ->
            case result of
                Ok _ ->
                    let
                        fresh =
                            { model
                                | deletingSchool = Nothing
                                , viewingSchool =
                                    case model.route of
                                        SchoolDetail id ->
                                            if id == deletedId then
                                                Nothing

                                            else
                                                model.viewingSchool

                                        _ ->
                                            model.viewingSchool
                                , route =
                                    case model.route of
                                        SchoolDetail id ->
                                            if id == deletedId then
                                                Schools

                                            else
                                                model.route

                                        _ ->
                                            model.route
                                , toast = Just ("Deleted " ++ name)
                            }
                    in
                    ( fresh
                    , Cmd.batch
                        [ Tuple.second (loadSchools fresh)
                        , Tuple.second (loadStudents fresh)
                        ]
                    )

                Err message ->
                    ( { model
                        | deletingSchool = Nothing
                        , toast = Just ("Delete failed: " ++ message)
                      }
                    , Cmd.none
                    )

        _ ->
            ( model, Cmd.none )
