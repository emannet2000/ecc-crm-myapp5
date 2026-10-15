module View.Reports exposing (reportsView)

import ManagementReport
import Html exposing (..)
import Html.Attributes exposing (attribute, class, disabled, selected, type_, value)
import Html.Events exposing (onClick, onInput)
import Types exposing (..)
import View.Icons exposing (iconRefresh)


card : String -> String -> Html Msg
card label value =
    div [ class "stat-card" ]
        [ span [ class "stat-card__label" ] [ text label ]
        , span [ class "stat-card__value" ] [ text value ]
        ]


reportsView : Model -> Html Msg
reportsView model =
    div [ class "report-suite" ]
        [ Html.map ManagementReportMsg (ManagementReport.view model.managementReport)
        , details [ class "report-secondary" ]
            [ summary [] [ text "Operational outcomes and priorities" ]
            , Html.node "crm-work-outcomes" [] []
            , Html.node "crm-priority-queues" [] []
            ]
        , details [ class "report-secondary" ]
            [ summary [] [ text "Detailed operational analysis" ]
            , Html.node "crm-insights" [] []
            ]
        , details [ class "report-secondary" ]
            [ summary [] [ text "Record exports and change history" ]
            , div [ class "reports-panels" ] [ exportsView model, auditView model ]
            ]
        ]


exportsView : Model -> Html Msg
exportsView model =
    section [ class "workspace-panel export-panel" ]
        [ span [ class "panel-eyebrow" ] [ text "Data & exports" ]
        , h2 [] [ text "Take your data with you" ]
        , p [] [ text "Download the records your account can access." ]
        , div [ class "workspace-toolbar" ]
            [ select [ value model.exportEntity, onInput SelectedExportEntity, attribute "aria-label" "Records to export" ]
                (List.map (\entity -> option [ value entity, selected (entity == model.exportEntity) ] [ text (if entity == "cases" then "Applications" else String.toUpper (String.left 1 entity) ++ String.dropLeft 1 entity) ])
                    [ "contacts", "deals", "tasks", "schools", "students", "agents", "leads", "cases", "documents", "invoices", "payments", "partners", "activities" ]
                )
            , button [ class "ecc-btn", type_ "button", onClick RequestedExport, disabled (model.exporting /= Nothing) ]
                [ text
                    (if model.exporting /= Nothing then
                        "Preparing export…"

                     else
                        "Download CSV"
                    )
                ]
            ]
        ]


auditView : Model -> Html Msg
auditView model =
    section [ class "workspace-panel history-panel" ]
        [ div [ class "panel-header" ]
            [ div [] [ h2 [] [ text "Change history" ], p [] [ text "A record of changes across your workspace." ] ]
            , button [ class "icon-button", type_ "button", onClick (RequestedAuditPage 0), attribute "aria-label" "Refresh history", attribute "title" "Refresh history" ] [ iconRefresh ]
            ]
        , case model.audit of
            Success data ->
                div []
                    [ if List.isEmpty data.events then
                        p [] [ text "No changes yet. New changes will appear here." ]

                      else
                        div [ class "audit-list" ]
                            (List.map
                                (\event ->
                                    div [ class "audit-entry" ]
                                        [ span [ class ("audit-entry__marker audit-entry__marker--" ++ event.action), attribute "aria-hidden" "true" ]
                                            [ text
                                                (case event.action of
                                                    "created" ->
                                                        "+"

                                                    "deleted" ->
                                                        "−"

                                                    _ ->
                                                        "↗"
                                                )
                                            ]
                                        , div [ class "audit-entry__body" ]
                                            [ div [ class "audit-entry__headline" ]
                                                [ strong [] [ text event.label ]
                                                , span [ class ("audit-action audit-action--" ++ event.action) ] [ text (String.toUpper (String.left 1 event.action) ++ String.dropLeft 1 event.action) ]
                                                ]
                                            , span [ class "audit-entry__meta" ] [ text (event.entity ++ " · " ++ event.actor) ]
                                            , Html.time [ class "audit-entry__time", attribute "datetime" event.occurredAt ] [ text (String.left 10 event.occurredAt ++ " · " ++ String.slice 11 19 event.occurredAt ++ " UTC") ]
                                            ]
                                        ]
                                )
                                data.events
                            )
                    , div [ class "workspace-toolbar" ]
                        [ button [ class "ecc-btn ecc-btn--ghost", type_ "button", disabled (model.auditOffset == 0), onClick (RequestedAuditPage (model.auditOffset - 25)) ] [ text "Previous" ]
                        , span [] [ text (String.fromInt (min data.total (model.auditOffset + 1)) ++ "–" ++ String.fromInt (min data.total (model.auditOffset + 25)) ++ " of " ++ String.fromInt data.total) ]
                        , button [ class "ecc-btn ecc-btn--ghost", type_ "button", disabled (model.auditOffset + 25 >= data.total), onClick (RequestedAuditPage (model.auditOffset + 25)) ] [ text "Next" ]
                        ]
                    ]

            Failure message ->
                p [ attribute "role" "alert" ] [ text message ]

            _ ->
                p [ attribute "role" "status" ] [ text "Loading history…" ]
        ]
