module Update.RequestOrder exposing (affectedFor, affected, all, scope, unwrap)

import Types exposing (..)


all : List String
all =
    [ "form", "contacts", "deals", "tasks", "schools", "students", "agents", "leads", "cases", "invoices", "partners", "detail", "activities", "case-documents", "invoice-payments", "dossier", "linked-students", "global-search", "audit" ]


scope : Msg -> Maybe String
scope msg =
    case msg of
        GotContacts _ -> Just "contacts"
        GotDeals _ -> Just "deals"
        GotTasks _ -> Just "tasks"
        GotSchools _ -> Just "schools"
        GotStudents _ -> Just "students"
        GotAgents _ -> Just "agents"
        GotLeads _ -> Just "leads"
        GotCases _ -> Just "cases"
        GotInvoices _ -> Just "invoices"
        GotPartners _ -> Just "partners"
        GotDealsAt _ _ _ _ -> Just "deals"
        FetchedContact _ -> Just "detail"
        FetchedDeal _ -> Just "detail"
        FetchedSchool _ -> Just "detail"
        FetchedStudent _ -> Just "detail"
        FetchedAgent _ -> Just "detail"
        FetchedLead _ -> Just "detail"
        FetchedCase _ -> Just "detail"
        FetchedInvoice _ -> Just "detail"
        FetchedPartner _ -> Just "detail"
        GotActivities _ -> Just "activities"
        GotCaseDocuments _ -> Just "case-documents"
        GotInvoicePayments _ -> Just "invoice-payments"
        GotStudentDossier _ -> Just "dossier"
        GotLinkedStudents _ _ -> Just "linked-students"
        GotGlobalSearch _ _ -> Just "global-search"
        GotAudit _ _ -> Just "audit"
        FetchFailed _ -> Just "detail"
        _ -> Nothing


unwrap : Msg -> Msg
unwrap msg =
    case msg of
        OrderedRead _ _ inner -> unwrap inner
        _ -> msg


-- Invalidate immediately on input, before the debounce starts a new request.
-- Save acknowledgements invalidate only the collections they reload.
affected : Msg -> List String
affected msg =
    case msg of
        RecordsChanged _ -> List.filter ((/=) "form") all
        UpdatedContactsQuery _ -> [ "contacts" ]
        ContactsPageChanged _ -> [ "contacts" ]
        GotSavedContact (Ok _) -> [ "contacts", "detail" ]
        GotDeletedContact _ _ (Ok _) -> [ "contacts", "detail" ]
        UpdatedDealsQuery _ -> [ "deals" ]
        GotSavedDeal (Ok _) -> [ "deals", "detail" ]
        GotDeletedDeal _ _ (Ok _) -> [ "deals", "detail" ]
        UpdatedTasksQuery _ -> [ "tasks" ]
        GotSavedTask (Ok _) -> [ "tasks", "detail" ]
        GotDeletedTask _ _ (Ok _) -> [ "tasks", "detail" ]
        UpdatedSchoolsQuery _ -> [ "schools" ]
        SchoolsPageChanged _ -> [ "schools" ]
        GotSavedSchool (Ok _) -> [ "schools", "detail" ]
        GotDeletedSchool _ _ (Ok _) -> [ "schools", "detail" ]
        UpdatedStudentsQuery _ -> [ "students" ]
        StudentsPageChanged _ -> [ "students" ]
        GotSavedStudent (Ok _) -> [ "students", "detail" ]
        GotDeletedStudent _ _ (Ok _) -> [ "students", "detail" ]
        UpdatedAgentsQuery _ -> [ "agents" ]
        AgentsPageChanged _ -> [ "agents" ]
        GotSavedAgent (Ok _) -> [ "agents", "detail" ]
        GotDeletedAgent _ _ (Ok _) -> [ "agents", "detail" ]
        UpdatedLeadsQuery _ -> [ "leads" ]
        LeadsPageChanged _ -> [ "leads" ]
        GotSavedLead (Ok _) -> [ "leads", "detail" ]
        GotDeletedLead _ _ (Ok _) -> [ "leads", "detail" ]
        UpdatedCasesQuery _ -> [ "cases" ]
        CasesPageChanged _ -> [ "cases" ]
        GotSavedCase (Ok _) -> [ "cases", "detail" ]
        GotDeletedCase _ _ (Ok _) -> [ "cases", "detail" ]
        UpdatedInvoicesQuery _ -> [ "invoices" ]
        InvoicesPageChanged _ -> [ "invoices" ]
        GotSavedInvoice (Ok _) -> [ "invoices", "detail" ]
        GotDeletedInvoice _ _ (Ok _) -> [ "invoices", "detail" ]
        UpdatedPartnersQuery _ -> [ "partners" ]
        PartnersPageChanged _ -> [ "partners" ]
        GotSavedPartner (Ok _) -> [ "partners", "detail" ]
        GotDeletedPartner _ _ (Ok _) -> [ "partners", "detail" ]
        ChangedTasksPage _ -> [ "tasks" ]
        UpdatedTasksStatusFilter _ -> [ "tasks" ]
        UpdatedCasesStageFilter _ -> [ "cases" ]
        UpdatedPartnersTypeFilter _ -> [ "partners" ]
        UpdatedPartnersCountryFilter _ -> [ "partners" ]
        UpdatedOwnerFilter _ -> [ "deals" ]
        UpdatedDateFromFilter _ -> [ "deals" ]
        UpdatedDateToFilter _ -> [ "deals" ]
        ClearedDealFilters -> [ "deals" ]
        RefreshDeals -> [ "deals" ]
        LoadMoreDeals -> [ "deals" ]
        GotMovedDeal (Ok _) -> [ "deals" ]
        GotBulkMoved _ (Ok _) -> [ "deals" ]
        GotBulkDeleted _ (Ok _) -> [ "deals" ]
        GotToggledTask (Ok _) -> [ "tasks" ]
        GotSavedActivity (Ok _) -> [ "activities", "detail" ]
        GotDeletedActivity (Ok _) -> [ "activities", "detail" ]
        GotSavedDocument (Ok _) -> [ "case-documents", "detail" ]
        GotDeletedDocument (Ok _) -> [ "case-documents", "detail" ]
        GotUpdatedDocument (Ok _) -> [ "case-documents" ]
        GotSavedPayment (Ok _) -> [ "invoice-payments", "invoices", "detail" ]
        GotDeletedPayment (Ok _) -> [ "invoice-payments", "invoices", "detail" ]
        GotRefunded (Ok _) -> [ "invoice-payments", "invoices" ]
        UpdatedGlobalQuery _ -> [ "global-search" ]
        ClosedGlobalSearch -> [ "global-search" ]
        RequestedAuditPage _ -> [ "audit" ]
        _ -> []


affectedFor : Route -> Msg -> List String
affectedFor route msg =
    let
        target =
            case msg of
                GotSavedContact (Ok record) -> Just (ContactDetail record.id)
                GotDeletedContact id _ (Ok _) -> Just (ContactDetail id)
                GotSavedDeal (Ok record) -> Just (DealDetail record.id)
                GotDeletedDeal id _ (Ok _) -> Just (DealDetail id)
                GotSavedSchool (Ok record) -> Just (SchoolDetail record.id)
                GotDeletedSchool id _ (Ok _) -> Just (SchoolDetail id)
                GotSavedStudent (Ok record) -> Just (StudentDetail record.id)
                GotDeletedStudent id _ (Ok _) -> Just (StudentDetail id)
                GotSavedAgent (Ok record) -> Just (AgentDetail record.id)
                GotDeletedAgent id _ (Ok _) -> Just (AgentDetail id)
                GotSavedLead (Ok record) -> Just (LeadDetail record.id)
                GotDeletedLead id _ (Ok _) -> Just (LeadDetail id)
                GotSavedCase (Ok record) -> Just (CaseDetail record.id)
                GotDeletedCase id _ (Ok _) -> Just (CaseDetail id)
                GotSavedInvoice (Ok record) -> Just (InvoiceDetail record.id)
                GotDeletedInvoice id _ (Ok _) -> Just (InvoiceDetail id)
                GotSavedPartner (Ok record) -> Just (PartnerDetail record.id)
                GotDeletedPartner id _ (Ok _) -> Just (PartnerDetail id)
                GotMovedDeal (Ok record) -> Just (DealDetail record.id)
                GotRefunded (Ok record) -> Just (InvoiceDetail record.id)
                _ -> Nothing
    in
    if target == Just route then
        "detail" :: affected msg
    else
        List.filter ((/=) "detail") (affected msg)
