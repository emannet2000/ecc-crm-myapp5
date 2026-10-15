module Main exposing (main)

import Api
import Frontend.RequestOrder as RequestOrder
import Update.RequestOrder as ReadOrder
import Update.SaveOrder as SaveOrder
import Administration
import WorkDashboard
import ManagementReport
import TeamChat
import Browser
import Browser.Events
import Browser.Navigation as Nav
import Html
import Html.Attributes as Attr
import Json.Decode as D
import Ports
import Router exposing (parseRoute, routeToPath)
import Set
import Time
import Types exposing (..)
import Update.Activities
import Update.Agents
import Update.Auth
import Update.Cases
import Update.Contacts
import Update.Deals
import Update.Fetched
import Update.Invoices
import Update.Leads
import Update.Navigation
import Update.Partners
import Update.Schools
import Update.Settings
import Update.Students
import Update.Tasks
import Update.Workspace
import Url
import Views


type alias Flags =
    { token : Maybe String
    , today : String
    , theme : Maybe String
    , logoutPending : Bool
    }


init : Flags -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    let
        route =
            parseRoute url

        model =
            { requests = RequestOrder.init
            , workDashboard = WorkDashboard.init
            , managementReport = ManagementReport.init
            , teamChat = TeamChat.init
            , administration = Administration.init
            , mode = Login
            , theme =
                if flags.theme == Just "dark" then
                    DarkTheme

                else
                    LightTheme
            , reports = NotAsked
            , globalQuery = ""
            , globalResults = NotAsked
            , audit = NotAsked
            , auditOffset = 0
            , exportEntity = "contacts"
            , exporting = Nothing
            , form = emptyForm
            , errors = []
            , alert = Nothing
            , submitting = False
            , token = flags.token
            , user = Nothing
            , showPassword = False
            , bootstrapping = flags.token /= Nothing
            , sessionGeneration = 0
            , sessionOwner = Nothing
            , logoutPending = flags.logoutPending
            , logoutBusy = flags.logoutPending
            , logoutMessage = ""
            , route = route
            , workspaceQuery = Maybe.withDefault "" url.query
            , contacts = NotAsked
            , viewingContact = Nothing
            , contactForm = Nothing
            , editingId = Nothing
            , deletingContact = Nothing
            , toast = Nothing
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
            , unreadNotifications = 0
            , today = flags.today
            , bulkMoveStage = Nothing
            , bulkDeleteConfirm = False
            , activities = NotAsked
            , activityForm = Nothing
            , deletingActivity = Nothing
            , taskOffset = 0
            , tasks = NotAsked
            , taskForm = Nothing
            , editingTaskId = Nothing
            , deletingTask = Nothing
            , pendingContactsQuery = Nothing
            , dealsRequestId = 0
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
            , sidebarOpen = False
            , navKey = key
            }
    in
    if flags.logoutPending then
        ( { model | token = Nothing, bootstrapping = False }, Ports.logoutSession () )
    else case flags.token of
        Just t ->
            ( model, Api.refreshSession (RefreshedSession model.sessionGeneration) )

        Nothing ->
            ( model, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        OrderedRead issued owner reply ->
            case ReadOrder.scope (ReadOrder.unwrap reply) of
                Just key ->
                    if model.user /= Nothing && model.sessionOwner == owner && RequestOrder.current key issued model.requests then
                        update (ReadOrder.unwrap reply) model
                    else
                        ( model, Cmd.none )
                Nothing ->
                    let
                        completion = ReadOrder.unwrap reply
                    in
                    if SaveOrder.sessionReply completion &&
                        (model.user == Nothing || model.sessionOwner /= owner || not (RequestOrder.current "identity" issued model.requests)) then
                        ( model, Cmd.none )
                    else if SaveOrder.bulkCompletion completion && not (RequestOrder.current "deal-selection" issued model.requests) then
                        let
                            ( next, cmd ) = update completion model
                        in
                        ( { next | selectedDeals = model.selectedDeals, movingDealId = model.movingDealId }, cmd )
                    else if SaveOrder.completion completion then
                        if model.user == Nothing || model.sessionOwner /= owner then
                            ( model, Cmd.none )
                        else if RequestOrder.current "form" issued model.requests then
                            update completion model
                        else
                            let
                                ( next, cmd ) = update completion model
                            in
                            ( SaveOrder.preserveForms model next, cmd )
                    else
                        update completion model

        _ ->
            let
                ( next, cmd ) = updateHelp msg model
                navigation = case msg of
                    NavigatedTo _ -> True
                    UrlChanged _ -> True
                    _ -> next.route /= model.route
                boundary = next.user == Nothing && model.user /= Nothing || next.sessionOwner /= model.sessionOwner
                keys =
                    if navigation || boundary then ReadOrder.all
                    else if SaveOrder.boundary msg then "form" :: ReadOrder.affectedFor model.route msg
                    else ReadOrder.affectedFor model.route msg
                identityBoundary =
                    boundary || (model.user == Nothing && next.user /= Nothing) ||
                        (case msg of
                            GotAuth (Ok _) -> True
                            _ -> False
                        )
                protectedKeys =
                    (if identityBoundary then [ "identity" ] else []) ++
                    (if SaveOrder.selectionBoundary msg then [ "deal-selection" ] else []) ++ keys
                requests = RequestOrder.advance protectedKeys next.requests
            in
            ( { next | requests = requests }, Cmd.map (ReadOrder.unwrap >> OrderedRead requests next.sessionOwner) cmd )


updateHelp : Msg -> Model -> ( Model, Cmd Msg )
updateHelp msg model =
    case msg of
        WorkDashboardMsg workMsg ->
            let
                ( workModel, cmd ) = WorkDashboard.update workMsg model.workDashboard
            in
            ( { model | workDashboard = workModel }, Cmd.map WorkDashboardMsg cmd )

        ManagementReportMsg reportMsg ->
            let
                ( reportModel, cmd ) = ManagementReport.update reportMsg model.managementReport
            in
            ( { model | managementReport = reportModel }, Cmd.map ManagementReportMsg cmd )

        TeamChatMsg chatMsg ->
            let
                ( chatModel, cmd ) = TeamChat.update chatMsg model.teamChat
            in
            ( { model | teamChat = chatModel }, Cmd.map TeamChatMsg cmd )

        AdministrationMsg adminMsg ->
            let
                ( adminModel, cmd ) = Administration.update adminMsg model.administration
            in
            if adminModel.signOut then
                let
                    ( next, authCmd ) = Update.Auth.update LoggedOut { model | administration = Administration.init, teamChat = TeamChat.init, managementReport = ManagementReport.clear model.managementReport, workDashboard = WorkDashboard.clear model.workDashboard }
                in
                ( next, Cmd.batch [ authCmd, Ports.protectUnsaved False ] )
            else
                ( { model | administration = adminModel }, Cmd.batch [ Cmd.map AdministrationMsg cmd, Ports.protectUnsaved (Administration.dirty adminModel || adminModel.busy) ] )

        LoggedOut ->
            if model.route == Types.Administration && (Administration.dirty model.administration || model.administration.busy || model.administration.loading) then
                update (AdministrationMsg (Administration.Request Administration.SignOut)) model
            else
                let
                    ( next, authCmd ) = Update.Auth.update LoggedOut { model | administration = Administration.init, teamChat = TeamChat.init, managementReport = ManagementReport.clear model.managementReport, workDashboard = WorkDashboard.clear model.workDashboard }
                in
                ( next, Cmd.batch [ authCmd, Ports.protectUnsaved False ] )

        UrlChanged url ->
            if model.route == Types.Administration && parseRoute url == Types.Administration && (Administration.dirty model.administration || model.administration.busy || model.administration.loading) then
                ( model, Cmd.none )
            else if model.route == Types.Administration && parseRoute url /= Types.Administration && (Administration.dirty model.administration || model.administration.busy || model.administration.loading) then
                let
                    ( next, cmd ) = update (AdministrationMsg (Administration.Request (Administration.Exit (Url.toString url)))) model
                in
                ( next, Cmd.batch [ cmd, Nav.replaceUrl model.navKey "/administration" ] )
            else
                Update.Navigation.update msg model

        RecordsChanged _ ->
            let
                ( next, cmd ) = updateNavigation (NavigatedTo model.route) model
            in
            ( SaveOrder.preserveForms model { next | sidebarOpen = model.sidebarOpen }, cmd )

        NavigatedTo route ->
            if model.route == Types.Administration && route == Types.Administration then
                ( model, Cmd.none )
            else if model.route == Administration && route /= Administration && (Administration.dirty model.administration || model.administration.busy || model.administration.loading) then
                update (AdministrationMsg (Administration.Request (Administration.Exit (routeToPath route)))) model
            else
                updateNavigation msg model

        LinkClicked request ->
            if model.route == Administration && (Administration.dirty model.administration || model.administration.busy || model.administration.loading) then
                case request of
                    Browser.Internal url -> update (AdministrationMsg (Administration.Request (Administration.Exit (Url.toString url)))) model
                    Browser.External path -> update (AdministrationMsg (Administration.Request (Administration.Exit path))) model
            else
                updateNavigation msg model

        ToggledTheme ->
            let
                nextTheme =
                    if model.theme == LightTheme then
                        DarkTheme

                    else
                        LightTheme
            in
            ( { model | theme = nextTheme }
            , Ports.storeTheme
                (if nextTheme == DarkTheme then
                    "dark"

                 else
                    "light"
                )
            )

        GotReports result ->
            ( { model
                | reports =
                    case result of
                        Ok summary ->
                            Success summary

                        Err message ->
                            Failure message
              }
            , Cmd.none
            )

        EscapePressed ->
            if model.globalQuery /= "" then
                Update.Workspace.update ClosedGlobalSearch model

            else if model.sidebarOpen then
                ( { model | sidebarOpen = False }, Cmd.none )

            else if model.logoutAllConfirm then
                ( { model | logoutAllConfirm = False }, Cmd.none )

            else if model.bulkDeleteConfirm then
                ( { model | bulkDeleteConfirm = False }, Cmd.none )

            else if model.bulkMoveStage /= Nothing then
                update CancelledBulkMove model

            else if model.activityForm /= Nothing || model.deletingActivity /= Nothing then
                update RequestedCloseActivityForm model

            else if model.contactForm /= Nothing || model.deletingContact /= Nothing then
                update RequestedCloseContactForm model

            else if model.dealForm /= Nothing || model.deletingDeal /= Nothing then
                update RequestedCloseDealForm model

            else if model.taskForm /= Nothing || model.deletingTask /= Nothing then
                update RequestedCloseTaskForm model

            else if model.schoolForm /= Nothing || model.deletingSchool /= Nothing then
                update RequestedCloseSchoolForm model

            else if model.studentForm /= Nothing || model.deletingStudent /= Nothing then
                update RequestedCloseStudentForm model

            else if model.agentForm /= Nothing || model.deletingAgent /= Nothing then
                update RequestedCloseAgentForm model

            else if model.leadForm /= Nothing || model.deletingLead /= Nothing then
                update RequestedCloseLeadForm model

            else if model.caseForm /= Nothing || model.deletingCase /= Nothing then
                update RequestedCloseCaseForm model

            else if model.documentForm /= Nothing || model.deletingDocument /= Nothing then
                update RequestedCloseDocumentForm model

            else if model.invoiceForm /= Nothing || model.deletingInvoice /= Nothing then
                update RequestedCloseInvoiceForm model

            else if model.paymentForm /= Nothing then
                update ClosedPaymentForm model

            else if model.refundConfirmInvoice /= Nothing then
                update CancelledRefund model

            else if model.partnerForm /= Nothing || model.deletingPartner /= Nothing then
                update RequestedClosePartnerForm model

            else
                ( model, Cmd.none )

        DismissedToast ->
            ( { model | toast = Nothing }, Cmd.none )

        NoOp ->
            ( model, Cmd.none )

        _ ->
            let
                oldRoute =
                    model.route

                ( newModel, newCmds ) =
                    updateDomains msg model

                alreadySynced =
                    case msg of
                        UrlChanged _ ->
                            True

                        _ ->
                            False
            in
            if not alreadySynced && newModel.route /= oldRoute then
                ( newModel
                , Cmd.batch
                    [ newCmds
                    , Nav.pushUrl newModel.navKey (routeToPath newModel.route)
                    ]
                )

            else
                ( newModel, newCmds )


updateNavigation : Msg -> Model -> ( Model, Cmd Msg )
updateNavigation msg model =
    let
        ( next, cmd ) = Update.Navigation.update msg model
    in
    if next.route /= model.route then
        ( next, Cmd.batch [ cmd, Nav.pushUrl next.navKey (routeToPath next.route) ] )
    else
        ( next, cmd )


updateDomains : Msg -> Model -> ( Model, Cmd Msg )
updateDomains msg model =
    List.foldl
        (\handler ( m, cmds ) ->
            let
                ( m2, cmd ) =
                    handler msg m
            in
            ( m2, cmd :: cmds )
        )
        ( model, [] )
        [ Update.Workspace.update
        , Update.Auth.update
        , Update.Navigation.update
        , Update.Contacts.update
        , Update.Deals.update
        , Update.Activities.update
        , Update.Settings.update
        , Update.Tasks.update
        , Update.Schools.update
        , Update.Students.update
        , Update.Agents.update
        , Update.Leads.update
        , Update.Cases.update
        , Update.Invoices.update
        , Update.Partners.update
        , Update.Fetched.update
        ]
        |> Tuple.mapSecond (List.reverse >> Cmd.batch)


escapeDecoder : D.Decoder Msg
escapeDecoder =
    D.field "key" D.string
        |> D.andThen
            (\key ->
                if key == "Escape" then
                    D.succeed EscapePressed

                else
                    D.fail "not escape"
            )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Ports.logoutFinished LogoutFinished
        , if model.route == Home && model.user /= Nothing then Browser.Events.onResize (\width _ -> WorkDashboardMsg (WorkDashboard.Viewport width)) else Sub.none
        , if model.route == Reports && model.user /= Nothing then Ports.printResult (ManagementReport.Printed >> ManagementReportMsg) else Sub.none
        , if model.route == Chat && model.user /= Nothing then Sub.map TeamChatMsg (TeamChat.subscriptions model.teamChat) else Sub.none
        , Ports.recordChanged RecordsChanged
        , Browser.Events.onKeyDown escapeDecoder
        , if model.user /= Nothing then
            Sub.batch [ Time.every 600000 (\_ -> RefreshSession), Time.every 60000 (\_ -> PollWorkspaceClock) ]

          else
            Sub.none
        , case model.toast of
            Just _ ->
                Time.every 8000 (\_ -> DismissedToast)

            Nothing ->
                Sub.none
        , if model.pendingContactsQuery /= Nothing then
            Time.every 300 (\_ -> FlushContactsSearch)

          else
            Sub.none
        , if model.pendingDealsQuery /= Nothing then
            Time.every 300 (\_ -> FlushDealsSearch)

          else
            Sub.none
        , if model.pendingTasksQuery /= Nothing then
            Time.every 300 (\_ -> FlushTasksSearch)

          else
            Sub.none
        , if model.pendingSchoolsQuery /= Nothing then
            Time.every 300 (\_ -> FlushSchoolsSearch)

          else
            Sub.none
        , if model.pendingStudentsQuery /= Nothing then
            Time.every 300 (\_ -> FlushStudentsSearch)

          else
            Sub.none
        , if model.pendingAgentsQuery /= Nothing then
            Time.every 300 (\_ -> FlushAgentsSearch)

          else
            Sub.none
        , if model.pendingLeadsQuery /= Nothing then
            Time.every 300 (\_ -> FlushLeadsSearch)

          else
            Sub.none
        , if model.pendingCasesQuery /= Nothing then
            Time.every 300 (\_ -> FlushCasesSearch)

          else
            Sub.none
        , if model.pendingInvoicesQuery /= Nothing then
            Time.every 300 (\_ -> FlushInvoicesSearch)

          else
            Sub.none
        , if model.pendingPartnersQuery /= Nothing then
            Time.every 300 (\_ -> FlushPartnersSearch)

          else
            Sub.none
        ]


main : Program Flags Model Msg
main =
    Browser.application
        { init = init
        , view =
            \model ->
                { title = "ECC CRM"
                , body = [ Html.a [ Attr.href "#workspace-content", Attr.class "skip-link" ] [ Html.text "Skip to main content" ], Views.view model ]
                }
        , update = update
        , subscriptions = subscriptions
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }
