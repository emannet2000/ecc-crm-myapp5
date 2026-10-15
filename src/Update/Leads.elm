module Update.Leads exposing (update)

{-| Lead messages.
-}

import Api
import Types exposing (..)
import Update.Loaders exposing (loadLeads, pageSize)
import Update.Navigation
import Update.Validate exposing (validateLeadForm)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotLeads result ->
            case result of
                Ok ( items, total ) ->
                    let
                        prev =
                            case model.leads of
                                Success d ->
                                    d

                                _ ->
                                    { items = [], query = "", total = 0, offset = 0, limit = pageSize }
                    in
                    ( { model
                        | leads =
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
                    ( { model | leads = Failure message }, Cmd.none )

        UpdatedLeadsQuery q ->
            let
                next =
                    case model.leads of
                        Success data ->
                            Success { data | query = q, offset = 0 }

                        _ ->
                            Success { items = [], query = q, total = 0, offset = 0, limit = pageSize }
            in
            ( { model | leads = next, pendingLeadsQuery = Just q }, Cmd.none )

        FlushLeadsSearch ->
            case ( model.token, model.pendingLeadsQuery ) of
                ( Just t, Just q ) ->
                    ( { model | pendingLeadsQuery = Nothing }
                    , Api.fetchLeads t q pageSize 0 GotLeads
                    )

                _ ->
                    ( { model | pendingLeadsQuery = Nothing }, Cmd.none )

        LeadsPageChanged newOffset ->
            case ( model.token, model.leads ) of
                ( Just t, Success data ) ->
                    ( { model | leads = Success { data | offset = newOffset } }
                    , Api.fetchLeads t data.query pageSize newOffset GotLeads
                    )

                _ ->
                    ( model, Cmd.none )

        OpenedAddLead ->
            ( { model
                | leadForm = Just emptyLeadForm
                , editingLeadId = Nothing
                , toast = Nothing
              }
            , Cmd.none
            )

        OpenedEditLead lead ->
            ( { model
                | leadForm = Just (leadToForm lead)
                , editingLeadId = Just lead.id
                , toast = Nothing
              }
            , Cmd.none
            )

        OpenedLeadDetail lead ->
            Update.Navigation.update (NavigatedTo (LeadDetail lead.id))
                { model | viewingLead = Just lead, toast = Nothing }

        RequestedCloseLeadForm ->
            case ( model.leadForm, model.deletingLead ) of
                ( _, Just _ ) ->
                    ( { model | deletingLead = Nothing }, Cmd.none )

                ( Just lf, _ ) ->
                    if lf.dirty && not lf.submitting then
                        ( { model | leadForm = Just { lf | confirmDiscard = True } }, Cmd.none )

                    else
                        ( { model | leadForm = Nothing, editingLeadId = Nothing }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ConfirmedCloseLeadForm ->
            ( { model | leadForm = Nothing, editingLeadId = Nothing }, Cmd.none )

        CancelledCloseLeadForm ->
            case model.leadForm of
                Just lf ->
                    ( { model | leadForm = Just { lf | confirmDiscard = False } }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        UpdatedLeadFormField field value ->
            case model.leadForm of
                Just lf ->
                    let
                        updated =
                            case field of
                                "nextAction" ->
                                    { lf | nextAction = value }

                                "duplicateConfirmed" ->
                                    { lf | duplicateConfirmed = value == "true" }

                                "referrer" ->
                                    { lf | referrer = value }

                                "leadNumber" ->
                                    { lf | leadNumber = value }

                                "name" ->
                                    { lf | name = value }

                                "email" ->
                                    { lf | email = value, duplicateConfirmed = False }

                                "phone" ->
                                    { lf | phone = value, duplicateConfirmed = False }

                                "nationality" ->
                                    { lf | nationality = value }

                                "currentCountry" ->
                                    { lf | currentCountry = value }

                                "interestedCountry" ->
                                    { lf | interestedCountry = value }

                                "interestedService" ->
                                    { lf | interestedService = value }

                                "source" ->
                                    { lf | source = value }

                                "assignedTo" ->
                                    { lf | assignedTo = value }

                                "status" ->
                                    { lf | status = value }

                                "followUpDate" ->
                                    { lf | followUpDate = value }

                                "notes" ->
                                    { lf | notes = value }

                                _ ->
                                    lf
                    in
                    ( { model
                        | leadForm =
                            Just
                                { updated
                                    | dirty = True
                                    , errors =
                                        List.filter (\( f, _ ) -> f /= field || field == "duplicateConfirmed") updated.errors
                                }
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        SubmittedLeadForm ->
            case ( model.leadForm, model.token ) of
                ( Just lf, Just token ) ->
                    let
                        ( validated, ok ) =
                            validateLeadForm lf
                    in
                    if not ok then
                        ( { model | leadForm = Just validated }, Cmd.none )

                    else
                        let
                            cmd =
                                case model.editingLeadId of
                                    Just id ->
                                        Api.updateLead token id validated GotSavedLead

                                    Nothing ->
                                        Api.createLead token validated GotSavedLead
                        in
                        ( { model | leadForm = Just { validated | submitting = True } }, cmd )

                _ ->
                    ( model, Cmd.none )

        GotSavedLead result ->
            case result of
                Ok lead ->
                    let
                        verb =
                            if model.editingLeadId /= Nothing then
                                "Updated "

                            else
                                "Added "

                        fresh =
                            { model
                                | leadForm = Nothing
                                , editingLeadId = Nothing
                                , viewingLead =
                                    case model.route of
                                        LeadDetail id ->
                                            if id == lead.id then
                                                Just lead

                                            else
                                                model.viewingLead

                                        _ ->
                                            model.viewingLead
                                , toast = Just (verb ++ lead.name)
                            }
                    in
                    ( fresh, Tuple.second (loadLeads fresh) )

                Err (FieldErrors fields) ->
                    case model.leadForm of
                        Just lf ->
                            ( { model | leadForm = Just { lf | submitting = False, errors = fields } }, Cmd.none )

                        Nothing ->
                            ( model, Cmd.none )

                Err (GenericError message) ->
                    case model.leadForm of
                        Just lf ->
                            ( { model
                                | leadForm =
                                    Just { lf | submitting = False, errors = [ ( "form", message ) ] }
                              }
                            , Cmd.none
                            )

                        Nothing ->
                            ( model, Cmd.none )

        RequestedDeleteLead lead ->
            ( { model | deletingLead = Just lead }, Cmd.none )

        CancelledDeleteLead ->
            ( { model | deletingLead = Nothing }, Cmd.none )

        ConfirmedDeleteLead ->
            case ( model.deletingLead, model.token ) of
                ( Just lead, Just token ) ->
                    ( model, Api.deleteLead token lead.id (GotDeletedLead lead.id lead.name) )

                _ ->
                    ( model, Cmd.none )

        GotDeletedLead deletedId name result ->
            case result of
                Ok _ ->
                    let
                        fresh =
                            { model
                                | deletingLead = Nothing
                                , viewingLead =
                                    case model.route of
                                        LeadDetail id ->
                                            if id == deletedId then
                                                Nothing

                                            else
                                                model.viewingLead

                                        _ ->
                                            model.viewingLead
                                , route =
                                    case model.route of
                                        LeadDetail id ->
                                            if id == deletedId then
                                                Leads

                                            else
                                                model.route

                                        _ ->
                                            model.route
                                , toast = Just ("Deleted " ++ name)
                            }
                    in
                    ( fresh, Tuple.second (loadLeads fresh) )

                Err message ->
                    ( { model
                        | deletingLead = Nothing
                        , toast = Just ("Delete failed: " ++ message)
                      }
                    , Cmd.none
                    )

        _ ->
            ( model, Cmd.none )
