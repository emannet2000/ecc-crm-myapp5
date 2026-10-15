module RequestOrderChecks exposing (checks)

import Frontend.RequestOrder as Order
import Types exposing (..)
import Update.RequestOrder as Requests
import Update.Loaders exposing (refresh)
import Update.SaveOrder as Saves


checks : List ( String, Bool )
checks =
    let
        first = Order.advance (Requests.affected (UpdatedContactsQuery "first")) Order.init
        latest = Order.advance (Requests.affected (UpdatedContactsQuery "latest")) first
        repeated = Order.advance (Requests.affected (UpdatedContactsQuery "first")) latest
        navigated = Order.advance Requests.all repeated
        returned = Order.advance Requests.all navigated
        unrelated = Order.advance (Requests.affected (UpdatedLeadsQuery "other")) latest
        paged = Order.advance (Requests.affected (ContactsPageChanged 25)) latest
        filtered = Order.advance (Requests.affected (UpdatedCasesStageFilter "Approved")) latest
        readErrors = [ GotContacts (Err "late"), GotTasks (Err "late"), GotSchools (Err "late"), GotStudents (Err "late"), GotAgents (Err "late"), GotLeads (Err "late"), GotCases (Err "late"), GotInvoices (Err "late"), GotPartners (Err "late") ]
        detailErrors = [ FetchedContact (Err "late"), FetchedDeal (Err "late"), FetchedSchool (Err "late"), FetchedStudent (Err "late"), FetchedAgent (Err "late"), FetchedLead (Err "late"), FetchedCase (Err "late"), FetchedInvoice (Err "late"), FetchedPartner (Err "late") ]
    in
    [ ( "Refreshing a filtered page retains its query and page context", refresh (Success { query = "nursing", offset = 25, filter = "Approved" }) == Success { query = "nursing", offset = 25, filter = "Approved" } )
    , ( "Initial lists still show their loading state", refresh NotAsked == Loading )
    , ( "A late search response cannot replace a newer search", not (Order.current "contacts" first latest) )
    , ( "Returning to the same search text does not accept its older request", not (Order.current "contacts" first repeated) )
    , ( "Typing invalidates an outstanding response before the debounce runs", not (Order.current "contacts" first latest) )
    , ( "An unrelated list does not cancel the current search", Order.current "contacts" latest unrelated )
    , ( "Pagination invalidates the previous page", not (Order.current "contacts" latest paged) )
    , ( "Filters invalidate the previous filter response", not (Order.current "cases" latest filtered) )
    , ( "Leaving and returning to a record rejects the previous visit's details", not (Order.current "detail" repeated returned) )
    , ( "Navigation invalidates linked records and related collections too", List.all (\key -> not (Order.current key repeated returned)) [ "activities", "case-documents", "invoice-payments", "dossier", "linked-students" ] )
    , ( "Late list errors receive the same protection as successes", List.all (Requests.scope >> (/=) Nothing) readErrors )
    , ( "Late detail errors receive the same protection as successes", List.all (Requests.scope >> (==) (Just "detail")) detailErrors )
    , ( "Write acknowledgements are not dropped as stale reads", Requests.scope (GotDeletedContact "contact-1" "Submitted record" (Ok "deleted")) == Nothing )
    , ( "An old deletion leaves the current detail request active", not (List.member "detail" (Requests.affectedFor (ContactDetail "current") (GotDeletedContact "older" "Submitted record" (Ok "deleted")))) )
    , ( "Deleting the current record invalidates its detail request", List.member "detail" (Requests.affectedFor (ContactDetail "current") (GotDeletedContact "current" "Submitted record" (Ok "deleted"))) )
    , ( "Background record changes preserve form ownership", not (List.member "form" (Requests.affected (RecordsChanged "saved-record"))))
    , ( "New and reopened forms advance save ownership, including the same record", List.all Saves.boundary [ OpenedAddContact, OpenedAddDeal, OpenedAddTask, OpenedAddSchool, OpenedAddStudent, OpenedAddAgent, OpenedAddLead, OpenedAddCase, OpenedAddDocument, OpenedAddInvoice, OpenedAddPartner, OpenedActivityForm, OpenedPaymentForm ] )
    , ( "Each submitted form gets its own save generation", List.all Saves.boundary [ SubmittedContactForm, SubmittedDealForm, SubmittedTaskForm, SubmittedSchoolForm, SubmittedStudentForm, SubmittedAgentForm, SubmittedLeadForm, SubmittedCaseForm, SubmittedDocumentForm, SubmittedInvoiceForm, SubmittedPartnerForm, SubmittedActivityForm, SubmittedPaymentForm, ConfirmedRefund ] )
    , ( "Late validation errors are protected for every form", List.all Saves.completion [ GotSavedContact (Err (FieldErrors [])), GotSavedDeal (Err (FieldErrors [])), GotSavedTask (Err (FieldErrors [])), GotSavedSchool (Err (FieldErrors [])), GotSavedStudent (Err (FieldErrors [])), GotSavedAgent (Err (FieldErrors [])), GotSavedLead (Err (FieldErrors [])), GotSavedCase (Err (FieldErrors [])), GotSavedDocument (Err (FieldErrors [])), GotSavedInvoice (Err (FieldErrors [])), GotSavedPartner (Err (FieldErrors [])), GotSavedActivity (Err (FieldErrors [])), GotSavedPayment (Err (FieldErrors [])), GotRefunded (Err (FieldErrors [])) ] )
    , ( "Profile, password, and sign-out replies require the original login", List.all Saves.sessionReply [ GotUpdatedProfile (Err (GenericError "late")), GotChangedPassword (Err "late"), GotLogoutAll (Ok "done") ] )
    , ( "Deletes keep ownership protection on both success and failure", List.all Saves.completion [ GotDeletedContact "id" "Original name" (Ok "id"), GotDeletedDeal "id" "Original name" (Err "late"), GotDeletedTask "id" "Original title" (Ok "id"), GotDeletedActivity (Err "late"), GotDeletedDocument (Ok "id"), GotDeletedPayment (Err "late") ] )
    , ( "New delete confirmations own their responses", List.all Saves.boundary [ ConfirmedDeleteContact, ConfirmedDeleteDeal, ConfirmedDeleteTask, ConfirmedDeleteSchool, ConfirmedDeleteStudent, ConfirmedDeleteAgent, ConfirmedDeleteLead, ConfirmedDeleteCase, ConfirmedDeleteDocument, ConfirmedDeleteInvoice, ConfirmedDeletePayment, ConfirmedDeletePartner, ConfirmedDeleteActivity ] )
    , ( "Changing or reselecting deals invalidates older selection ownership", List.all Saves.selectionBoundary [ ToggledDealSelection "same-id", ToggledSelectAllDeals, ClearedDealSelection, UpdatedDealsQuery "other", UpdatedOwnerFilter "other", UpdatedDateFromFilter "2099-01-01", UpdatedDateToFilter "2099-12-31", ClearedDealFilters, RefreshDeals ] )
    , ( "Bulk replies require both login and selection ownership", List.all (\msg -> Saves.bulkCompletion msg && Saves.sessionReply msg) [ GotBulkMoved [ "old" ] (Err (GenericError "late")), GotBulkDeleted [ "old" ] (Ok "old") ] )
    ]
