module Update.Deals exposing (update)

{-| Deal messages (pipeline, drag/drop, bulk actions).
-}

import Api
import Set
import Types exposing (..)
import Update.Loaders exposing (loadDeals, pageSize)
import Update.Navigation
import Update.Validate exposing (validateDealForm)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        RefreshDeals ->
            loadDeals { model | dealsRequestId = model.dealsRequestId + 1, pendingDealsQuery = Nothing, selectedDeals = Set.empty }

        LoadMoreDeals ->
            case ( model.token, model.deals ) of
                ( Just token, Success data ) ->
                    if data.loadingMore || model.pendingDealsQuery /= Nothing || List.length data.items >= data.total then
                        ( model, Cmd.none )

                    else
                        ( { model | deals = Success { data | loadingMore = True } }
                        , Api.fetchDeals token data.query model.ownerFilter model.dateFromFilter model.dateToFilter data.snapshot data.limit (List.length data.items) (GotDealsAt model.dealsRequestId data.query True)
                        )

                _ ->
                    ( model, Cmd.none )

        GotDealsAt requestId query append result ->
            if requestId /= model.dealsRequestId then
                ( model, Cmd.none )

            else
                case result of
                    Ok data ->
                        let
                            items =
                                case ( append, model.deals ) of
                                    ( True, Success old ) ->
                                        old.items ++ data.items

                                    _ ->
                                        data.items
                        in
                        ( { model | deals = Success { data | items = items, query = query, loadingMore = False } }, Cmd.none )

                    Err message ->
                        if append then
                            case model.deals of
                                Success data ->
                                    ( { model | deals = Success { data | loadingMore = False }, toast = Just message }, Cmd.none )

                                _ ->
                                    ( model, Cmd.none )

                        else
                            ( { model | deals = Failure message }, Cmd.none )

        GotDeals result ->
            case result of
                Ok data ->
                    ( { model | deals = Success data }, Cmd.none )

                Err message ->
                    ( { model | deals = Failure message }, Cmd.none )

        UpdatedDealsQuery q ->
            let
                nextDeals =
                    case model.deals of
                        Success data ->
                            Success { data | query = q, offset = 0 }

                        _ ->
                            Success (emptyDealsData q)
            in
            ( { model | selectedDeals = Set.empty, deals = nextDeals, pendingDealsQuery = Just q, dealsRequestId = model.dealsRequestId + 1 }
            , Cmd.none
            )

        FlushDealsSearch ->
            case ( model.token, model.pendingDealsQuery ) of
                ( Just t, Just q ) ->
                    ( { model | pendingDealsQuery = Nothing }
                    , Api.fetchDeals t q model.ownerFilter model.dateFromFilter model.dateToFilter "" 50 0 (GotDealsAt model.dealsRequestId q False)
                    )

                _ ->
                    ( { model | pendingDealsQuery = Nothing }, Cmd.none )

        OpenedAddDeal ->
            ( { model
                | dealForm = Just emptyDealForm
                , editingDealId = Nothing
                , toast = Nothing
              }
            , Cmd.none
            )

        OpenedAddDealForContact contact ->
            ( { model
                | dealForm = Just { emptyDealForm | contactId = contact.id }
                , editingDealId = Nothing
                , toast = Nothing
              }
            , Cmd.none
            )

        OpenedAddDealWithStage stage ->
            ( { model
                | dealForm = Just { emptyDealForm | stage = stage }
                , editingDealId = Nothing
                , toast = Nothing
              }
            , Cmd.none
            )

        OpenedEditDeal deal ->
            ( { model
                | dealForm = Just (dealToForm deal)
                , editingDealId = Just deal.id
                , toast = Nothing
              }
            , Cmd.none
            )

        OpenedDealDetail deal ->
            Update.Navigation.update (NavigatedTo (DealDetail deal.id))
                { model | viewingDeal = Just deal, toast = Nothing }

        RequestedCloseDealForm ->
            case ( model.dealForm, model.deletingDeal ) of
                ( _, Just _ ) ->
                    ( { model | deletingDeal = Nothing }, Cmd.none )

                ( Just df, _ ) ->
                    if df.dirty && not df.submitting then
                        ( { model | dealForm = Just { df | confirmDiscard = True } }
                        , Cmd.none
                        )

                    else
                        ( { model | dealForm = Nothing, editingDealId = Nothing }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ConfirmedCloseDealForm ->
            ( { model | dealForm = Nothing, editingDealId = Nothing }, Cmd.none )

        CancelledCloseDealForm ->
            case model.dealForm of
                Just df ->
                    ( { model | dealForm = Just { df | confirmDiscard = False } }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        UpdatedDealFormField field value ->
            case model.dealForm of
                Just df ->
                    let
                        updated =
                            case field of
                                "title" ->
                                    { df | title = value }

                                "contactId" ->
                                    { df | contactId = value }

                                "value" ->
                                    { df | value = value }

                                "currency" ->
                                    { df | currency = value }

                                "stage" ->
                                    { df | stage = value }

                                "closeDate" ->
                                    { df | closeDate = value }

                                "owner" ->
                                    { df | owner = value }

                                "notes" ->
                                    { df | notes = value }

                                _ ->
                                    df
                    in
                    ( { model
                        | dealForm =
                            Just
                                { updated
                                    | dirty = True
                                    , errors =
                                        List.filter (\( f, _ ) -> f /= field) updated.errors
                                }
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        SubmittedDealForm ->
            case ( model.dealForm, model.token ) of
                ( Just df, Just token ) ->
                    let
                        ( validated, ok ) =
                            validateDealForm df
                    in
                    if not ok then
                        ( { model | dealForm = Just validated }, Cmd.none )

                    else
                        let
                            cmd =
                                case model.editingDealId of
                                    Just id ->
                                        Api.updateDeal token id validated GotSavedDeal

                                    Nothing ->
                                        Api.createDeal token validated GotSavedDeal
                        in
                        ( { model
                            | dealForm = Just { validated | submitting = True }
                          }
                        , cmd
                        )

                _ ->
                    ( model, Cmd.none )

        GotSavedDeal result ->
            let
                wasEdit =
                    model.editingDealId /= Nothing

                verb =
                    if wasEdit then
                        "Updated "

                    else
                        "Added "
            in
            case result of
                Ok deal ->
                    let
                        freshModel =
                            { model
                                | dealForm = Nothing
                                , editingDealId = Nothing
                                , viewingDeal =
                                    case model.route of
                                        DealDetail id ->
                                            if id == deal.id then
                                                Just deal

                                            else
                                                model.viewingDeal

                                        _ ->
                                            model.viewingDeal
                                , toast = Just (verb ++ deal.title)
                            }
                    in
                    ( freshModel, Tuple.second (loadDeals freshModel) )

                Err (FieldErrors fields) ->
                    case model.dealForm of
                        Just df ->
                            ( { model
                                | dealForm =
                                    Just { df | submitting = False, errors = fields }
                              }
                            , Cmd.none
                            )

                        Nothing ->
                            ( model, Cmd.none )

                Err (GenericError message) ->
                    case model.dealForm of
                        Just df ->
                            ( { model
                                | dealForm =
                                    Just
                                        { df
                                            | submitting = False
                                            , errors = [ ( "form", message ) ]
                                        }
                              }
                            , Cmd.none
                            )

                        Nothing ->
                            ( model, Cmd.none )

        MovedDeal deal newStage ->
            case model.token of
                Just token ->
                    ( { model | movingDealId = Just deal.id }
                    , Api.updateDealStage token deal.id newStage GotMovedDeal
                    )

                Nothing ->
                    ( model, Cmd.none )

        GotMovedDeal result ->
            case result of
                Ok deal ->
                    let
                        freshModel =
                            { model
                                | movingDealId = Nothing
                                , viewingDeal =
                                    case model.route of
                                        DealDetail id ->
                                            if id == deal.id then
                                                Just deal

                                            else
                                                model.viewingDeal

                                        _ ->
                                            model.viewingDeal
                                , toast = Just (deal.title ++ " moved to " ++ deal.stage)
                            }
                    in
                    ( freshModel, Tuple.second (loadDeals freshModel) )

                Err err ->
                    let
                        message =
                            case err of
                                FieldErrors _ ->
                                    "Could not move deal."

                                GenericError m ->
                                    m
                    in
                    ( { model | movingDealId = Nothing, toast = Just message }, Cmd.none )

        RequestedDeleteDeal deal ->
            ( { model | deletingDeal = Just deal }, Cmd.none )

        CancelledDeleteDeal ->
            ( { model | deletingDeal = Nothing }, Cmd.none )

        ConfirmedDeleteDeal ->
            case ( model.deletingDeal, model.token ) of
                ( Just deal, Just token ) ->
                    ( model, Api.deleteDeal token deal.id (GotDeletedDeal deal.id deal.title) )

                _ ->
                    ( model, Cmd.none )

        GotDeletedDeal deletedId name result ->
            case result of
                Ok _ ->
                    let
                        backToDeals =
                            case model.route of
                                DealDetail id ->
                                    id == deletedId

                                _ ->
                                    False

                        freshModel =
                            { model
                                | deletingDeal = Nothing
                                , dealForm = Nothing
                                , editingDealId = Nothing
                                , viewingDeal =
                                    if backToDeals then
                                        Nothing

                                    else
                                        model.viewingDeal
                                , route =
                                    if backToDeals then
                                        Deals

                                    else
                                        model.route
                                , toast = Just ("Deleted " ++ name)
                            }
                    in
                    ( freshModel, Tuple.second (loadDeals freshModel) )

                Err message ->
                    ( { model
                        | deletingDeal = Nothing
                        , toast = Just ("Delete failed: " ++ message)
                      }
                    , Cmd.none
                    )

        DraggingDealStarted id ->
            ( { model | draggingDealId = Just id }, Cmd.none )

        DraggingDealEnded ->
            ( { model
                | draggingDealId = Nothing
                , dropTargetStage = Nothing
              }
            , Cmd.none
            )

        DropTargetEntered stageName ->
            ( { model | dropTargetStage = Just stageName }, Cmd.none )

        DropTargetLeft ->
            ( { model | dropTargetStage = Nothing }, Cmd.none )

        DealDroppedOnStage stageName ->
            case ( model.draggingDealId, model.token, model.deals ) of
                ( Just dealId, Just token, Success dealsData ) ->
                    case List.filter (\d -> d.id == dealId) dealsData.items |> List.head of
                        Just deal ->
                            if deal.stage == stageName then
                                ( { model
                                    | draggingDealId = Nothing
                                    , dropTargetStage = Nothing
                                  }
                                , Cmd.none
                                )

                            else
                                ( { model
                                    | draggingDealId = Nothing
                                    , dropTargetStage = Nothing
                                    , movingDealId = Just dealId
                                  }
                                , Api.updateDealStage token dealId stageName GotMovedDeal
                                )

                        Nothing ->
                            ( { model | draggingDealId = Nothing, dropTargetStage = Nothing }, Cmd.none )

                _ ->
                    ( { model | draggingDealId = Nothing, dropTargetStage = Nothing }, Cmd.none )

        ToggledDealSelection dealId ->
            let
                newSelection =
                    if Set.member dealId model.selectedDeals then
                        Set.remove dealId model.selectedDeals

                    else
                        Set.insert dealId model.selectedDeals
            in
            ( { model | selectedDeals = newSelection }, Cmd.none )

        ToggledSelectAllDeals ->
            case model.deals of
                Success data ->
                    let
                        allIds =
                            List.map .id data.items

                        allSelected =
                            List.all (\id -> Set.member id model.selectedDeals) allIds
                    in
                    if allSelected then
                        ( { model | selectedDeals = Set.empty }, Cmd.none )

                    else
                        ( { model | selectedDeals = Set.fromList allIds }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ClearedDealSelection ->
            ( { model | selectedDeals = Set.empty }, Cmd.none )

        UpdatedOwnerFilter owner ->
            loadDeals { model | selectedDeals = Set.empty, ownerFilter = owner, dealsRequestId = model.dealsRequestId + 1, pendingDealsQuery = Nothing }

        UpdatedDateFromFilter date ->
            loadDeals { model | selectedDeals = Set.empty, dateFromFilter = date, dealsRequestId = model.dealsRequestId + 1, pendingDealsQuery = Nothing }

        UpdatedDateToFilter date ->
            loadDeals { model | selectedDeals = Set.empty, dateToFilter = date, dealsRequestId = model.dealsRequestId + 1, pendingDealsQuery = Nothing }

        ClearedDealFilters ->
            loadDeals { model | selectedDeals = Set.empty, ownerFilter = "", dateFromFilter = "", dateToFilter = "", dealsRequestId = model.dealsRequestId + 1, pendingDealsQuery = Nothing }

        RequestedBulkMove stageName ->
            ( { model
                | bulkMoveStage =
                    Just
                        (if String.isEmpty stageName then
                            "Qualified"

                         else
                            stageName
                        )
              }
            , Cmd.none
            )

        CancelledBulkMove ->
            ( { model | bulkMoveStage = Nothing }, Cmd.none )

        ConfirmedBulkMove ->
            case ( model.token, model.bulkMoveStage ) of
                ( Just token, Just stageName ) ->
                    if String.isEmpty stageName then
                        ( model, Cmd.none )

                    else
                        let
                            ids =
                                Set.toList model.selectedDeals
                        in
                        ( { model | bulkMoveStage = Nothing }
                        , Api.bulkMoveDeals token ids stageName (GotBulkMoved ids)
                        )

                _ ->
                    ( { model | bulkMoveStage = Nothing }, Cmd.none )

        RequestedBulkDelete ->
            ( { model | bulkDeleteConfirm = True }, Cmd.none )

        CancelledBulkDelete ->
            ( { model | bulkDeleteConfirm = False }, Cmd.none )

        ConfirmedBulkDelete ->
            case model.token of
                Just token ->
                    let
                        ids =
                            Set.toList model.selectedDeals
                    in
                    ( { model | bulkDeleteConfirm = False }
                    , Api.bulkDeleteDeals token ids (GotBulkDeleted ids)
                    )

                Nothing ->
                    ( { model | bulkDeleteConfirm = False }, Cmd.none )

        GotBulkMoved ids result ->
            let
                n =
                    List.length ids

                msgText =
                    case result of
                        Ok _ ->
                            "Moved "
                                ++ String.fromInt n
                                ++ " deal"
                                ++ (if n == 1 then
                                        ""

                                    else
                                        "s"
                                   )

                        Err _ ->
                            "Move rejected. Refresh and review the selected deals before retrying."

                freshModel =
                    { model
                        | selectedDeals =
                            case result of
                                Ok _ -> Set.diff model.selectedDeals (Set.fromList ids)
                                Err _ -> model.selectedDeals
                        , movingDealId = Nothing
                        , toast = Just msgText
                    }
            in
            ( freshModel, Tuple.second (loadDeals freshModel) )

        GotBulkDeleted ids result ->
            let
                n =
                    List.length ids

                msgText =
                    case result of
                        Ok _ ->
                            "Deleted "
                                ++ String.fromInt n
                                ++ " deal"
                                ++ (if n == 1 then
                                        ""

                                    else
                                        "s"
                                   )

                        Err _ ->
                            "Delete rejected. Refresh and review the selected deals before retrying."

                freshModel =
                    { model
                        | selectedDeals =
                            case result of
                                Ok _ -> Set.diff model.selectedDeals (Set.fromList ids)
                                Err _ -> model.selectedDeals
                        , toast = Just msgText
                    }
            in
            ( freshModel, Tuple.second (loadDeals freshModel) )

        _ ->
            ( model, Cmd.none )
