module Update.Agents exposing (update)

{-| Agent messages.
-}

import Api
import Types exposing (..)
import Update.Loaders exposing (loadAgents, loadStudents, pageSize)
import Update.Navigation
import Update.Validate exposing (validateAgentForm)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotAgents result ->
            case result of
                Ok ( items, total ) ->
                    let
                        prev =
                            case model.agents of
                                Success d ->
                                    d

                                _ ->
                                    { items = [], query = "", total = 0, offset = 0, limit = pageSize }
                    in
                    ( { model
                        | agents =
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
                    ( { model | agents = Failure message }, Cmd.none )

        UpdatedAgentsQuery q ->
            let
                next =
                    case model.agents of
                        Success data ->
                            Success { data | query = q, offset = 0 }

                        _ ->
                            Success { items = [], query = q, total = 0, offset = 0, limit = pageSize }
            in
            ( { model | agents = next, pendingAgentsQuery = Just q }, Cmd.none )

        FlushAgentsSearch ->
            case ( model.token, model.pendingAgentsQuery ) of
                ( Just t, Just q ) ->
                    ( { model | pendingAgentsQuery = Nothing }
                    , Api.fetchAgents t q pageSize 0 GotAgents
                    )

                _ ->
                    ( { model | pendingAgentsQuery = Nothing }, Cmd.none )

        AgentsPageChanged newOffset ->
            case ( model.token, model.agents ) of
                ( Just t, Success data ) ->
                    ( { model | agents = Success { data | offset = newOffset } }
                    , Api.fetchAgents t data.query pageSize newOffset GotAgents
                    )

                _ ->
                    ( model, Cmd.none )

        OpenedAddAgent ->
            ( { model
                | agentForm = Just emptyAgentForm
                , editingAgentId = Nothing
                , toast = Nothing
              }
            , Cmd.none
            )

        OpenedEditAgent agent ->
            ( { model
                | agentForm = Just (agentToForm agent)
                , editingAgentId = Just agent.id
                , toast = Nothing
              }
            , Cmd.none
            )

        OpenedAgentDetail agent ->
            Update.Navigation.update (NavigatedTo (AgentDetail agent.id))
                { model | viewingAgent = Just agent, toast = Nothing }

        RequestedCloseAgentForm ->
            case ( model.agentForm, model.deletingAgent ) of
                ( _, Just _ ) ->
                    ( { model | deletingAgent = Nothing }, Cmd.none )

                ( Just af, _ ) ->
                    if af.dirty && not af.submitting then
                        ( { model | agentForm = Just { af | confirmDiscard = True } }, Cmd.none )

                    else
                        ( { model | agentForm = Nothing, editingAgentId = Nothing }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ConfirmedCloseAgentForm ->
            ( { model | agentForm = Nothing, editingAgentId = Nothing }, Cmd.none )

        CancelledCloseAgentForm ->
            case model.agentForm of
                Just af ->
                    ( { model | agentForm = Just { af | confirmDiscard = False } }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        UpdatedAgentFormField field value ->
            case model.agentForm of
                Just af ->
                    let
                        updated =
                            case field of
                                "name" ->
                                    { af | name = value }

                                "agentCode" ->
                                    { af | agentCode = value }

                                "countryCode" ->
                                    { af | countryCode = value }

                                "contractStatus" ->
                                    { af | contractStatus = value }

                                "agentStatus" ->
                                    { af | agentStatus = value }

                                "studentsReferred" ->
                                    { af | studentsReferred = value }

                                "notes" ->
                                    { af | notes = value }

                                _ ->
                                    af
                    in
                    ( { model
                        | agentForm =
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

        SubmittedAgentForm ->
            case ( model.agentForm, model.token ) of
                ( Just af, Just token ) ->
                    let
                        ( validated, ok ) =
                            validateAgentForm af
                    in
                    if not ok then
                        ( { model | agentForm = Just validated }, Cmd.none )

                    else
                        let
                            cmd =
                                case model.editingAgentId of
                                    Just id ->
                                        Api.updateAgent token id validated GotSavedAgent

                                    Nothing ->
                                        Api.createAgent token validated GotSavedAgent
                        in
                        ( { model | agentForm = Just { validated | submitting = True } }, cmd )

                _ ->
                    ( model, Cmd.none )

        GotSavedAgent result ->
            case result of
                Ok agent ->
                    let
                        verb =
                            if model.editingAgentId /= Nothing then
                                "Updated "

                            else
                                "Added "

                        fresh =
                            { model
                                | agentForm = Nothing
                                , editingAgentId = Nothing
                                , viewingAgent =
                                    case model.route of
                                        AgentDetail id ->
                                            if id == agent.id then
                                                Just agent

                                            else
                                                model.viewingAgent

                                        _ ->
                                            model.viewingAgent
                                , toast = Just (verb ++ agent.name)
                            }
                    in
                    ( fresh, Tuple.second (loadAgents fresh) )

                Err (FieldErrors fields) ->
                    case model.agentForm of
                        Just af ->
                            ( { model | agentForm = Just { af | submitting = False, errors = fields } }, Cmd.none )

                        Nothing ->
                            ( model, Cmd.none )

                Err (GenericError message) ->
                    case model.agentForm of
                        Just af ->
                            ( { model
                                | agentForm =
                                    Just { af | submitting = False, errors = [ ( "form", message ) ] }
                              }
                            , Cmd.none
                            )

                        Nothing ->
                            ( model, Cmd.none )

        RequestedDeleteAgent agent ->
            ( { model | deletingAgent = Just agent }, Cmd.none )

        CancelledDeleteAgent ->
            ( { model | deletingAgent = Nothing }, Cmd.none )

        ConfirmedDeleteAgent ->
            case ( model.deletingAgent, model.token ) of
                ( Just agent, Just token ) ->
                    ( model, Api.deleteAgent token agent.id (GotDeletedAgent agent.id agent.name) )

                _ ->
                    ( model, Cmd.none )

        GotDeletedAgent deletedId name result ->
            case result of
                Ok _ ->
                    let
                        fresh =
                            { model
                                | deletingAgent = Nothing
                                , viewingAgent =
                                    case model.route of
                                        AgentDetail id ->
                                            if id == deletedId then
                                                Nothing

                                            else
                                                model.viewingAgent

                                        _ ->
                                            model.viewingAgent
                                , route =
                                    case model.route of
                                        AgentDetail id ->
                                            if id == deletedId then
                                                Agents

                                            else
                                                model.route

                                        _ ->
                                            model.route
                                , toast = Just ("Deleted " ++ name)
                            }
                    in
                    ( fresh
                    , Cmd.batch
                        [ Tuple.second (loadAgents fresh)
                        , Tuple.second (loadStudents fresh)
                        ]
                    )

                Err message ->
                    ( { model
                        | deletingAgent = Nothing
                        , toast = Just ("Delete failed: " ++ message)
                      }
                    , Cmd.none
                    )

        _ ->
            ( model, Cmd.none )
