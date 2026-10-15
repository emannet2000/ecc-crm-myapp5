module Update.Navigation exposing (update)

{-| URL and navigation messages.
-}

import Api
import Administration
import WorkDashboard
import ManagementReport
import TeamChat
import Browser
import Browser.Navigation as Nav
import Router exposing (parseRoute, routeToPath)
import Types exposing (..)
import Update.Loaders exposing (fetchForAgentRoute, fetchForCaseRoute, fetchForContactRoute, fetchForDealRoute, fetchForInvoiceRoute, fetchForLeadRoute, fetchForPartnerRoute, fetchForSchoolRoute, fetchForStudentRoute, loadActivities, loadAgents, loadCaseDocuments, loadCases, loadContacts, loadDeals, loadInvoicePayments, loadInvoices, loadLeads, loadPartners, loadSchools, loadStudentDossier, loadStudents, loadTasks, refresh)
import Url


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ToggledSideBar ->
            ( { model | sidebarOpen = not model.sidebarOpen }, Cmd.none )

        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model, Nav.pushUrl model.navKey (Url.toString url) )

                Browser.External href ->
                    ( model, Nav.load href )

        UrlChanged url ->
            update (NavigatedTo (parseRoute url)) { model | workspaceQuery = Maybe.withDefault "" url.query }

        NavigatedTo route ->
            let
                seededProfile =
                    if route == Settings then
                        case model.user of
                            Just u ->
                                profileFromUser u

                            Nothing ->
                                emptyProfileForm

                    else
                        model.profileForm

                preservedContact =
                    case ( route, model.viewingContact ) of
                        ( ContactDetail id, Just c ) ->
                            if c.id == id then
                                Just c

                            else
                                Nothing

                        _ ->
                            Nothing

                preservedDeal =
                    case ( route, model.viewingDeal ) of
                        ( DealDetail id, Just d ) ->
                            if d.id == id then
                                Just d

                            else
                                Nothing

                        _ ->
                            Nothing

                preservedSchool =
                    case ( route, model.viewingSchool ) of
                        ( SchoolDetail id, Just s ) ->
                            if s.id == id then
                                Just s

                            else
                                Nothing

                        _ ->
                            Nothing

                preservedStudent =
                    case ( route, model.viewingStudent ) of
                        ( StudentDetail id, Just s ) ->
                            if s.id == id then
                                Just s

                            else
                                Nothing

                        _ ->
                            Nothing

                preservedAgent =
                    case ( route, model.viewingAgent ) of
                        ( AgentDetail id, Just a ) ->
                            if a.id == id then
                                Just a

                            else
                                Nothing

                        _ ->
                            Nothing

                preservedLead =
                    case ( route, model.viewingLead ) of
                        ( LeadDetail id, Just l ) ->
                            if l.id == id then
                                Just l

                            else
                                Nothing

                        _ ->
                            Nothing

                preservedCase =
                    case ( route, model.viewingCase ) of
                        ( CaseDetail id, Just c ) ->
                            if c.id == id then
                                Just c

                            else
                                Nothing

                        _ ->
                            Nothing

                preservedInvoice =
                    case ( route, model.viewingInvoice ) of
                        ( InvoiceDetail id, Just inv ) ->
                            if inv.id == id then
                                Just inv

                            else
                                Nothing

                        _ ->
                            Nothing

                preservedPartner =
                    case ( route, model.viewingPartner ) of
                        ( PartnerDetail id, Just p ) ->
                            if p.id == id then
                                Just p

                            else
                                Nothing

                        _ ->
                            Nothing

                preservedDossier =
                    case ( route, model.studentDossier ) of
                        ( StudentDetail _, Success d ) ->
                            Success d

                        _ ->
                            NotAsked

                clearedModel =
                    { model
                        | route = route
                        , dealsRequestId = model.dealsRequestId + 1
                        , sidebarOpen = False
                        , contactForm = Nothing
                        , deletingContact = Nothing
                        , viewingContact = preservedContact
                        , dealForm = Nothing
                        , deletingDeal = Nothing
                        , viewingDeal = preservedDeal
                        , activityForm = Nothing
                        , deletingActivity = Nothing
                        , activities = NotAsked
                        , taskForm = Nothing
                        , deletingTask = Nothing
                        , schoolForm = Nothing
                        , deletingSchool = Nothing
                        , viewingSchool = preservedSchool
                        , studentForm = Nothing
                        , deletingStudent = Nothing
                        , viewingStudent = preservedStudent
                        , studentDossier = preservedDossier
                        , agentForm = Nothing
                        , deletingAgent = Nothing
                        , viewingAgent = preservedAgent
                        , leadForm = Nothing
                        , deletingLead = Nothing
                        , viewingLead = preservedLead
                        , profileForm = seededProfile
                        , passwordForm = emptyPasswordForm
                        , logoutAllConfirm = False
                        , bulkDeleteConfirm = False
                        , bulkMoveStage = Nothing
                        , caseForm = Nothing
                        , deletingCase = Nothing
                        , viewingCase = preservedCase
                        , caseDocuments = NotAsked
                        , documentForm = Nothing
                        , deletingDocument = Nothing
                        , invoiceForm = Nothing
                        , deletingInvoice = Nothing
                        , viewingInvoice = preservedInvoice
                        , invoicePayments = NotAsked
                        , paymentForm = Nothing
                        , deletingPayment = Nothing
                        , refundConfirmInvoice = Nothing
                        , partnerForm = Nothing
                        , deletingPartner = Nothing
                        , viewingPartner = preservedPartner
                    }

                onHome =
                    route == Home

                onContactDetail =
                    case route of
                        ContactDetail _ ->
                            True

                        _ ->
                            False

                onStudentDetail =
                    case route of
                        StudentDetail _ ->
                            True

                        _ ->
                            False

                needsContacts =
                    (onHome || route == Contacts || route == Tasks)
                        && clearedModel.contacts
                        == NotAsked

                needsDeals =
                    (onHome || route == Deals || onContactDetail)
                        && clearedModel.deals
                        == NotAsked

                needsTasks =
                    (onHome || route == Tasks || onContactDetail)
                        && clearedModel.tasks
                        == NotAsked

                needsSchools =
                    onHome
                        || ((route == Schools || route == Students)
                                && clearedModel.schools
                                == NotAsked
                           )

                needsStudents =
                    onHome
                        || ((route == Students || onStudentDetail)
                                && clearedModel.students
                                == NotAsked
                           )

                needsAgents =
                    onHome
                        || ((route == Agents || route == Students)
                                && clearedModel.agents
                                == NotAsked
                           )

                needsLeads =
                    onHome
                        || (route == Leads && clearedModel.leads == NotAsked)

                needsCases =
                    (onHome || route == Cases || onStudentDetail)
                        && clearedModel.cases
                        == NotAsked

                needsInvoices =
                    (onHome || route == Invoices || onStudentDetail)
                        && clearedModel.invoices
                        == NotAsked

                needsPartners =
                    route == Partners && clearedModel.partners == NotAsked

                contactsCmd =
                    if needsContacts then
                        Tuple.second (loadContacts clearedModel)

                    else
                        Cmd.none

                dealsCmd =
                    if needsDeals then
                        Tuple.second (loadDeals clearedModel)

                    else
                        Cmd.none

                tasksCmd =
                    if needsTasks then
                        Tuple.second (loadTasks clearedModel)

                    else
                        Cmd.none

                schoolsCmd =
                    if needsSchools then
                        Tuple.second (loadSchools clearedModel)

                    else
                        Cmd.none

                studentsCmd =
                    if needsStudents then
                        Tuple.second (loadStudents clearedModel)

                    else
                        Cmd.none

                agentsCmd =
                    if needsAgents then
                        Tuple.second (loadAgents clearedModel)

                    else
                        Cmd.none

                leadsCmd =
                    if needsLeads then
                        Tuple.second (loadLeads clearedModel)

                    else
                        Cmd.none

                casesCmd =
                    if needsCases then
                        Tuple.second (loadCases clearedModel)

                    else
                        Cmd.none

                invoicesCmd =
                    if needsInvoices then
                        Tuple.second (loadInvoices clearedModel)

                    else
                        Cmd.none

                partnersCmd =
                    if needsPartners then
                        Tuple.second (loadPartners clearedModel)

                    else
                        Cmd.none

                activityCmd =
                    case ( route, preservedContact ) of
                        ( ContactDetail _, Just c ) ->
                            Tuple.second (loadActivities clearedModel c.id)

                        _ ->
                            Cmd.none

                caseDocCmd =
                    case ( route, preservedCase ) of
                        ( CaseDetail _, Just c ) ->
                            Tuple.second (loadCaseDocuments clearedModel c.id)

                        _ ->
                            Cmd.none

                invoicePaymentCmd =
                    case ( route, preservedInvoice ) of
                        ( InvoiceDetail _, Just inv ) ->
                            Tuple.second (loadInvoicePayments clearedModel inv.id)

                        _ ->
                            Cmd.none

                dossierCmd =
                    case route of
                        StudentDetail sid ->
                            case clearedModel.studentDossier of
                                Success _ ->
                                    Cmd.none

                                _ ->
                                    Tuple.second (loadStudentDossier clearedModel sid)

                        _ ->
                            Cmd.none

                fetchCmd =
                    case route of
                        ContactDetail _ ->
                            fetchForContactRoute clearedModel route preservedContact

                        DealDetail _ ->
                            fetchForDealRoute clearedModel route preservedDeal

                        SchoolDetail _ ->
                            fetchForSchoolRoute clearedModel route preservedSchool

                        StudentDetail _ ->
                            fetchForStudentRoute clearedModel route preservedStudent

                        AgentDetail _ ->
                            fetchForAgentRoute clearedModel route preservedAgent

                        LeadDetail _ ->
                            fetchForLeadRoute clearedModel route preservedLead

                        CaseDetail _ ->
                            fetchForCaseRoute clearedModel route preservedCase

                        InvoiceDetail _ ->
                            fetchForInvoiceRoute clearedModel route preservedInvoice

                        PartnerDetail _ ->
                            fetchForPartnerRoute clearedModel route preservedPartner

                        _ ->
                            Cmd.none

                finalModel =
                    { clearedModel
                        | workDashboard =
                            if route == Home then
                                WorkDashboard.start (Maybe.map .id model.user |> Maybe.withDefault "") clearedModel.workDashboard |> Tuple.first
                            else
                                clearedModel.workDashboard
                        , managementReport =
                            if route == Reports then
                                ManagementReport.start (Maybe.map .id model.user |> Maybe.withDefault "") clearedModel.managementReport |> Tuple.first
                            else
                                clearedModel.managementReport
                        , teamChat =
                            if route == Chat then
                                TeamChat.start (Maybe.map .id model.user |> Maybe.withDefault "") clearedModel.teamChat |> Tuple.first
                            else
                                clearedModel.teamChat
                        , administration =
                            if route == Types.Administration && Maybe.map .role model.user == Just "admin" && ((Maybe.map .currentUserId clearedModel.administration.data /= Maybe.map .id model.user) || (not (Administration.dirty clearedModel.administration) && not clearedModel.administration.busy)) then
                                Administration.update Administration.Start clearedModel.administration |> Tuple.first
                            else
                                clearedModel.administration
                        , globalQuery = ""
                        , globalResults = NotAsked
                        , auditOffset =
                            if route == Reports then
                                0

                            else
                                clearedModel.auditOffset
                        , audit =
                            if route == Reports then
                                Loading

                            else
                                clearedModel.audit
                        , reports =
                            if route == Reports || route == Home then
                                Loading

                            else
                                clearedModel.reports
                        , contacts =
                            if needsContacts then
                                refresh clearedModel.contacts

                            else
                                clearedModel.contacts
                        , deals =
                            if needsDeals then
                                Loading

                            else
                                clearedModel.deals
                        , tasks =
                            if needsTasks then
                                refresh clearedModel.tasks

                            else
                                clearedModel.tasks
                        , schools =
                            if needsSchools then
                                refresh clearedModel.schools

                            else
                                clearedModel.schools
                        , students =
                            if needsStudents then
                                refresh clearedModel.students

                            else
                                clearedModel.students
                        , linkedStudents =
                            case route of
                                AgentDetail _ ->
                                    Loading

                                SchoolDetail _ ->
                                    Loading

                                _ ->
                                    NotAsked
                        , agents =
                            if needsAgents then
                                refresh clearedModel.agents

                            else
                                clearedModel.agents
                        , leads =
                            if needsLeads then
                                refresh clearedModel.leads

                            else
                                clearedModel.leads
                        , cases =
                            if needsCases then
                                refresh clearedModel.cases

                            else
                                clearedModel.cases
                        , invoices =
                            if needsInvoices then
                                refresh clearedModel.invoices

                            else
                                clearedModel.invoices
                        , partners =
                            if needsPartners then
                                refresh clearedModel.partners

                            else
                                clearedModel.partners
                    }
            in
            ( finalModel
            , Cmd.batch
                [ if route == Home then
                    WorkDashboard.start (Maybe.map .id model.user |> Maybe.withDefault "") clearedModel.workDashboard |> Tuple.second |> Cmd.map WorkDashboardMsg
                  else
                    Cmd.none
                , if route == Reports then
                    ManagementReport.start (Maybe.map .id model.user |> Maybe.withDefault "") clearedModel.managementReport |> Tuple.second |> Cmd.map ManagementReportMsg
                  else
                    Cmd.none
                , if route == Chat then
                    TeamChat.start (Maybe.map .id model.user |> Maybe.withDefault "") clearedModel.teamChat |> Tuple.second |> Cmd.map TeamChatMsg
                  else
                    Cmd.none
                , if route == Types.Administration && Maybe.map .role model.user == Just "admin" && ((Maybe.map .currentUserId clearedModel.administration.data /= Maybe.map .id model.user) || (not (Administration.dirty clearedModel.administration) && not clearedModel.administration.busy)) then
                    Administration.update Administration.Start clearedModel.administration |> Tuple.second |> Cmd.map AdministrationMsg
                  else
                    Cmd.none
                , if route == Reports || route == Home then
                    case clearedModel.token of
                        Just token ->
                            Cmd.batch [ if route == Home then Api.fetchReports token GotReports else Cmd.none, if route == Reports then Api.fetchAudit token 0 (GotAudit 0) else Cmd.none ]

                        Nothing ->
                            Cmd.none

                  else
                    Cmd.none
                , contactsCmd
                , dealsCmd
                , tasksCmd
                , activityCmd
                , schoolsCmd
                , studentsCmd
                , agentsCmd
                , leadsCmd
                , casesCmd
                , invoicesCmd
                , partnersCmd
                , caseDocCmd
                , invoicePaymentCmd
                , dossierCmd
                , fetchCmd
                ]
            )

        _ ->
            ( model, Cmd.none )
