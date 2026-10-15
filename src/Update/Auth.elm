module Update.Auth exposing (update)

{-| Login, session and logout messages.
-}

import Api
import Browser.Navigation as Nav
import Ports exposing (storeToken)
import Set
import Types exposing (..)
import Update.Navigation
import Update.Validate exposing (validate)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        RetryLogout ->
            if model.logoutBusy then ( model, Cmd.none )
            else ( { model | logoutPending = True, logoutBusy = True, logoutMessage = "" }, Ports.logoutSession () )

        LogoutFinished result ->
            if not model.logoutPending then ( model, Cmd.none )
            else ( { model | logoutPending = not result.ok, logoutBusy = False, logoutMessage = result.message }, Cmd.none )

        RefreshSession ->
            if model.token == Nothing then
                ( model, Cmd.none )
            else
                let generation = model.sessionGeneration + 1 in
                ( { model | bootstrapping = model.user == Nothing, alert = Nothing, sessionGeneration = generation }, Api.refreshSession (RefreshedSession generation) )

        RefreshedSession generation result ->
            if generation /= model.sessionGeneration then
                ( model, Cmd.none )
            else case result of
                Ok response ->
                    if model.sessionOwner /= Nothing && model.sessionOwner /= Just response.user.id then
                        -- Start a fresh document so old API replies, JS caches and
                        -- forms cannot cross the account boundary.
                        ( { model | user = Nothing, bootstrapping = True, sessionGeneration = model.sessionGeneration + 1 }, Nav.load "/" )
                    else if model.bootstrapping then
                        update (GotUser (Ok response.user)) { model | token = Just response.token }

                    else
                        ( { model | token = Just response.token, user = Just response.user }, Cmd.none )

                Err SessionRejected ->
                    update (GotUser (Err "Your session expired. Please sign in again.")) model

                Err (SessionUnavailable message) ->
                    ( { model | bootstrapping = False, alert = Just { kind = AlertError, message = message }, toast = if model.user == Nothing then model.toast else Just message }, Cmd.none )

        UpdatedOTP value ->
            ( { model | form = (\f -> { f | otp = value }) model.form }, Cmd.none )

        UpdatedField field value ->
            let
                current =
                    model.form

                newForm =
                    case field of
                        NameField ->
                            { current | name = value }

                        EmailField ->
                            { current | email = value }

                        PasswordField ->
                            { current | password = value }
            in
            ( { model
                | form = newForm
                , errors = List.filter (\( f, _ ) -> f /= field) model.errors
              }
            , Cmd.none
            )

        ToggledRemember value ->
            ( { model | form = (\f -> { f | remember = value }) model.form }, Cmd.none )

        ToggledShowPassword ->
            ( { model | showPassword = not model.showPassword }, Cmd.none )

        SwitchedMode newMode ->
            ( { model
                | mode = newMode
                , form = emptyForm
                , errors = []
                , alert = Nothing
              }
            , Cmd.none
            )

        Submitted ->
            let
                errs =
                    validate model.form model.mode
            in
            if not (List.isEmpty errs) then
                ( { model | errors = errs }, Cmd.none )

            else
                let
                    cmd =
                        case model.mode of
                            Login ->
                                Api.login model.form.email model.form.password model.form.otp model.form.remember GotAuth

                            Register ->
                                Api.register model.form.name model.form.email model.form.password GotAuth
                in
                ( { model
                    | submitting = True
                    , errors = []
                    , alert = Nothing
                  }
                , cmd
                )

        GotAuth result ->
            case result of
                Ok { token, user } ->
                    let
                        storeCmd =
                            Cmd.batch [ storeToken (Just token), Ports.sessionIdentity user.id ]

                        recovering = model.sessionOwner == Just user.id && model.user == Nothing
                        changedAccount = model.sessionOwner /= Nothing && model.sessionOwner /= Just user.id
                        modelWithAuth =
                            { model
                                | submitting = False
                                , sessionGeneration = model.sessionGeneration + 1
                                , sessionOwner = Just user.id
                                , form = emptyForm
                                , token = Just token
                                , user = Just user
                                , route = model.route
                                , reports = NotAsked
                                , globalQuery = ""
                                , globalResults = NotAsked
                                , audit = NotAsked
                                , auditOffset = 0
                                , exporting = Nothing
                                , contacts = NotAsked
                                , deals = NotAsked
                                , cases = NotAsked
                                , invoices = NotAsked
                                , partners = NotAsked
                                , toast = Nothing
                                , alert =
                                    Just
                                        { kind = AlertSuccess
                                        , message = "Welcome, " ++ user.name ++ "!"
                                        }
                            }

                        ( routedModel, routeCmds ) =
                            if recovering then
                                ( { model | token = Just token, user = Just user, sessionOwner = Just user.id, sessionGeneration = model.sessionGeneration + 1, form = emptyForm, submitting = False, bootstrapping = False, alert = Nothing, toast = Just "Signed in again. Your unsaved entries are restored; review them before saving." }
                                , Update.Navigation.update (NavigatedTo model.route) modelWithAuth |> Tuple.second
                                )
                            else Update.Navigation.update (NavigatedTo model.route) modelWithAuth
                    in
                    if changedAccount then
                        ( { model | user = Nothing, bootstrapping = True, sessionGeneration = model.sessionGeneration + 1 }, Nav.load "/" )
                    else
                        ( routedModel, Cmd.batch [ storeCmd, routeCmds, Api.fetchWorkspaceClock token RefreshedWorkspaceClock ] )

                Err message ->
                    ( { model
                        | submitting = False
                        , alert = Just { kind = AlertError, message = message }
                      }
                    , Cmd.none
                    )

        GotUser result ->
            case result of
                Ok user ->
                    let
                        modelWithUser =
                            { model | user = Just user, sessionOwner = Just user.id, bootstrapping = False }

                        ( routedModel, routeCmds ) =
                            Update.Navigation.update (NavigatedTo model.route) modelWithUser
                    in
                    ( routedModel, Cmd.batch [ Ports.sessionIdentity user.id, routeCmds, Api.fetchWorkspaceClock (Maybe.withDefault "cookie-session" model.token) RefreshedWorkspaceClock ] )

                Err message ->
                    ( { model
                        | sessionGeneration = model.sessionGeneration + 1
                        , token = Nothing
                        , user = Nothing
                        , bootstrapping = False
                        , passwordForm = emptyPasswordForm
                        , leadForm = Maybe.map (\draft -> { draft | duplicateConfirmed = False, submitting = False }) model.leadForm
                        , paymentForm = Maybe.map (\draft -> { draft | confirmDuplicate = False, submitting = False }) model.paymentForm
                        , form = emptyForm
                        , alert = if model.sessionOwner == Nothing then Nothing else Just { kind = AlertError, message = message ++ " Sign in with the same account to recover your unsaved entries." }
                      }
                    , Cmd.batch [ storeToken Nothing, Ports.preserveSessionDrafts (Maybe.withDefault "" model.sessionOwner) ]
                    )

        LoggedOut ->
            ( { model
                | sessionGeneration = model.sessionGeneration + 1
                , sessionOwner = Nothing
                , logoutPending = True
                , logoutBusy = True
                , logoutMessage = ""
                , token = Nothing
                , user = Nothing
                , form = emptyForm
                , mode = Login
                , route = Home
                , reports = NotAsked
                , globalQuery = ""
                , globalResults = NotAsked
                , audit = NotAsked
                , auditOffset = 0
                , exporting = Nothing
                , contacts = NotAsked
                , viewingContact = Nothing
                , contactForm = Nothing
                , editingId = Nothing
                , deletingContact = Nothing
                , alert = Nothing
                , toast = Nothing
                , bootstrapping = False
                , deals = NotAsked
                , viewingDeal = Nothing
                , dealForm = Nothing
                , editingDealId = Nothing
                , deletingDeal = Nothing
                , movingDealId = Nothing
                , draggingDealId = Nothing
                , dropTargetStage = Nothing
                , selectedDeals = Set.empty
                , ownerFilter = ""
                , dateFromFilter = ""
                , dateToFilter = ""
                , bulkMoveStage = Nothing
                , bulkDeleteConfirm = False
                , activities = NotAsked
                , activityForm = Nothing
                , deletingActivity = Nothing
                , tasks = NotAsked
                , taskForm = Nothing
                , editingTaskId = Nothing
                , deletingTask = Nothing
                , pendingContactsQuery = Nothing
                , dealsRequestId = model.dealsRequestId + 1
                , pendingDealsQuery = Nothing
                , pendingTasksQuery = Nothing
                , profileForm = emptyProfileForm
                , passwordForm = emptyPasswordForm
                , logoutAllConfirm = False
                , schools = NotAsked
                , viewingSchool = Nothing
                , schoolForm = Nothing
                , editingSchoolId = Nothing
                , deletingSchool = Nothing
                , pendingSchoolsQuery = Nothing
                , students = NotAsked
                , linkedStudents = NotAsked
                , viewingStudent = Nothing
                , studentDossier = NotAsked
                , studentForm = Nothing
                , editingStudentId = Nothing
                , deletingStudent = Nothing
                , pendingStudentsQuery = Nothing
                , agents = NotAsked
                , viewingAgent = Nothing
                , agentForm = Nothing
                , editingAgentId = Nothing
                , deletingAgent = Nothing
                , pendingAgentsQuery = Nothing
                , leads = NotAsked
                , viewingLead = Nothing
                , leadForm = Nothing
                , editingLeadId = Nothing
                , deletingLead = Nothing
                , pendingLeadsQuery = Nothing
                , cases = NotAsked
                , viewingCase = Nothing
                , caseForm = Nothing
                , editingCaseId = Nothing
                , deletingCase = Nothing
                , pendingCasesQuery = Nothing
                , caseDocuments = NotAsked
                , documentForm = Nothing
                , editingDocumentId = Nothing
                , deletingDocument = Nothing
                , invoices = NotAsked
                , viewingInvoice = Nothing
                , invoiceForm = Nothing
                , editingInvoiceId = Nothing
                , deletingInvoice = Nothing
                , pendingInvoicesQuery = Nothing
                , invoicePayments = NotAsked
                , paymentForm = Nothing
                , deletingPayment = Nothing
                , refundConfirmInvoice = Nothing
                , partners = NotAsked
                , viewingPartner = Nothing
                , partnerForm = Nothing
                , editingPartnerId = Nothing
                , deletingPartner = Nothing
                , pendingPartnersQuery = Nothing
              }
            , Cmd.batch [ storeToken Nothing, Ports.logoutSession () ]
            )

        _ ->
            ( model, Cmd.none )
