module Update.Tasks exposing (update)

{-| Task messages.
-}

import Api
import Types exposing (..)
import Update.Loaders exposing (loadTasks)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ChangedTasksPage offset ->
            loadTasks { model | taskOffset = max 0 offset }

        GotTasks result ->
            case result of
                Ok ( items, total ) ->
                    let
                        ( prevQ, prevSt ) =
                            case model.tasks of
                                Success d ->
                                    ( d.query, d.statusFilter )

                                _ ->
                                    ( "", "" )
                    in
                    ( { model
                        | tasks =
                            Success
                                { items = items
                                , query = prevQ
                                , statusFilter = prevSt
                                , total = total
                                }
                      }
                    , Cmd.none
                    )

                Err message ->
                    ( { model | tasks = Failure message }, Cmd.none )

        UpdatedTasksQuery q ->
            let
                next =
                    case model.tasks of
                        Success data ->
                            Success { data | query = q }

                        _ ->
                            Success { items = [], query = q, statusFilter = "", total = 0 }
            in
            ( { model | tasks = next, taskOffset = 0, pendingTasksQuery = Just q }, Cmd.none )

        FlushTasksSearch ->
            case ( model.token, model.pendingTasksQuery ) of
                ( Just t, Just q ) ->
                    let
                        st =
                            case model.tasks of
                                Success d ->
                                    d.statusFilter

                                _ ->
                                    ""
                    in
                    ( { model | pendingTasksQuery = Nothing }
                    , Api.fetchTasks t q st GotTasks
                    )

                _ ->
                    ( { model | pendingTasksQuery = Nothing }, Cmd.none )

        UpdatedTasksStatusFilter status ->
            case model.token of
                Just t ->
                    let
                        q =
                            case model.tasks of
                                Success d ->
                                    d.query

                                _ ->
                                    ""

                        next =
                            case model.tasks of
                                Success data ->
                                    Success { data | statusFilter = status }

                                _ ->
                                    Success { items = [], query = q, statusFilter = status, total = 0 }
                    in
                    ( { model | tasks = next, taskOffset = 0 }
                    , Api.fetchTasks t q status GotTasks
                    )

                Nothing ->
                    ( model, Cmd.none )

        OpenedAddTask ->
            ( { model | taskForm = Just emptyTaskForm, editingTaskId = Nothing, toast = Nothing }, Cmd.none )

        OpenedAddTaskForContact contact ->
            ( { model
                | taskForm = Just { emptyTaskForm | contactId = contact.id }
                , editingTaskId = Nothing
                , toast = Nothing
              }
            , Cmd.none
            )

        OpenedEditTask task ->
            ( { model | taskForm = Just (taskToForm task), editingTaskId = Just task.id, toast = Nothing }, Cmd.none )

        RequestedCloseTaskForm ->
            case ( model.taskForm, model.deletingTask ) of
                ( _, Just _ ) ->
                    ( { model | deletingTask = Nothing }, Cmd.none )

                ( Just tf, _ ) ->
                    if tf.dirty && not tf.submitting then
                        ( { model | taskForm = Just { tf | confirmDiscard = True } }, Cmd.none )

                    else
                        ( { model | taskForm = Nothing, editingTaskId = Nothing }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ConfirmedCloseTaskForm ->
            ( { model | taskForm = Nothing, editingTaskId = Nothing }, Cmd.none )

        CancelledCloseTaskForm ->
            case model.taskForm of
                Just tf ->
                    ( { model | taskForm = Just { tf | confirmDiscard = False } }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        UpdatedTaskFormField field value ->
            case model.taskForm of
                Just tf ->
                    let
                        updated =
                            case field of
                                "title" ->
                                    { tf | title = value }

                                "description" ->
                                    { tf | description = value }

                                "status" ->
                                    { tf | status = value }

                                "dueDate" ->
                                    { tf | dueDate = value }

                                "contactId" ->
                                    { tf | contactId = value }

                                "owner" ->
                                    { tf | owner = value }

                                _ ->
                                    tf
                    in
                    ( { model
                        | taskForm =
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

        SubmittedTaskForm ->
            case ( model.taskForm, model.token ) of
                ( Just tf, Just token ) ->
                    let
                        errs =
                            if String.isEmpty (String.trim tf.title) then
                                [ ( "title", "Title is required." ) ]

                            else
                                []

                        validated =
                            { tf | errors = errs }
                    in
                    if not (List.isEmpty errs) then
                        ( { model | taskForm = Just validated }, Cmd.none )

                    else
                        let
                            cmd =
                                case model.editingTaskId of
                                    Just id ->
                                        Api.updateTask token id validated GotSavedTask

                                    Nothing ->
                                        Api.createTask token validated GotSavedTask
                        in
                        ( { model | taskForm = Just { validated | submitting = True } }, cmd )

                _ ->
                    ( model, Cmd.none )

        GotSavedTask result ->
            case result of
                Ok task ->
                    let
                        verb =
                            if model.editingTaskId /= Nothing then
                                "Updated "

                            else
                                "Added "

                        fresh =
                            { model | taskForm = Nothing, editingTaskId = Nothing, toast = Just (verb ++ task.title) }
                    in
                    ( fresh, Tuple.second (loadTasks fresh) )

                Err (FieldErrors fields) ->
                    case model.taskForm of
                        Just tf ->
                            ( { model | taskForm = Just { tf | submitting = False, errors = fields } }, Cmd.none )

                        Nothing ->
                            ( model, Cmd.none )

                Err (GenericError message) ->
                    case model.taskForm of
                        Just tf ->
                            ( { model | taskForm = Just { tf | submitting = False, errors = [ ( "form", message ) ] } }, Cmd.none )

                        Nothing ->
                            ( model, Cmd.none )

        ToggledTaskStatus task newStatus ->
            case model.token of
                Just token ->
                    ( model, Api.updateTaskStatus token task.id newStatus GotToggledTask )

                Nothing ->
                    ( model, Cmd.none )

        GotToggledTask result ->
            case result of
                Ok task ->
                    let
                        fresh =
                            { model | toast = Just (task.title ++ " → " ++ task.status) }
                    in
                    ( fresh, Tuple.second (loadTasks fresh) )

                Err err ->
                    let
                        message =
                            case err of
                                FieldErrors _ ->
                                    "Could not update task."

                                GenericError m ->
                                    m
                    in
                    ( { model | toast = Just message }, Cmd.none )

        RequestedDeleteTask task ->
            ( { model | deletingTask = Just task }, Cmd.none )

        CancelledDeleteTask ->
            ( { model | deletingTask = Nothing }, Cmd.none )

        ConfirmedDeleteTask ->
            case ( model.deletingTask, model.token ) of
                ( Just task, Just token ) ->
                    ( model, Api.deleteTask token task.id (GotDeletedTask task.id task.title) )

                _ ->
                    ( model, Cmd.none )

        GotDeletedTask deletedId name result ->
            case result of
                Ok _ ->
                    let
                        fresh =
                            { model | deletingTask = Nothing, toast = Just ("Deleted " ++ name) }
                    in
                    ( fresh, Tuple.second (loadTasks fresh) )

                Err message ->
                    ( { model | deletingTask = Nothing, toast = Just ("Delete failed: " ++ message) }, Cmd.none )

        _ ->
            ( model, Cmd.none )
