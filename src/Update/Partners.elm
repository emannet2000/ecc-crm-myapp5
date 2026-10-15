module Update.Partners exposing (update)

import Api
import Types exposing (..)
import Update.Loaders exposing (loadPartners, pageSize)
import Update.Navigation


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotPartners result ->
            case result of
                Ok ( items, total ) ->
                    let
                        prev =
                            case model.partners of
                                Success d ->
                                    d

                                _ ->
                                    { items = [], query = "", typeFilter = "", countryFilter = "", total = 0, offset = 0, limit = pageSize }
                    in
                    ( { model
                        | partners =
                            Success
                                { items = items
                                , query = prev.query
                                , typeFilter = prev.typeFilter
                                , countryFilter = prev.countryFilter
                                , total = total
                                , offset = prev.offset
                                , limit = pageSize
                                }
                      }
                    , Cmd.none
                    )

                Err message ->
                    ( { model | partners = Failure message }, Cmd.none )

        UpdatedPartnersQuery q ->
            let
                next =
                    case model.partners of
                        Success data ->
                            Success { data | query = q, offset = 0 }

                        _ ->
                            Success { items = [], query = q, typeFilter = "", countryFilter = "", total = 0, offset = 0, limit = pageSize }
            in
            ( { model | partners = next, pendingPartnersQuery = Just q }, Cmd.none )

        UpdatedPartnersTypeFilter t ->
            case model.token of
                Just tok ->
                    let
                        ( q, country, next ) =
                            case model.partners of
                                Success data ->
                                    ( data.query, data.countryFilter, Success { data | typeFilter = t, offset = 0 } )

                                _ ->
                                    ( "", "", Success { items = [], query = "", typeFilter = t, countryFilter = "", total = 0, offset = 0, limit = pageSize } )
                    in
                    ( { model | partners = next }
                    , Api.fetchPartners tok q t country pageSize 0 GotPartners
                    )

                Nothing ->
                    ( model, Cmd.none )

        UpdatedPartnersCountryFilter c ->
            case model.token of
                Just tok ->
                    let
                        ( q, ptype, next ) =
                            case model.partners of
                                Success data ->
                                    ( data.query, data.typeFilter, Success { data | countryFilter = c, offset = 0 } )

                                _ ->
                                    ( "", "", Success { items = [], query = "", typeFilter = "", countryFilter = c, total = 0, offset = 0, limit = pageSize } )
                    in
                    ( { model | partners = next }
                    , Api.fetchPartners tok q ptype c pageSize 0 GotPartners
                    )

                Nothing ->
                    ( model, Cmd.none )

        FlushPartnersSearch ->
            case ( model.token, model.pendingPartnersQuery ) of
                ( Just t, Just q ) ->
                    let
                        ( ptype, country ) =
                            case model.partners of
                                Success d ->
                                    ( d.typeFilter, d.countryFilter )

                                _ ->
                                    ( "", "" )
                    in
                    ( { model | pendingPartnersQuery = Nothing }
                    , Api.fetchPartners t q ptype country pageSize 0 GotPartners
                    )

                _ ->
                    ( { model | pendingPartnersQuery = Nothing }, Cmd.none )

        PartnersPageChanged newOffset ->
            case ( model.token, model.partners ) of
                ( Just t, Success data ) ->
                    ( { model | partners = Success { data | offset = newOffset } }
                    , Api.fetchPartners t data.query data.typeFilter data.countryFilter pageSize newOffset GotPartners
                    )

                _ ->
                    ( model, Cmd.none )

        OpenedAddPartner ->
            ( { model | partnerForm = Just emptyPartnerForm, editingPartnerId = Nothing, toast = Nothing }, Cmd.none )

        OpenedEditPartner p ->
            ( { model | partnerForm = Just (partnerToForm p), editingPartnerId = Just p.id, toast = Nothing }, Cmd.none )

        OpenedPartnerDetail p ->
            Update.Navigation.update (NavigatedTo (PartnerDetail p.id))
                { model | viewingPartner = Just p, toast = Nothing }

        RequestedClosePartnerForm ->
            case ( model.partnerForm, model.deletingPartner ) of
                ( _, Just _ ) ->
                    ( { model | deletingPartner = Nothing }, Cmd.none )

                ( Just pf, _ ) ->
                    if pf.dirty && not pf.submitting then
                        ( { model | partnerForm = Just { pf | confirmDiscard = True } }, Cmd.none )

                    else
                        ( { model | partnerForm = Nothing, editingPartnerId = Nothing }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ConfirmedClosePartnerForm ->
            ( { model | partnerForm = Nothing, editingPartnerId = Nothing }, Cmd.none )

        CancelledClosePartnerForm ->
            case model.partnerForm of
                Just pf ->
                    ( { model | partnerForm = Just { pf | confirmDiscard = False } }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        UpdatedPartnerFormField field value ->
            case model.partnerForm of
                Just pf ->
                    let
                        updated =
                            case field of
                                "type" ->
                                    { pf | type_ = value }

                                "legalCompanyName" ->
                                    { pf | legalCompanyName = value }

                                "country" ->
                                    { pf | country = value }

                                "licenseNumber" ->
                                    { pf | licenseNumber = value }

                                "licenseExpiry" ->
                                    { pf | licenseExpiry = value }

                                "verificationSource" ->
                                    { pf | verificationSource = value }

                                "contactPerson" ->
                                    { pf | contactPerson = value }

                                "contactEmail" ->
                                    { pf | contactEmail = value }

                                "contactPhone" ->
                                    { pf | contactPhone = value }

                                "agreementStart" ->
                                    { pf | agreementStart = value }

                                "agreementExpiry" ->
                                    { pf | agreementExpiry = value }

                                "servicesPermitted" ->
                                    { pf | servicesPermitted = value }

                                "commissionStructure" ->
                                    { pf | commissionStructure = value }

                                "paymentTerms" ->
                                    { pf | paymentTerms = value }

                                "casesReferred" ->
                                    { pf | casesReferred = value }

                                "casesConverted" ->
                                    { pf | casesConverted = value }

                                "amountPayable" ->
                                    { pf | amountPayable = value }

                                "complianceNotes" ->
                                    { pf | complianceNotes = value }

                                "notes" ->
                                    { pf | notes = value }

                                _ ->
                                    pf
                    in
                    ( { model
                        | partnerForm =
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

        SubmittedPartnerForm ->
            case ( model.partnerForm, model.token ) of
                ( Just pf, Just token ) ->
                    let
                        errs =
                            if String.isEmpty (String.trim pf.legalCompanyName) then
                                [ ( "legalCompanyName", "Legal company name is required." ) ]

                            else
                                []
                    in
                    if not (List.isEmpty errs) then
                        ( { model | partnerForm = Just { pf | errors = errs } }, Cmd.none )

                    else
                        let
                            cmd =
                                case model.editingPartnerId of
                                    Just id ->
                                        Api.updatePartner token id pf GotSavedPartner

                                    Nothing ->
                                        Api.createPartner token pf GotSavedPartner
                        in
                        ( { model | partnerForm = Just { pf | submitting = True, errors = [] } }, cmd )

                _ ->
                    ( model, Cmd.none )

        GotSavedPartner result ->
            case result of
                Ok p ->
                    let
                        verb =
                            if model.editingPartnerId /= Nothing then
                                "Updated "

                            else
                                "Added "

                        fresh =
                            { model
                                | partnerForm = Nothing
                                , editingPartnerId = Nothing
                                , viewingPartner =
                                    case model.route of
                                        PartnerDetail id ->
                                            if id == p.id then
                                                Just p

                                            else
                                                model.viewingPartner

                                        _ ->
                                            model.viewingPartner
                                , toast = Just (verb ++ p.legalCompanyName)
                            }
                    in
                    ( fresh, Tuple.second (loadPartners fresh) )

                Err (FieldErrors fields) ->
                    case model.partnerForm of
                        Just pf ->
                            ( { model | partnerForm = Just { pf | submitting = False, errors = fields } }, Cmd.none )

                        Nothing ->
                            ( model, Cmd.none )

                Err (GenericError message) ->
                    case model.partnerForm of
                        Just pf ->
                            ( { model
                                | partnerForm =
                                    Just { pf | submitting = False, errors = [ ( "form", message ) ] }
                              }
                            , Cmd.none
                            )

                        Nothing ->
                            ( model, Cmd.none )

        RequestedDeletePartner p ->
            ( { model | deletingPartner = Just p }, Cmd.none )

        CancelledDeletePartner ->
            ( { model | deletingPartner = Nothing }, Cmd.none )

        ConfirmedDeletePartner ->
            case ( model.deletingPartner, model.token ) of
                ( Just p, Just token ) ->
                    ( model, Api.deletePartner token p.id (GotDeletedPartner p.id p.legalCompanyName) )

                _ ->
                    ( model, Cmd.none )

        GotDeletedPartner deletedId name result ->
            case result of
                Ok _ ->
                    let
                        fresh =
                            { model
                                | deletingPartner = Nothing
                                , viewingPartner =
                                    case model.route of
                                        PartnerDetail id ->
                                            if id == deletedId then
                                                Nothing

                                            else
                                                model.viewingPartner

                                        _ ->
                                            model.viewingPartner
                                , route =
                                    case model.route of
                                        PartnerDetail id ->
                                            if id == deletedId then
                                                Partners

                                            else
                                                model.route

                                        _ ->
                                            model.route
                                , toast = Just ("Deleted " ++ name)
                            }
                    in
                    ( fresh, Tuple.second (loadPartners fresh) )

                Err message ->
                    ( { model
                        | deletingPartner = Nothing
                        , toast = Just ("Delete failed: " ++ message)
                      }
                    , Cmd.none
                    )

        _ ->
            ( model, Cmd.none )
