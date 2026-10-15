module Update.Loaders exposing (fetchForAgentRoute, fetchForCaseRoute, fetchForContactRoute, fetchForDealRoute, fetchForInvoiceRoute, fetchForLeadRoute, fetchForPartnerRoute, fetchForSchoolRoute, fetchForStudentRoute, loadActivities, loadAgents, loadCaseDocuments, loadCases, loadContacts, loadDeals, loadInvoicePayments, loadInvoices, loadLeads, loadPartners, loadSchools, loadStudentDossier, loadStudents, loadTasks, pageSize, refresh)

{-| Data-loading commands and route-driven fetches.
-}

import Api
import Types exposing (..)


-- Retain the query, filters and offset while refreshing existing results.
refresh : RemoteData a -> RemoteData a
refresh data =
    case data of
        Success _ -> data
        _ -> Loading


pageSize : Int
pageSize =
    25


dealsBoardLimit : Int
dealsBoardLimit =
    50


contactsQueryOf : Model -> String
contactsQueryOf model =
    case model.contacts of
        Success d ->
            d.query

        _ ->
            ""


contactsOffsetOf : Model -> Int
contactsOffsetOf model =
    case model.contacts of
        Success d ->
            d.offset

        _ ->
            0


dealsQueryOf : Model -> String
dealsQueryOf model =
    case model.deals of
        Success d ->
            d.query

        _ ->
            ""


loadContacts : Model -> ( Model, Cmd Msg )
loadContacts model =
    case model.token of
        Just t ->
            ( { model | contacts = refresh model.contacts }
            , Api.fetchContacts t (contactsQueryOf model) pageSize (contactsOffsetOf model) GotContacts
            )

        Nothing ->
            ( model, Cmd.none )


loadDeals : Model -> ( Model, Cmd Msg )
loadDeals model =
    case model.token of
        Just t ->
            ( { model | deals = Loading }
            , Api.fetchDeals t (dealsQueryOf model) model.ownerFilter model.dateFromFilter model.dateToFilter "" dealsBoardLimit 0 (GotDealsAt model.dealsRequestId (dealsQueryOf model) False)
            )

        Nothing ->
            ( model, Cmd.none )


loadTasks : Model -> ( Model, Cmd Msg )
loadTasks model =
    case model.token of
        Just t ->
            let
                ( q, st ) =
                    case model.tasks of
                        Success d ->
                            ( d.query, d.statusFilter )

                        _ ->
                            ( "", "" )
            in
            ( { model | tasks = refresh model.tasks }
            , Api.fetchTasksPage t q st model.taskOffset GotTasks
            )

        Nothing ->
            ( model, Cmd.none )


loadSchools : Model -> ( Model, Cmd Msg )
loadSchools model =
    case model.token of
        Just t ->
            let
                ( q, offset ) =
                    case model.schools of
                        Success d ->
                            ( d.query, d.offset )

                        _ ->
                            ( "", 0 )
            in
            ( { model | schools = refresh model.schools }
            , Api.fetchSchools t q pageSize offset GotSchools
            )

        Nothing ->
            ( model, Cmd.none )


loadStudents : Model -> ( Model, Cmd Msg )
loadStudents model =
    case model.token of
        Just t ->
            let
                ( q, offset ) =
                    case model.students of
                        Success d ->
                            ( d.query, d.offset )

                        _ ->
                            ( "", 0 )
            in
            ( { model | students = refresh model.students }
            , Api.fetchStudents t q pageSize offset GotStudents
            )

        Nothing ->
            ( model, Cmd.none )


loadStudentDossier : Model -> String -> ( Model, Cmd Msg )
loadStudentDossier model studentId =
    case model.token of
        Just t ->
            ( { model | studentDossier = Loading }
            , Api.fetchStudentDossier t studentId GotStudentDossier
            )

        Nothing ->
            ( model, Cmd.none )


loadAgents : Model -> ( Model, Cmd Msg )
loadAgents model =
    case model.token of
        Just t ->
            let
                ( q, offset ) =
                    case model.agents of
                        Success d ->
                            ( d.query, d.offset )

                        _ ->
                            ( "", 0 )
            in
            ( { model | agents = refresh model.agents }
            , Api.fetchAgents t q pageSize offset GotAgents
            )

        Nothing ->
            ( model, Cmd.none )


loadLeads : Model -> ( Model, Cmd Msg )
loadLeads model =
    case model.token of
        Just t ->
            let
                ( q, offset ) =
                    case model.leads of
                        Success d ->
                            ( d.query, d.offset )

                        _ ->
                            ( "", 0 )
            in
            ( { model | leads = refresh model.leads }
            , Api.fetchLeads t q pageSize offset GotLeads
            )

        Nothing ->
            ( model, Cmd.none )


loadCases : Model -> ( Model, Cmd Msg )
loadCases model =
    case model.token of
        Just t ->
            let
                ( q, st, offset ) =
                    case model.cases of
                        Success d ->
                            ( d.query, d.stageFilter, d.offset )

                        _ ->
                            ( "", "", 0 )
            in
            ( { model | cases = refresh model.cases }
            , Api.fetchCases t q st pageSize offset GotCases
            )

        Nothing ->
            ( model, Cmd.none )


loadInvoices : Model -> ( Model, Cmd Msg )
loadInvoices model =
    case model.token of
        Just t ->
            let
                ( q, offset ) =
                    case model.invoices of
                        Success d ->
                            ( d.query, d.offset )

                        _ ->
                            ( "", 0 )
            in
            ( { model | invoices = refresh model.invoices }
            , Api.fetchInvoices t q pageSize offset GotInvoices
            )

        Nothing ->
            ( model, Cmd.none )


loadPartners : Model -> ( Model, Cmd Msg )
loadPartners model =
    case model.token of
        Just t ->
            let
                ( q, tp ) =
                    case model.partners of
                        Success d ->
                            ( d.query, d.typeFilter )

                        _ ->
                            ( "", "" )

                ( co, offset ) =
                    case model.partners of
                        Success d ->
                            ( d.countryFilter, d.offset )

                        _ ->
                            ( "", 0 )
            in
            ( { model | partners = refresh model.partners }
            , Api.fetchPartners t q tp co pageSize offset GotPartners
            )

        Nothing ->
            ( model, Cmd.none )


loadActivities : Model -> String -> ( Model, Cmd Msg )
loadActivities model contactId =
    case model.token of
        Just t ->
            ( { model | activities = Loading }
            , Api.fetchActivities t contactId GotActivities
            )

        Nothing ->
            ( model, Cmd.none )


loadCaseDocuments : Model -> String -> ( Model, Cmd Msg )
loadCaseDocuments model caseId =
    case model.token of
        Just t ->
            ( { model | caseDocuments = Loading }
            , Api.fetchCaseDocuments t caseId GotCaseDocuments
            )

        Nothing ->
            ( model, Cmd.none )


loadInvoicePayments : Model -> String -> ( Model, Cmd Msg )
loadInvoicePayments model invoiceId =
    case model.token of
        Just t ->
            ( { model | invoicePayments = Loading }
            , Api.fetchInvoicePayments t invoiceId GotInvoicePayments
            )

        Nothing ->
            ( model, Cmd.none )


fetchForContactRoute : Model -> Route -> Maybe Contact -> Cmd Msg
fetchForContactRoute model route preserved =
    case ( route, preserved, model.token ) of
        ( ContactDetail id, Nothing, Just t ) ->
            Api.fetchContact t id FetchedContact

        _ ->
            Cmd.none


fetchForDealRoute : Model -> Route -> Maybe Deal -> Cmd Msg
fetchForDealRoute model route preserved =
    case ( route, preserved, model.token ) of
        ( DealDetail id, Nothing, Just t ) ->
            Api.fetchDeal t id FetchedDeal

        _ ->
            Cmd.none


fetchForSchoolRoute : Model -> Route -> Maybe School -> Cmd Msg
fetchForSchoolRoute model route preserved =
    case ( route, model.token ) of
        ( SchoolDetail id, Just t ) ->
            let
                schoolCmd =
                    case preserved of
                        Nothing ->
                            Api.fetchSchool t id FetchedSchool

                        Just _ ->
                            Cmd.none
            in
            Cmd.batch [ schoolCmd, Api.fetchLinkedStudents t "school" id (GotLinkedStudents id) ]

        _ ->
            Cmd.none


fetchForStudentRoute : Model -> Route -> Maybe Student -> Cmd Msg
fetchForStudentRoute model route preserved =
    case ( route, preserved, model.token ) of
        ( StudentDetail id, Nothing, Just t ) ->
            Api.fetchStudent t id FetchedStudent

        _ ->
            Cmd.none


fetchForAgentRoute : Model -> Route -> Maybe Agent -> Cmd Msg
fetchForAgentRoute model route preserved =
    case ( route, model.token ) of
        ( AgentDetail id, Just t ) ->
            let
                agentCmd =
                    case preserved of
                        Nothing ->
                            Api.fetchAgent t id FetchedAgent

                        Just _ ->
                            Cmd.none
            in
            Cmd.batch [ agentCmd, Api.fetchLinkedStudents t "agent" id (GotLinkedStudents id) ]

        _ ->
            Cmd.none


fetchForLeadRoute : Model -> Route -> Maybe Lead -> Cmd Msg
fetchForLeadRoute model route preserved =
    case ( route, preserved, model.token ) of
        ( LeadDetail id, Nothing, Just t ) ->
            Api.fetchLead t id FetchedLead

        _ ->
            Cmd.none


fetchForCaseRoute : Model -> Route -> Maybe Case -> Cmd Msg
fetchForCaseRoute model route preserved =
    case ( route, preserved, model.token ) of
        ( CaseDetail id, Nothing, Just t ) ->
            Api.fetchCase t id FetchedCase

        _ ->
            Cmd.none


fetchForInvoiceRoute : Model -> Route -> Maybe Invoice -> Cmd Msg
fetchForInvoiceRoute model route preserved =
    case ( route, preserved, model.token ) of
        ( InvoiceDetail id, Nothing, Just t ) ->
            Api.fetchInvoice t id FetchedInvoice

        _ ->
            Cmd.none


fetchForPartnerRoute : Model -> Route -> Maybe Partner -> Cmd Msg
fetchForPartnerRoute model route preserved =
    case ( route, preserved, model.token ) of
        ( PartnerDetail id, Nothing, Just t ) ->
            Api.fetchPartner t id FetchedPartner

        _ ->
            Cmd.none
