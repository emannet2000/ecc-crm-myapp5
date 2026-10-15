module View.Agents exposing (agentDetailView, agentFormModal, agentsView, deleteAgentConfirmModal)

{-| Agents: list, detail, form.
-}

import Html exposing (..)
import Html.Attributes as Attr exposing (class, disabled, for, id, placeholder, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import Json.Decode as D
import Router exposing (routeToPath)
import Svg
import Types exposing (..)
import View.Helpers exposing (detailCard, detailEmpty, detailStat, infoRow, initials, paginationBar, svgIcon, svgPath)
import View.Icons exposing (iconBack, iconCalendar, iconContacts, iconDeals, iconEdit, iconPin, iconStudent, iconTrash, iconUserTiny)
import View.Students exposing (linkedStudentsView)


agentContractBadge : String -> Html Msg
agentContractBadge status =
    let
        cls =
            case String.toLower status of
                "signed" ->
                    "badge badge--success"

                "pending" ->
                    "badge badge--info"

                "not signed" ->
                    "badge badge--muted"

                _ ->
                    "badge"
    in
    span [ class cls ] [ text status ]


agentStatusBadge : String -> Html Msg
agentStatusBadge status =
    let
        cls =
            case String.toLower status of
                "active" ->
                    "badge badge--success"

                "inactive" ->
                    "badge badge--muted"

                _ ->
                    "badge"
    in
    span [ class cls ] [ text status ]


agentRow : Agent -> Html Msg
agentRow agent =
    tr [ class "contact-row" ]
        [ td []
            [ div [ class "contact-name-cell" ]
                [ div [ class "contact-avatar" ] [ text (initials agent.name) ]
                , div [ class "contact-name-info" ]
                    [ a [ class "contact-name record-link", Attr.href (routeToPath (AgentDetail agent.id)) ] [ text agent.name ]
                    , span [ class "contact-email" ]
                        [ text
                            (if String.isEmpty agent.agentCode then
                                agent.countryCode

                             else
                                agent.agentCode
                            )
                        ]
                    ]
                ]
            ]
        , td [] [ text agent.countryCode ]
        , td [] [ agentContractBadge agent.contractStatus ]
        , td [] [ agentStatusBadge agent.agentStatus ]
        , td [] [ text (String.fromInt agent.studentsReferred) ]
        , td [ class "contact-actions-cell" ]
            [ button
                [ class "row-action"
                , type_ "button"
                , Attr.title "Edit"
                , Attr.attribute "aria-label" ("Edit " ++ agent.name)
                , Html.Events.stopPropagationOn "click"
                    (D.succeed ( OpenedEditAgent agent, True ))
                ]
                [ iconEdit ]
            , button
                [ class "row-action row-action--danger"
                , type_ "button"
                , Attr.title "Delete"
                , Attr.attribute "aria-label" ("Delete " ++ agent.name)
                , Html.Events.stopPropagationOn "click"
                    (D.succeed ( RequestedDeleteAgent agent, True ))
                ]
                [ iconTrash ]
            ]
        ]


agentsSkeleton : Html Msg
agentsSkeleton =
    div []
        [ div [ class "page-toolbar" ]
            [ div [ class "page-toolbar__search" ]
                [ input [ type_ "text", placeholder "Search agents…", disabled True ] [] ]
            ]
        , div [ class "table-wrap" ]
            (List.repeat 5
                (div [ class "skeleton-row" ]
                    [ div [ class "skeleton-line skeleton-line--medium" ] []
                    , div [ class "skeleton-line skeleton-line--short" ] []
                    ]
                )
            )
        ]


agentsView : Model -> Html Msg
agentsView model =
    case model.agents of
        NotAsked ->
            agentsSkeleton

        Loading ->
            agentsSkeleton

        Failure msg ->
            div [ class "content__empty-block" ]
                [ text ("Could not load agents: " ++ msg), button [ class "ecc-btn ecc-btn--ghost ecc-btn--inline", onClick (NavigatedTo model.route) ] [ text "Retry" ] ]

        Success data ->
            let
                filtered =
                    data.items

                isQueryEmpty =
                    String.isEmpty (String.trim data.query)
            in
            div []
                [ div [ class "page-toolbar" ]
                    [ div [ class "page-toolbar__search" ]
                        [ svgIcon
                            [ Attr.attribute "viewBox" "0 0 24 24"
                            , Attr.attribute "width" "16"
                            , Attr.attribute "height" "16"
                            , Attr.attribute "fill" "none"
                            , Attr.attribute "stroke" "currentColor"
                            , Attr.attribute "stroke-width" "1.8"
                            , Attr.attribute "stroke-linecap" "round"
                            , Attr.attribute "stroke-linejoin" "round"
                            ]
                            [ Svg.node "circle"
                                [ Attr.attribute "cx" "11"
                                , Attr.attribute "cy" "11"
                                , Attr.attribute "r" "8"
                                ]
                                []
                            , svgPath "M21 21l-4.35-4.35"
                            ]
                        , input
                            [ type_ "search"
                            , Attr.attribute "aria-label" "Search agents"
                            , placeholder "Search agents…"
                            , value data.query
                            , onInput UpdatedAgentsQuery
                            ]
                            []
                        ]
                    , button
                        [ class "ecc-btn ecc-btn--inline"
                        , type_ "button"
                        , onClick OpenedAddAgent
                        ]
                        [ text "Add agent" ]
                    ]
                , if List.isEmpty filtered then
                    div [ class "empty-state" ]
                        [ h3 [ class "empty-state__title" ]
                            [ text
                                (if isQueryEmpty then
                                    "No agents yet"

                                 else
                                    "No agents match your search"
                                )
                            ]
                        , p [ class "empty-state__desc" ]
                            [ text
                                (if isQueryEmpty then
                                    "Add your first agent to start tracking referrals."

                                 else
                                    "Try a different search term."
                                )
                            ]
                        , if isQueryEmpty then
                            div [ class "empty-state__action" ]
                                [ button
                                    [ class "ecc-btn ecc-btn--inline"
                                    , type_ "button"
                                    , onClick OpenedAddAgent
                                    ]
                                    [ text "Add your first agent" ]
                                ]

                          else
                            text ""
                        ]

                  else
                    div [ class "table-wrap" ]
                        [ table [ class "data-table" ]
                            [ thead []
                                [ tr []
                                    [ th [] [ text "Agent" ]
                                    , th [] [ text "Country" ]
                                    , th [] [ text "Contract" ]
                                    , th [] [ text "Status" ]
                                    , th [] [ text "Linked students" ]
                                    , th [ class "th-actions" ] [ text "" ]
                                    ]
                                ]
                            , tbody [] (List.map agentRow filtered)
                            ]
                        ]
                , paginationBar data.total data.offset data.limit AgentsPageChanged
                ]


agentDetailView : Model -> Agent -> Html Msg
agentDetailView model a =
    let
        display v =
            if String.isEmpty v then
                "—"

            else
                v

        codeDisplay =
            display a.agentCode

        countryDisplay =
            display a.countryCode

        createdDisplay =
            display a.createdAt

        ownerDisplay =
            display a.createdBy

        linkedCount =
            case model.linkedStudents of
                Success data ->
                    if data.parentId == a.id then
                        data.total

                    else
                        a.studentsReferred

                _ ->
                    a.studentsReferred
    in
    div [ class "detail" ]
        [ button
            [ class "detail__back"
            , type_ "button"
            , onClick (NavigatedTo Agents)
            ]
            [ iconBack
            , span [] [ text "Back to agents" ]
            ]
        , header [ class "detail-hero" ]
            [ div [ class "detail-hero__avatar" ] [ text (initials a.name) ]
            , div [ class "detail-hero__body" ]
                [ div [ class "detail-hero__title-row" ]
                    [ h1 [ class "detail-hero__name" ] [ text a.name ]
                    , agentStatusBadge a.agentStatus
                    ]
                , p [ class "detail-hero__role" ]
                    [ text (display a.countryCode) ]
                ]
            , div [ class "detail-hero__actions" ]
                [ button
                    [ class "ecc-btn ecc-btn--ghost ecc-btn--inline"
                    , type_ "button"
                    , onClick (OpenedEditAgent a)
                    ]
                    [ iconEdit
                    , span [] [ text "Edit" ]
                    ]
                , button
                    [ class "ecc-btn ecc-btn--danger ecc-btn--inline"
                    , type_ "button"
                    , onClick (RequestedDeleteAgent a)
                    ]
                    [ iconTrash
                    , span [] [ text "Delete" ]
                    ]
                ]
            ]
        , div [ class "detail-stats" ]
            [ detailStat "Contract" a.contractStatus "Agreement"
            , detailStat "Status" a.agentStatus "Current"
            , detailStat "Students referred"
                (String.fromInt linkedCount)
                "Linked student records"
            , detailStat "Country" countryDisplay "Location"
            ]
        , div [ class "detail__grid" ]
            [ aside [ class "detail__sidebar" ]
                [ detailCard "About"
                    Nothing
                    (div [ class "info-list" ]
                        [ infoRow iconUserTiny "Agent code" codeDisplay
                        , infoRow iconPin "Country" countryDisplay
                        , infoRow iconDeals "Contract" a.contractStatus
                        , infoRow iconCalendar "Created" createdDisplay
                        , infoRow iconContacts "Added by" ownerDisplay
                        ]
                    )
                , detailCard "Notes"
                    Nothing
                    (if String.isEmpty a.notes then
                        p [ class "detail-muted" ] [ text "No notes yet." ]

                     else
                        p [ class "detail-notes" ] [ text a.notes ]
                    )
                ]
            , div [ class "detail__main" ]
                [ detailCard "Referrals"
                    (Just
                        (button
                            [ class "detail-card__action"
                            , type_ "button"
                            , onClick (OpenedAddStudentForAgent a)
                            ]
                            [ text "Add referral" ]
                        )
                    )
                    (div []
                        [ linkedStudentsView model a.id
                        , button
                            [ class "ecc-btn ecc-btn--ghost ecc-btn--inline"
                            , type_ "button"
                            , onClick (NavigatedTo Students)
                            ]
                            [ text "Open students" ]
                        ]
                    )
                ]
            ]
        ]


agentFormFieldError : String -> AgentForm -> Maybe String
agentFormFieldError field af =
    af.errors
        |> List.filter (\( f, _ ) -> f == field)
        |> List.head
        |> Maybe.map Tuple.second


agentRichField : AgentForm -> String -> String -> String -> Html Msg
agentRichField af fieldId labelText inputType =
    let
        currentValue =
            case fieldId of
                "name" ->
                    af.name

                "agentCode" ->
                    af.agentCode

                "countryCode" ->
                    af.countryCode

                "studentsReferred" ->
                    af.studentsReferred

                _ ->
                    ""

        err =
            agentFormFieldError fieldId af

        cls =
            case err of
                Just _ ->
                    "ecc-field ecc-field--error"

                Nothing ->
                    "ecc-field"
    in
    div [ class cls ]
        ([ input
            [ id ("agf-" ++ fieldId)
            , type_ inputType
            , placeholder " "
            , value currentValue
            , onInput (UpdatedAgentFormField fieldId)
            , disabled af.submitting
            ]
            []
         , label [ for ("agf-" ++ fieldId) ] [ text labelText ]
         ]
            ++ (case err of
                    Just msg ->
                        [ p [ class "ecc-field__message" ] [ text msg ] ]

                    Nothing ->
                        []
               )
        )


agentStatusPills : String -> String -> List String -> (String -> Msg) -> Bool -> Html Msg
agentStatusPills label current options toMsg isDisabled =
    div [ class "ecc-field" ]
        [ span [ class "ecc-field__label" ] [ text label ]
        , div [ class "stage-pills" ]
            (List.map
                (\s ->
                    let
                        cls =
                            if current == s then
                                "stage-pill stage-pill--active"

                            else
                                "stage-pill"
                    in
                    button
                        [ type_ "button"
                        , class cls
                        , onClick (toMsg s)
                        , disabled isDisabled
                        ]
                        [ text s ]
                )
                options
            )
        ]


agentFormView : AgentForm -> Bool -> Html Msg
agentFormView af isEdit =
    let
        formError =
            agentFormFieldError "form" af

        submitLabel =
            if af.submitting then
                "Saving…"

            else if isEdit then
                "Save changes"

            else
                "Save agent"
    in
    form [ onSubmit SubmittedAgentForm, Attr.novalidate True ]
        [ Html.node "crm-draft-recovery" [] []
        , case formError of
            Just msg ->
                div [ class "ecc-alert ecc-alert--error" ] [ text msg ]

            Nothing ->
                text ""
        , div [ class "form-grid" ]
            [ agentRichField af "name" "Agent full name" "text"
            , if isEdit then agentRichField af "agentCode" "Agent reference" "text" else p [ class "ecc-field__message" ] [ text "Agent reference is generated automatically when you save." ]
            , agentRichField af "countryCode" "Country code (e.g. IN)" "text"
            ]
        , agentStatusPills "Contract status"
            af.contractStatus
            agentContractStatuses
            (UpdatedAgentFormField "contractStatus")
            af.submitting
        , agentStatusPills "Agent status"
            af.agentStatus
            agentStatuses
            (UpdatedAgentFormField "agentStatus")
            af.submitting
        , div [ class "ecc-field ecc-field--notes" ]
            [ span [ class "ecc-field__label" ] [ text "Notes" ]
            , textarea
                [ id "agf-notes"
                , placeholder "Additional notes or remarks…"
                , value af.notes
                , onInput (UpdatedAgentFormField "notes")
                , disabled af.submitting
                , Attr.rows 4
                ]
                []
            ]
        , div [ class "modal__actions" ]
            [ button
                [ type_ "button"
                , class "ecc-btn ecc-btn--ghost ecc-btn--inline"
                , onClick RequestedCloseAgentForm
                , disabled af.submitting
                ]
                [ text "Cancel" ]
            , button
                [ type_ "submit"
                , class "ecc-btn ecc-btn--inline"
                , disabled (af.submitting || not af.dirty)
                ]
                [ text submitLabel ]
            ]
        ]


agentFormModal : Model -> AgentForm -> Html Msg
agentFormModal model af =
    let
        isEdit =
            model.editingAgentId /= Nothing

        titleText =
            if isEdit then
                "Edit agent"

            else
                "Add agent"
    in
    div [ class "modal-backdrop", onClick RequestedCloseAgentForm ]
        [ div
            [ class "modal modal--wide"
            , Attr.attribute "role" "dialog"
            , Attr.attribute "data-draft-record-id" (Maybe.withDefault "new" model.editingAgentId)
            , Attr.attribute "aria-modal" "true"
            , Attr.attribute "aria-label" titleText
            , Html.Events.stopPropagationOn "click"
                (D.succeed ( DismissedToast, True ))
            ]
            [ header [ class "modal__header" ]
                [ h2 [ class "modal__title" ] [ text titleText ]
                , button
                    [ class "modal__close"
                    , type_ "button"
                    , onClick RequestedCloseAgentForm
                    , Attr.attribute "aria-label" "Close"
                    ]
                    [ svgIcon
                        [ Attr.attribute "viewBox" "0 0 24 24"
                        , Attr.attribute "width" "18"
                        , Attr.attribute "height" "18"
                        , Attr.attribute "fill" "none"
                        , Attr.attribute "stroke" "currentColor"
                        , Attr.attribute "stroke-width" "2"
                        , Attr.attribute "stroke-linecap" "round"
                        , Attr.attribute "stroke-linejoin" "round"
                        ]
                        [ svgPath "M18 6 6 18"
                        , svgPath "M6 6l12 12"
                        ]
                    ]
                ]
            , if af.confirmDiscard then
                div [ class "modal__confirm" ]
                    [ p [ class "modal__confirm-text" ]
                        [ text "Discard your changes? They won't be saved." ]
                    , div [ class "modal__actions" ]
                        [ button
                            [ type_ "button"
                            , class "ecc-btn ecc-btn--ghost ecc-btn--inline"
                            , onClick CancelledCloseAgentForm
                            ]
                            [ text "Keep editing" ]
                        , button
                            [ type_ "button"
                            , class "ecc-btn ecc-btn--danger ecc-btn--inline"
                            , onClick ConfirmedCloseAgentForm
                            ]
                            [ text "Discard" ]
                        ]
                    ]

              else
                agentFormView af isEdit
            ]
        ]


deleteAgentConfirmModal : Agent -> Html Msg
deleteAgentConfirmModal agent =
    div [ class "modal-backdrop", onClick CancelledDeleteAgent ]
        [ div
            [ class "modal modal--narrow"
            , Attr.attribute "role" "alertdialog"
            , Attr.attribute "aria-modal" "true"
            , Attr.attribute "aria-label" "Delete agent"
            , Html.Events.stopPropagationOn "click"
                (D.succeed ( DismissedToast, True ))
            ]
            [ header [ class "modal__header" ]
                [ h2 [ class "modal__title" ] [ text "Delete agent" ]
                , button
                    [ class "modal__close"
                    , type_ "button"
                    , onClick CancelledDeleteAgent
                    , Attr.attribute "aria-label" "Close"
                    ]
                    [ svgIcon
                        [ Attr.attribute "viewBox" "0 0 24 24"
                        , Attr.attribute "width" "18"
                        , Attr.attribute "height" "18"
                        , Attr.attribute "fill" "none"
                        , Attr.attribute "stroke" "currentColor"
                        , Attr.attribute "stroke-width" "2"
                        , Attr.attribute "stroke-linecap" "round"
                        , Attr.attribute "stroke-linejoin" "round"
                        ]
                        [ svgPath "M18 6 6 18"
                        , svgPath "M6 6l12 12"
                        ]
                    ]
                ]
            , p [ class "modal__confirm-text" ]
                [ text "Delete "
                , strong [] [ text agent.name ]
                , text "? This cannot be undone."
                ]
            , div [ class "modal__actions" ]
                [ button
                    [ type_ "button"
                    , class "ecc-btn ecc-btn--ghost ecc-btn--inline"
                    , onClick CancelledDeleteAgent
                    ]
                    [ text "Cancel" ]
                , button
                    [ type_ "button"
                    , class "ecc-btn ecc-btn--danger ecc-btn--inline"
                    , onClick ConfirmedDeleteAgent
                    ]
                    [ text "Delete" ]
                ]
            ]
        ]
