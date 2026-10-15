module Update.Cases exposing (update)

{-| Case and document messages.
-}

import Api
import Types exposing (..)
import Update.Loaders exposing (loadCases, pageSize)
import Update.Navigation
import Update.Validate exposing (validateCaseForm)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotCases result ->
            case result of
                Ok ( items, total ) ->
                    let
                        prev =
                            case model.cases of
                                Success d ->
                                    d

                                _ ->
                                    { items = [], query = "", stageFilter = "", total = 0, offset = 0, limit = pageSize }
                    in
                    ( { model
                        | cases =
                            Success
                                { items = items
                                , query = prev.query
                                , stageFilter = prev.stageFilter
                                , total = total
                                , offset = prev.offset
                                , limit = pageSize
                                }
                      }
                    , Cmd.none
                    )

                Err message ->
                    ( { model | cases = Failure message }, Cmd.none )

        UpdatedCasesQuery q ->
            let
                next =
                    case model.cases of
                        Success data ->
                            Success { data | query = q, offset = 0 }

                        _ ->
                            Success { items = [], query = q, stageFilter = "", total = 0, offset = 0, limit = pageSize }
            in
            ( { model | cases = next, pendingCasesQuery = Just q }, Cmd.none )

        UpdatedCasesStageFilter stage ->
            case model.token of
                Just t ->
                    let
                        ( q, next ) =
                            case model.cases of
                                Success data ->
                                    ( data.query, Success { data | stageFilter = stage, offset = 0 } )

                                _ ->
                                    ( "", Success { items = [], query = "", stageFilter = stage, total = 0, offset = 0, limit = pageSize } )
                    in
                    ( { model | cases = next }
                    , Api.fetchCases t q stage pageSize 0 GotCases
                    )

                Nothing ->
                    ( model, Cmd.none )

        FlushCasesSearch ->
            case ( model.token, model.pendingCasesQuery ) of
                ( Just t, Just q ) ->
                    let
                        stage =
                            case model.cases of
                                Success d ->
                                    d.stageFilter

                                _ ->
                                    ""
                    in
                    ( { model | pendingCasesQuery = Nothing }
                    , Api.fetchCases t q stage pageSize 0 GotCases
                    )

                _ ->
                    ( { model | pendingCasesQuery = Nothing }, Cmd.none )

        CasesPageChanged newOffset ->
            case ( model.token, model.cases ) of
                ( Just t, Success data ) ->
                    ( { model | cases = Success { data | offset = newOffset } }
                    , Api.fetchCases t data.query data.stageFilter pageSize newOffset GotCases
                    )

                _ ->
                    ( model, Cmd.none )

        OpenedAddCase ->
            ( { model | caseForm = Just emptyCaseForm, editingCaseId = Nothing, toast = Nothing }, Cmd.none )

        OpenedAddCaseForStudent student ->
            ( { model
                | caseForm = Just { emptyCaseForm | studentId = student.id }
                , editingCaseId = Nothing
                , viewingStudent = Just student
                , toast = Nothing
              }
            , Cmd.none
            )

        OpenedEditCase c ->
            ( { model | caseForm = Just (caseToForm c), editingCaseId = Just c.id, toast = Nothing }, Cmd.none )

        OpenedCaseDetail c ->
            Update.Navigation.update (NavigatedTo (CaseDetail c.id))
                { model | viewingCase = Just c, toast = Nothing }

        RequestedCloseCaseForm ->
            case ( model.caseForm, model.deletingCase ) of
                ( _, Just _ ) ->
                    ( { model | deletingCase = Nothing }, Cmd.none )

                ( Just cf, _ ) ->
                    if cf.dirty && not cf.submitting then
                        ( { model | caseForm = Just { cf | confirmDiscard = True } }, Cmd.none )

                    else
                        ( { model | caseForm = Nothing, editingCaseId = Nothing }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ConfirmedCloseCaseForm ->
            ( { model | caseForm = Nothing, editingCaseId = Nothing }, Cmd.none )

        CancelledCloseCaseForm ->
            case model.caseForm of
                Just cf ->
                    ( { model | caseForm = Just { cf | confirmDiscard = False } }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        UpdatedCaseFormField field value ->
            case model.caseForm of
                Just cf ->
                    let
                        updated =
                            case field of
                                "caseNumber" ->
                                    { cf | caseNumber = value }

                                "clientId" ->
                                    { cf | clientId = value }

                                "studentId" ->
                                    { cf | studentId = value }

                                "serviceCategory" ->
                                    { cf | serviceCategory = value }

                                "destinationCountry" ->
                                    { cf | destinationCountry = value }

                                "visaType" ->
                                    { cf | visaType = value }

                                "schoolOrEmployer" ->
                                    { cf | schoolOrEmployer = value }

                                "assignedOfficer" ->
                                    { cf | assignedOfficer = value }

                                "externalAdviser" ->
                                    { cf | externalAdviser = value }

                                "dateOpened" ->
                                    { cf | dateOpened = value }

                                "targetSubmission" ->
                                    { cf | targetSubmission = value }

                                "actualSubmission" ->
                                    { cf | actualSubmission = value }

                                "governmentRef" ->
                                    { cf | governmentRef = value }

                                "currentStage" ->
                                    { cf | currentStage = value }

                                "priority" ->
                                    { cf | priority = value }

                                "nextAction" ->
                                    { cf | nextAction = value }

                                "nextDeadline" ->
                                    { cf | nextDeadline = value }

                                "result" ->
                                    { cf | result = value }

                                "closureDate" ->
                                    { cf | closureDate = value }

                                "notes" ->
                                    { cf | notes = value }

                                _ ->
                                    cf
                    in
                    ( { model
                        | caseForm =
                            Just
                                { updated
                                    | dirty = True
                                    , errors = List.filter (\( f, _ ) -> f /= field) updated.errors
                                }
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        SubmittedCaseForm ->
            case ( model.caseForm, model.token ) of
                ( Just cf, Just token ) ->
                    let
                        ( validated, ok ) =
                            validateCaseForm cf
                    in
                    if not ok then
                        ( { model | caseForm = Just validated }, Cmd.none )

                    else
                        let
                            cmd =
                                case model.editingCaseId of
                                    Just id ->
                                        Api.updateCase token id validated GotSavedCase

                                    Nothing ->
                                        Api.createCase token validated GotSavedCase
                        in
                        ( { model | caseForm = Just { validated | submitting = True } }, cmd )

                _ ->
                    ( model, Cmd.none )

        GotSavedCase result ->
            case result of
                Ok c ->
                    let
                        verb =
                            if model.editingCaseId /= Nothing then
                                "Updated "

                            else
                                "Added "

                        fresh =
                            { model
                                | caseForm = Nothing
                                , editingCaseId = Nothing
                                , viewingCase =
                                    case model.route of
                                        CaseDetail id ->
                                            if id == c.id then
                                                Just c

                                            else
                                                model.viewingCase

                                        _ ->
                                            model.viewingCase
                                , toast = Just (verb ++ c.caseNumber)
                            }
                    in
                    ( fresh, Tuple.second (loadCases fresh) )

                Err (FieldErrors fields) ->
                    case model.caseForm of
                        Just cf ->
                            ( { model | caseForm = Just { cf | submitting = False, errors = fields } }, Cmd.none )

                        Nothing ->
                            ( model, Cmd.none )

                Err (GenericError message) ->
                    case model.caseForm of
                        Just cf ->
                            ( { model
                                | caseForm =
                                    Just { cf | submitting = False, errors = [ ( "form", message ) ] }
                              }
                            , Cmd.none
                            )

                        Nothing ->
                            ( model, Cmd.none )

        RequestedDeleteCase c ->
            ( { model | deletingCase = Just c }, Cmd.none )

        CancelledDeleteCase ->
            ( { model | deletingCase = Nothing }, Cmd.none )

        ConfirmedDeleteCase ->
            case ( model.deletingCase, model.token ) of
                ( Just c, Just token ) ->
                    ( model, Api.deleteCase token c.id (GotDeletedCase c.id c.caseNumber) )

                _ ->
                    ( model, Cmd.none )

        GotDeletedCase deletedId name result ->
            case result of
                Ok _ ->
                    let
                        fresh =
                            { model
                                | deletingCase = Nothing
                                , viewingCase =
                                    case model.route of
                                        CaseDetail id ->
                                            if id == deletedId then
                                                Nothing

                                            else
                                                model.viewingCase

                                        _ ->
                                            model.viewingCase
                                , caseDocuments =
                                    if model.route == CaseDetail deletedId then
                                        NotAsked

                                    else
                                        model.caseDocuments
                                , route =
                                    case model.route of
                                        CaseDetail id ->
                                            if id == deletedId then
                                                Cases

                                            else
                                                model.route

                                        _ ->
                                            model.route
                                , toast = Just ("Deleted " ++ name)
                            }
                    in
                    ( fresh, Tuple.second (loadCases fresh) )

                Err message ->
                    ( { model
                        | deletingCase = Nothing
                        , toast = Just ("Delete failed: " ++ message)
                      }
                    , Cmd.none
                    )

        GotCaseDocuments result ->
            case result of
                Ok docs ->
                    ( { model | caseDocuments = Success docs }, Cmd.none )

                Err message ->
                    ( { model | caseDocuments = Failure message }, Cmd.none )

        OpenedAddDocument ->
            ( { model | documentForm = Just emptyDocumentForm, editingDocumentId = Nothing, toast = Nothing }, Cmd.none )

        OpenedEditDocument d ->
            ( { model | documentForm = Just (documentToForm d), editingDocumentId = Just d.id, toast = Nothing }, Cmd.none )

        RequestedCloseDocumentForm ->
            case ( model.documentForm, model.deletingDocument ) of
                ( _, Just _ ) ->
                    ( { model | deletingDocument = Nothing }, Cmd.none )

                ( Just df, _ ) ->
                    if df.dirty && not df.submitting then
                        ( { model | documentForm = Just { df | confirmDiscard = True } }, Cmd.none )

                    else
                        ( { model | documentForm = Nothing, editingDocumentId = Nothing }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ConfirmedCloseDocumentForm ->
            ( { model | documentForm = Nothing, editingDocumentId = Nothing }, Cmd.none )

        CancelledCloseDocumentForm ->
            case model.documentForm of
                Just df ->
                    ( { model | documentForm = Just { df | confirmDiscard = False } }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        UpdatedDocumentFormField field value ->
            case model.documentForm of
                Just df ->
                    let
                        updated =
                            case field of
                                "docName" ->
                                    { df | docName = value }

                                "dateRequested" ->
                                    { df | dateRequested = value }

                                "dateReceived" ->
                                    { df | dateReceived = value }

                                "expiryDate" ->
                                    { df | expiryDate = value }

                                "verifiedBy" ->
                                    { df | verifiedBy = value }

                                "verificationDate" ->
                                    { df | verificationDate = value }

                                "status" ->
                                    { df | status = value }

                                "rejectionReason" ->
                                    { df | rejectionReason = value }

                                "filePath" ->
                                    { df | filePath = value }

                                "notes" ->
                                    { df | notes = value }

                                _ ->
                                    df
                    in
                    ( { model
                        | documentForm =
                            Just
                                { updated
                                    | dirty = True
                                    , errors = List.filter (\( f, _ ) -> f /= field) updated.errors
                                }
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        ToggledDocumentBool field value ->
            case model.documentForm of
                Just df ->
                    let
                        updated =
                            case field of
                                "required" ->
                                    { df | required = value }

                                "translationRequired" ->
                                    { df | translationRequired = value }

                                "legalizationRequired" ->
                                    { df | legalizationRequired = value }

                                _ ->
                                    df
                    in
                    ( { model | documentForm = Just { updated | dirty = True } }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        SubmittedDocumentForm ->
            case ( model.documentForm, model.token, model.viewingCase ) of
                ( Just df, Just token, Just c ) ->
                    if String.isEmpty (String.trim df.docName) then
                        ( { model
                            | documentForm =
                                Just { df | errors = [ ( "docName", "Document name is required." ) ] }
                          }
                        , Cmd.none
                        )

                    else
                        let
                            cmd =
                                case model.editingDocumentId of
                                    Just id ->
                                        Api.updateDocument token c.id id df GotSavedDocument

                                    Nothing ->
                                        Api.createDocument token c.id df GotSavedDocument
                        in
                        ( { model | documentForm = Just { df | submitting = True, errors = [] } }, cmd )

                _ ->
                    ( model, Cmd.none )

        GotSavedDocument result ->
            case result of
                Ok d ->
                    let
                        verb =
                            if model.editingDocumentId /= Nothing then
                                "Updated "

                            else
                                "Added "

                        fresh =
                            { model
                                | documentForm = Nothing
                                , editingDocumentId = Nothing
                                , toast = Just (verb ++ d.docName)
                            }
                    in
                    ( fresh, refreshDocuments fresh )

                Err (FieldErrors fields) ->
                    case model.documentForm of
                        Just df ->
                            ( { model | documentForm = Just { df | submitting = False, errors = fields } }, Cmd.none )

                        Nothing ->
                            ( model, Cmd.none )

                Err (GenericError message) ->
                    case model.documentForm of
                        Just df ->
                            ( { model
                                | documentForm =
                                    Just { df | submitting = False, errors = [ ( "form", message ) ] }
                              }
                            , Cmd.none
                            )

                        Nothing ->
                            ( model, Cmd.none )

        RequestedDeleteDocument d ->
            ( { model | deletingDocument = Just d }, Cmd.none )

        CancelledDeleteDocument ->
            ( { model | deletingDocument = Nothing }, Cmd.none )

        ConfirmedDeleteDocument ->
            case ( model.deletingDocument, model.token ) of
                ( Just d, Just token ) ->
                    ( model, Api.deleteDocument token d.id GotDeletedDocument )

                _ ->
                    ( model, Cmd.none )

        GotDeletedDocument result ->
            case result of
                Ok _ ->
                    let
                        fresh =
                            { model | deletingDocument = Nothing, toast = Just "Document deleted" }
                    in
                    ( fresh, refreshDocuments fresh )

                Err message ->
                    ( { model
                        | deletingDocument = Nothing
                        , toast = Just ("Delete failed: " ++ message)
                      }
                    , Cmd.none
                    )

        UpdatedDocumentStatus d newStatus ->
            case model.token of
                Just token ->
                    ( model, Api.updateDocumentStatus token d.id newStatus GotUpdatedDocument )

                Nothing ->
                    ( model, Cmd.none )

        GotUpdatedDocument result ->
            case result of
                Ok d ->
                    let
                        fresh =
                            { model | toast = Just (d.docName ++ " → " ++ d.status) }
                    in
                    ( fresh, refreshDocuments fresh )

                Err err ->
                    let
                        message =
                            case err of
                                FieldErrors _ ->
                                    "Could not update document."

                                GenericError m ->
                                    m
                    in
                    ( { model | toast = Just message }, Cmd.none )

        _ ->
            ( model, Cmd.none )


refreshDocuments : Model -> Cmd Msg
refreshDocuments model =
    case ( model.token, model.viewingCase ) of
        ( Just t, Just c ) ->
            Api.fetchCaseDocuments t c.id GotCaseDocuments

        _ ->
            Cmd.none
