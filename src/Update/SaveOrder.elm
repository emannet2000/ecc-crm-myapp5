module Update.SaveOrder exposing (boundary, completion, sessionReply, bulkCompletion, selectionBoundary, preserveForms)

{-| A form instance owns its save response. Older writes still acknowledge the
server result and refresh records, but cannot close or annotate a newer form.
-}

import Types exposing (..)


completion : Msg -> Bool
completion msg =
    case msg of
        GotSavedContact _ -> True
        GotSavedDeal _ -> True
        GotSavedTask _ -> True
        GotSavedSchool _ -> True
        GotSavedStudent _ -> True
        GotSavedAgent _ -> True
        GotSavedLead _ -> True
        GotSavedCase _ -> True
        GotSavedDocument _ -> True
        GotSavedInvoice _ -> True
        GotSavedPartner _ -> True
        GotSavedActivity _ -> True
        GotSavedPayment _ -> True
        GotRefunded _ -> True
        GotDeletedContact _ _ _ -> True
        GotDeletedDeal _ _ _ -> True
        GotDeletedTask _ _ _ -> True
        GotDeletedSchool _ _ _ -> True
        GotDeletedStudent _ _ _ -> True
        GotDeletedAgent _ _ _ -> True
        GotDeletedLead _ _ _ -> True
        GotDeletedCase _ _ _ -> True
        GotDeletedInvoice _ _ _ -> True
        GotDeletedPartner _ _ _ -> True
        GotDeletedActivity _ -> True
        GotDeletedDocument _ -> True
        GotDeletedPayment _ -> True
        _ -> False


boundary : Msg -> Bool
boundary msg =
    case msg of
        OpenedAddContact -> True
        OpenedEditContact _ -> True
        ConfirmedCloseContactForm -> True
        OpenedAddDeal -> True
        OpenedAddDealForContact _ -> True
        OpenedAddDealWithStage _ -> True
        OpenedEditDeal _ -> True
        ConfirmedCloseDealForm -> True
        OpenedActivityForm -> True
        ConfirmedCloseActivityForm -> True
        OpenedAddTask -> True
        OpenedAddTaskForContact _ -> True
        OpenedEditTask _ -> True
        ConfirmedCloseTaskForm -> True
        OpenedAddSchool -> True
        OpenedEditSchool _ -> True
        ConfirmedCloseSchoolForm -> True
        OpenedAddStudent -> True
        OpenedAddStudentForAgent _ -> True
        OpenedAddStudentForSchool _ -> True
        OpenedEditStudent _ -> True
        ConfirmedCloseStudentForm -> True
        OpenedAddAgent -> True
        OpenedEditAgent _ -> True
        ConfirmedCloseAgentForm -> True
        OpenedAddLead -> True
        OpenedEditLead _ -> True
        ConfirmedCloseLeadForm -> True
        OpenedAddCase -> True
        OpenedAddCaseForStudent _ -> True
        OpenedEditCase _ -> True
        ConfirmedCloseCaseForm -> True
        OpenedAddDocument -> True
        OpenedEditDocument _ -> True
        ConfirmedCloseDocumentForm -> True
        OpenedAddInvoice -> True
        OpenedEditInvoice _ -> True
        ConfirmedCloseInvoiceForm -> True
        OpenedPaymentForm -> True
        ClosedPaymentForm -> True
        RequestedRefund _ -> True
        CancelledRefund -> True
        ConfirmedRefund -> True
        OpenedAddPartner -> True
        OpenedEditPartner _ -> True
        ConfirmedClosePartnerForm -> True
        SubmittedContactForm -> True
        SubmittedDealForm -> True
        SubmittedTaskForm -> True
        SubmittedSchoolForm -> True
        SubmittedStudentForm -> True
        SubmittedAgentForm -> True
        SubmittedLeadForm -> True
        SubmittedCaseForm -> True
        SubmittedDocumentForm -> True
        SubmittedInvoiceForm -> True
        SubmittedPartnerForm -> True
        SubmittedActivityForm -> True
        SubmittedPaymentForm -> True
        RequestedDeleteContact _ -> True
        CancelledDeleteContact -> True
        ConfirmedDeleteContact -> True
        RequestedDeleteDeal _ -> True
        CancelledDeleteDeal -> True
        ConfirmedDeleteDeal -> True
        RequestedDeleteTask _ -> True
        CancelledDeleteTask -> True
        ConfirmedDeleteTask -> True
        RequestedDeleteSchool _ -> True
        CancelledDeleteSchool -> True
        ConfirmedDeleteSchool -> True
        RequestedDeleteStudent _ -> True
        CancelledDeleteStudent -> True
        ConfirmedDeleteStudent -> True
        RequestedDeleteAgent _ -> True
        CancelledDeleteAgent -> True
        ConfirmedDeleteAgent -> True
        RequestedDeleteLead _ -> True
        CancelledDeleteLead -> True
        ConfirmedDeleteLead -> True
        RequestedDeleteCase _ -> True
        CancelledDeleteCase -> True
        ConfirmedDeleteCase -> True
        RequestedDeleteInvoice _ -> True
        CancelledDeleteInvoice -> True
        ConfirmedDeleteInvoice -> True
        RequestedDeletePartner _ -> True
        CancelledDeletePartner -> True
        ConfirmedDeletePartner -> True
        RequestedDeleteActivity _ -> True
        CancelledDeleteActivity -> True
        ConfirmedDeleteActivity -> True
        RequestedDeleteDocument _ -> True
        CancelledDeleteDocument -> True
        ConfirmedDeleteDocument -> True
        RequestedDeletePayment _ -> True
        CancelledDeletePayment -> True
        ConfirmedDeletePayment -> True
        _ -> False


preserveForms : Model -> Model -> Model
preserveForms before after =
    { after
        | contactForm = before.contactForm
        , editingId = before.editingId
        , dealForm = before.dealForm
        , editingDealId = before.editingDealId
        , taskForm = before.taskForm
        , editingTaskId = before.editingTaskId
        , schoolForm = before.schoolForm
        , editingSchoolId = before.editingSchoolId
        , studentForm = before.studentForm
        , editingStudentId = before.editingStudentId
        , agentForm = before.agentForm
        , editingAgentId = before.editingAgentId
        , leadForm = before.leadForm
        , editingLeadId = before.editingLeadId
        , caseForm = before.caseForm
        , editingCaseId = before.editingCaseId
        , documentForm = before.documentForm
        , editingDocumentId = before.editingDocumentId
        , invoiceForm = before.invoiceForm
        , editingInvoiceId = before.editingInvoiceId
        , partnerForm = before.partnerForm
        , editingPartnerId = before.editingPartnerId
        , activityForm = before.activityForm
        , paymentForm = before.paymentForm
        , refundConfirmInvoice = before.refundConfirmInvoice
        , deletingContact = before.deletingContact
        , deletingDeal = before.deletingDeal
        , deletingTask = before.deletingTask
        , deletingSchool = before.deletingSchool
        , deletingStudent = before.deletingStudent
        , deletingAgent = before.deletingAgent
        , deletingLead = before.deletingLead
        , deletingCase = before.deletingCase
        , deletingDocument = before.deletingDocument
        , deletingInvoice = before.deletingInvoice
        , deletingPartner = before.deletingPartner
        , deletingActivity = before.deletingActivity
        , deletingPayment = before.deletingPayment
        , profileForm = before.profileForm
        , passwordForm = before.passwordForm
        , logoutAllConfirm = before.logoutAllConfirm
        , bulkDeleteConfirm = before.bulkDeleteConfirm
        , bulkMoveStage = before.bulkMoveStage
    }


sessionReply : Msg -> Bool
sessionReply msg =
    completion msg ||
        (case msg of
            GotUpdatedProfile _ -> True
            GotChangedPassword _ -> True
            GotLogoutAll _ -> True
            GotBulkMoved _ _ -> True
            GotBulkDeleted _ _ -> True
            GotMovedDeal _ -> True
            GotToggledTask _ -> True
            GotUpdatedDocument _ -> True
            _ -> False
        )


bulkCompletion : Msg -> Bool
bulkCompletion msg =
    case msg of
        GotBulkMoved _ _ -> True
        GotBulkDeleted _ _ -> True
        _ -> False


selectionBoundary : Msg -> Bool
selectionBoundary msg =
    case msg of
        ToggledDealSelection _ -> True
        ToggledSelectAllDeals -> True
        ClearedDealSelection -> True
        UpdatedDealsQuery _ -> True
        UpdatedOwnerFilter _ -> True
        UpdatedDateFromFilter _ -> True
        UpdatedDateToFilter _ -> True
        ClearedDealFilters -> True
        RefreshDeals -> True
        _ -> False
