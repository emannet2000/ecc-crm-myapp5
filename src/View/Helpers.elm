module View.Helpers exposing (alertView, detailCard, detailEmpty, detailStat, emptyIllustration, formField, infoRow, initials, onCheck, onEnter, paginationBar, sparkline, svgIcon, svgPath, toastView)

{-| Shared view helpers: svg/event helpers, form fields, alerts, pagination, toasts, detail-card pieces, sparkline, empty illustration.
-}

import Html exposing (..)
import Html.Attributes as Attr exposing (class, disabled, for, id, placeholder, type_, value)
import Html.Events exposing (onClick, onInput)
import Json.Decode as D
import Svg
import Types exposing (..)


svgIcon : List (Html.Attribute msg) -> List (Html msg) -> Html msg
svgIcon attributes children =
    Svg.svg (Attr.attribute "aria-hidden" "true" :: attributes) children


svgPath : String -> Html msg
svgPath d =
    Svg.path [ Attr.attribute "d" d ] []


onCheck : (Bool -> msg) -> Html.Attribute msg
onCheck toMsg =
    Html.Events.on "change"
        (D.map toMsg (D.at [ "target", "checked" ] D.bool))


onEnter : msg -> Html.Attribute msg
onEnter msg =
    Html.Events.on "keydown"
        (D.field "key" D.string
            |> D.andThen
                (\key ->
                    if key == "Enter" then
                        D.succeed msg

                    else
                        D.fail "not enter"
                )
        )


fieldError : Field -> Model -> Maybe String
fieldError field model =
    model.errors
        |> List.filter (\( f, _ ) -> f == field)
        |> List.head
        |> Maybe.map Tuple.second


initials : String -> String
initials name =
    name
        |> String.words
        |> List.map (String.left 1)
        |> List.take 2
        |> String.concat
        |> String.toUpper


alertView : Maybe Alert -> Html msg
alertView maybeAlert =
    case maybeAlert of
        Nothing ->
            text ""

        Just alert ->
            let
                cls =
                    case alert.kind of
                        AlertError ->
                            "ecc-alert ecc-alert--error"

                        AlertSuccess ->
                            "ecc-alert ecc-alert--success"
            in
            div [ class cls, Attr.attribute "role" "alert" ]
                [ text alert.message ]


type alias FieldConfig =
    { id : String
    , labelText : String
    , fieldType : String
    , fieldKey : Field
    , autocomplete : String
    }


formField : Model -> FieldConfig -> Html Msg
formField model cfg =
    let
        val =
            case cfg.fieldKey of
                NameField ->
                    model.form.name

                EmailField ->
                    model.form.email

                PasswordField ->
                    model.form.password

        err =
            fieldError cfg.fieldKey model

        isPassword =
            cfg.fieldKey == PasswordField

        inputType =
            if isPassword && model.showPassword then
                "text"

            else
                cfg.fieldType

        containerClass =
            case err of
                Just _ ->
                    "ecc-field ecc-field--error"

                Nothing ->
                    "ecc-field"
    in
    div [ class containerClass ]
        ([ input
            [ id cfg.id
            , Attr.name cfg.id
            , type_ inputType
            , placeholder " "
            , Attr.attribute "autocomplete" cfg.autocomplete
            , Attr.attribute "autocapitalize" (if cfg.fieldKey == NameField then "words" else "none")
            , Attr.attribute "enterkeyhint" (if isPassword then "go" else "next")
            , Attr.attribute "spellcheck" "false"
            , Attr.attribute "aria-invalid" (if err /= Nothing then "true" else "false")
            , value val
            , onInput (UpdatedField cfg.fieldKey)
            ]
            []
         , label [ for cfg.id ] [ text cfg.labelText ]
         ]
            ++ (if isPassword then
                    [ button
                        [ type_ "button"
                        , class "ecc-field__toggle"
                        , Attr.attribute "aria-label"
                            (if model.showPassword then
                                "Hide password"

                             else
                                "Show password"
                            )
                        , Attr.attribute "aria-pressed" (if model.showPassword then "true" else "false")
                        , onClick ToggledShowPassword
                        ]
                        [ if model.showPassword then
                            svgIcon
                                [ Attr.attribute "viewBox" "0 0 24 24"
                                , Attr.attribute "width" "18"
                                , Attr.attribute "height" "18"
                                , Attr.attribute "fill" "none"
                                , Attr.attribute "stroke" "currentColor"
                                , Attr.attribute "stroke-width" "1.8"
                                , Attr.attribute "stroke-linecap" "round"
                                , Attr.attribute "stroke-linejoin" "round"
                                ]
                                [ svgPath "M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"
                                , svgPath "M1 1l22 22"
                                ]

                          else
                            svgIcon
                                [ Attr.attribute "viewBox" "0 0 24 24"
                                , Attr.attribute "width" "18"
                                , Attr.attribute "height" "18"
                                , Attr.attribute "fill" "none"
                                , Attr.attribute "stroke" "currentColor"
                                , Attr.attribute "stroke-width" "1.8"
                                , Attr.attribute "stroke-linecap" "round"
                                , Attr.attribute "stroke-linejoin" "round"
                                ]
                                [ svgPath "M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8Z"
                                , Svg.node "circle"
                                    [ Attr.attribute "cx" "12"
                                    , Attr.attribute "cy" "12"
                                    , Attr.attribute "r" "3"
                                    ]
                                    []
                                ]
                        ]
                    ]

                else
                    []
               )
            ++ (case err of
                    Just msg ->
                        [ p [ class "ecc-field__message" ] [ text msg ] ]

                    Nothing ->
                        []
               )
        )


paginationBar : Int -> Int -> Int -> (Int -> Msg) -> Html Msg
paginationBar total offset limit toMsg =
    let
        from =
            if total == 0 then
                0

            else
                offset + 1

        to =
            min total (offset + limit)

        canPrev =
            offset > 0

        canNext =
            offset + limit < total
    in
    if total <= limit then
        p [ class "page-toolbar__summary" ]
            [ text
                (String.fromInt total
                    ++ " result"
                    ++ (if total == 1 then
                            ""

                        else
                            "s"
                       )
                )
            ]

    else
        div [ class "pagination" ]
            [ span [ class "pagination__info" ]
                [ text (String.fromInt from ++ "–" ++ String.fromInt to ++ " of " ++ String.fromInt total) ]
            , div [ class "pagination__btns" ]
                [ button
                    [ type_ "button"
                    , class "ecc-btn ecc-btn--ghost ecc-btn--inline"
                    , disabled (not canPrev)
                    , onClick (toMsg (max 0 (offset - limit)))
                    ]
                    [ text "Previous" ]
                , button
                    [ type_ "button"
                    , class "ecc-btn ecc-btn--ghost ecc-btn--inline"
                    , disabled (not canNext)
                    , onClick (toMsg (offset + limit))
                    ]
                    [ text "Next" ]
                ]
            ]


toastView : String -> Html Msg
toastView message =
    div [ class "toast", Attr.attribute "role" "status" ]
        [ svgIcon
            [ Attr.attribute "viewBox" "0 0 24 24"
            , Attr.attribute "width" "16"
            , Attr.attribute "height" "16"
            , Attr.attribute "fill" "none"
            , Attr.attribute "stroke" "currentColor"
            , Attr.attribute "stroke-width" "2.5"
            , Attr.attribute "stroke-linecap" "round"
            , Attr.attribute "stroke-linejoin" "round"
            ]
            [ svgPath "M20 6 9 17l-5-5" ]
        , span [] [ text message ]
        ]


infoRow : Html Msg -> String -> String -> Html Msg
infoRow icon label valueText =
    div [ class "info-row" ]
        [ span [ class "info-row__icon" ] [ icon ]
        , div [ class "info-row__body" ]
            [ span [ class "info-row__label" ] [ text label ]
            , span [ class "info-row__value" ] [ text valueText ]
            ]
        ]


detailStat : String -> String -> String -> Html Msg
detailStat label valueText hint =
    div [ class "detail-stat" ]
        [ span [ class "detail-stat__label" ] [ text label ]
        , span [ class "detail-stat__value" ] [ text valueText ]
        , span [ class "detail-stat__hint" ] [ text hint ]
        ]


detailCard : String -> Maybe (Html Msg) -> Html Msg -> Html Msg
detailCard titleText action body =
    section [ class "detail-card" ]
        [ header [ class "detail-card__header" ]
            [ h3 [ class "detail-card__title" ] [ text titleText ]
            , case action of
                Just a ->
                    a

                Nothing ->
                    text ""
            ]
        , body
        ]


detailEmpty : Html Msg -> String -> String -> Html Msg
detailEmpty icon titleText desc =
    div [ class "detail-empty" ]
        [ div [ class "detail-empty__icon" ] [ icon ]
        , h4 [ class "detail-empty__title" ] [ text titleText ]
        , p [ class "detail-empty__desc" ] [ text desc ]
        ]



-- ── Sparkline ────────────────────────────────────────────────


sparkline : List Int -> Html msg
sparkline values =
    let
        maxV =
            List.maximum values |> Maybe.withDefault 1

        n =
            List.length values

        barWidth =
            100 / toFloat (max 1 n)

        gap =
            barWidth * 0.28

        w =
            barWidth - gap

        bar i v =
            let
                h =
                    (toFloat v / toFloat (max 1 maxV)) * 100

                x =
                    toFloat i * barWidth + gap / 2

                y =
                    100 - h
            in
            Svg.node "rect"
                [ Attr.attribute "x" (String.fromFloat x)
                , Attr.attribute "y" (String.fromFloat y)
                , Attr.attribute "width" (String.fromFloat w)
                , Attr.attribute "height" (String.fromFloat h)
                , Attr.attribute "rx" "1"
                ]
                []
    in
    Svg.node "svg"
        [ Attr.attribute "viewBox" "0 0 100 100"
        , Attr.attribute "preserveAspectRatio" "none"
        , Attr.attribute "class" "sparkline"
        , Attr.attribute "aria-hidden" "true"
        ]
        (List.indexedMap bar values)



-- ── Empty illustration ───────────────────────────────────────


emptyIllustration : Html msg -> Html msg
emptyIllustration icon =
    div [ class "empty-illus" ]
        [ Svg.node "svg"
            [ Attr.attribute "viewBox" "0 0 120 120"
            , Attr.attribute "fill" "none"
            , Attr.attribute "aria-hidden" "true"
            ]
            [ Svg.node "circle"
                [ Attr.attribute "cx" "60"
                , Attr.attribute "cy" "60"
                , Attr.attribute "r" "52"
                , Attr.attribute "stroke" "rgba(226,185,77,0.15)"
                , Attr.attribute "stroke-width" "1"
                , Attr.attribute "stroke-dasharray" "3 6"
                ]
                []
            , Svg.node "circle"
                [ Attr.attribute "cx" "60"
                , Attr.attribute "cy" "60"
                , Attr.attribute "r" "38"
                , Attr.attribute "stroke" "rgba(226,185,77,0.25)"
                , Attr.attribute "stroke-width" "1"
                ]
                []
            , Svg.node "circle"
                [ Attr.attribute "cx" "60"
                , Attr.attribute "cy" "60"
                , Attr.attribute "r" "26"
                , Attr.attribute "fill" "rgba(226,185,77,0.06)"
                ]
                []
            ]
        , div [ class "empty-illus__icon" ] [ icon ]
        ]
