module Update.Students exposing (update)

{-| Student messages.
-}

import Api
import Types exposing (..)
import Update.Loaders exposing (loadAgents, loadSchools, loadStudents, pageSize)
import Update.Navigation
import Update.Validate exposing (validateStudentForm)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotStudents result ->
            case result of
                Ok ( items, total ) ->
                    let
                        prev =
                            case model.students of
                                Success d ->
                                    d

                                _ ->
                                    { items = [], query = "", total = 0, offset = 0, limit = pageSize }
                    in
                    ( { model
                        | students =
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
                    ( { model | students = Failure message }, Cmd.none )

        GotLinkedStudents parentId result ->
            if not (isCurrentLinkedStudentsRoute model.route parentId) then
                ( model, Cmd.none )

            else
                case result of
                    Ok ( items, total ) ->
                        ( { model | linkedStudents = Success { parentId = parentId, items = items, total = total } }, Cmd.none )

                    Err message ->
                        ( { model | linkedStudents = Failure message }, Cmd.none )

        GotStudentDossier result ->
            case result of
                Ok dossier ->
                    ( { model | studentDossier = Success dossier }, Cmd.none )

                Err message ->
                    ( { model | studentDossier = Failure message }, Cmd.none )

        UpdatedStudentsQuery q ->
            let
                next =
                    case model.students of
                        Success data ->
                            Success { data | query = q, offset = 0 }

                        _ ->
                            Success { items = [], query = q, total = 0, offset = 0, limit = pageSize }
            in
            ( { model | students = next, pendingStudentsQuery = Just q }, Cmd.none )

        FlushStudentsSearch ->
            case ( model.token, model.pendingStudentsQuery ) of
                ( Just t, Just q ) ->
                    ( { model | pendingStudentsQuery = Nothing }
                    , Api.fetchStudents t q pageSize 0 GotStudents
                    )

                _ ->
                    ( { model | pendingStudentsQuery = Nothing }, Cmd.none )

        StudentsPageChanged newOffset ->
            case ( model.token, model.students ) of
                ( Just t, Success data ) ->
                    ( { model | students = Success { data | offset = newOffset } }
                    , Api.fetchStudents t data.query pageSize newOffset GotStudents
                    )

                _ ->
                    ( model, Cmd.none )

        OpenedAddStudent ->
            ( { model
                | studentForm = Just emptyStudentForm
                , editingStudentId = Nothing
                , toast = Nothing
              }
            , Cmd.none
            )

        OpenedAddStudentForAgent agent ->
            ( { model
                | studentForm = Just { emptyStudentForm | agentId = agent.id }
                , editingStudentId = Nothing
                , toast = Nothing
              }
            , Cmd.none
            )

        OpenedAddStudentForSchool school ->
            ( { model
                | studentForm = Just { emptyStudentForm | schoolId = school.id }
                , editingStudentId = Nothing
                , toast = Nothing
              }
            , Cmd.none
            )

        OpenedEditStudent student ->
            ( { model
                | studentForm = Just (studentToForm student)
                , editingStudentId = Just student.id
                , toast = Nothing
              }
            , Cmd.none
            )

        OpenedStudentDetail student ->
            Update.Navigation.update (NavigatedTo (StudentDetail student.id))
                { model | viewingStudent = Just student, toast = Nothing }

        RequestedCloseStudentForm ->
            case ( model.studentForm, model.deletingStudent ) of
                ( _, Just _ ) ->
                    ( { model | deletingStudent = Nothing }, Cmd.none )

                ( Just sf, _ ) ->
                    if sf.dirty && not sf.submitting then
                        ( { model | studentForm = Just { sf | confirmDiscard = True } }, Cmd.none )

                    else
                        ( { model | studentForm = Nothing, editingStudentId = Nothing }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ConfirmedCloseStudentForm ->
            ( { model | studentForm = Nothing, editingStudentId = Nothing }, Cmd.none )

        CancelledCloseStudentForm ->
            case model.studentForm of
                Just sf ->
                    ( { model | studentForm = Just { sf | confirmDiscard = False } }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        UpdatedStudentFormField field value ->
            case model.studentForm of
                Just sf ->
                    let
                        updated =
                            case field of
                                "name" ->
                                    { sf | name = value }

                                "studentCode" ->
                                    { sf | studentCode = value }

                                "countryCode" ->
                                    { sf | countryCode = value }

                                "schoolId" ->
                                    { sf | schoolId = value }

                                "agentId" ->
                                    { sf | agentId = value }

                                "program" ->
                                    { sf | program = value }

                                "acceptanceStatus" ->
                                    { sf | acceptanceStatus = value }

                                "visaStatus" ->
                                    { sf | visaStatus = value }

                                "invoiceStatus" ->
                                    { sf | invoiceStatus = value }

                                "notes" ->
                                    { sf | notes = value }

                                _ ->
                                    sf
                    in
                    ( { model
                        | studentForm =
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

        SubmittedStudentForm ->
            case ( model.studentForm, model.token ) of
                ( Just sf, Just token ) ->
                    let
                        ( validated, ok ) =
                            validateStudentForm sf
                    in
                    if not ok then
                        ( { model | studentForm = Just validated }, Cmd.none )

                    else
                        let
                            cmd =
                                case model.editingStudentId of
                                    Just id ->
                                        Api.updateStudent token id validated GotSavedStudent

                                    Nothing ->
                                        Api.createStudent token validated GotSavedStudent
                        in
                        ( { model | studentForm = Just { validated | submitting = True } }, cmd )

                _ ->
                    ( model, Cmd.none )

        GotSavedStudent result ->
            case result of
                Ok student ->
                    let
                        verb =
                            if model.editingStudentId /= Nothing then
                                "Updated "

                            else
                                "Added "

                        fresh =
                            { model
                                | studentForm = Nothing
                                , editingStudentId = Nothing
                                , viewingStudent =
                                    case model.route of
                                        StudentDetail id ->
                                            if id == student.id then
                                                Just student

                                            else
                                                model.viewingStudent

                                        _ ->
                                            model.viewingStudent
                                , toast = Just (verb ++ student.name)
                                , linkedStudents = Loading
                            }
                    in
                    ( fresh
                    , Cmd.batch
                        (Tuple.second (loadStudents fresh)
                            :: linkedStudentsRefresh model
                            :: relatedCountRefresh fresh
                        )
                    )

                Err (FieldErrors fields) ->
                    case model.studentForm of
                        Just sf ->
                            ( { model | studentForm = Just { sf | submitting = False, errors = fields } }, Cmd.none )

                        Nothing ->
                            ( model, Cmd.none )

                Err (GenericError message) ->
                    case model.studentForm of
                        Just sf ->
                            ( { model
                                | studentForm =
                                    Just { sf | submitting = False, errors = [ ( "form", message ) ] }
                              }
                            , Cmd.none
                            )

                        Nothing ->
                            ( model, Cmd.none )

        RequestedDeleteStudent student ->
            ( { model | deletingStudent = Just student }, Cmd.none )

        CancelledDeleteStudent ->
            ( { model | deletingStudent = Nothing }, Cmd.none )

        ConfirmedDeleteStudent ->
            case ( model.deletingStudent, model.token ) of
                ( Just student, Just token ) ->
                    ( model, Api.deleteStudent token student.id (GotDeletedStudent student.id student.name) )

                _ ->
                    ( model, Cmd.none )

        GotDeletedStudent deletedId name result ->
            case result of
                Ok _ ->
                    let
                        fresh =
                            { model
                                | deletingStudent = Nothing
                                , viewingStudent =
                                    case model.route of
                                        StudentDetail id ->
                                            if id == deletedId then
                                                Nothing

                                            else
                                                model.viewingStudent

                                        _ ->
                                            model.viewingStudent
                                , studentDossier =
                                    if model.route == StudentDetail deletedId then
                                        NotAsked

                                    else
                                        model.studentDossier
                                , route =
                                    case model.route of
                                        StudentDetail id ->
                                            if id == deletedId then
                                                Students

                                            else
                                                model.route

                                        _ ->
                                            model.route
                                , toast = Just ("Deleted " ++ name)
                            }
                    in
                    ( fresh, Tuple.second (loadStudents fresh) )

                Err message ->
                    ( { model
                        | deletingStudent = Nothing
                        , toast = Just ("Delete failed: " ++ message)
                      }
                    , Cmd.none
                    )

        _ ->
            ( model, Cmd.none )


linkedStudentsRefresh : Model -> Cmd Msg
linkedStudentsRefresh model =
    case ( model.token, model.route ) of
        ( Just token, AgentDetail id ) ->
            Api.fetchLinkedStudents token "agent" id (GotLinkedStudents id)

        ( Just token, SchoolDetail id ) ->
            Api.fetchLinkedStudents token "school" id (GotLinkedStudents id)

        _ ->
            Cmd.none


relatedCountRefresh : Model -> List (Cmd Msg)
relatedCountRefresh model =
    case model.route of
        AgentDetail _ ->
            [ Tuple.second (loadAgents model) ]

        SchoolDetail _ ->
            [ Tuple.second (loadSchools model) ]

        _ ->
            []


isCurrentLinkedStudentsRoute : Route -> String -> Bool
isCurrentLinkedStudentsRoute route parentId =
    case route of
        AgentDetail id ->
            id == parentId

        SchoolDetail id ->
            id == parentId

        _ ->
            False
