module TeamChat exposing (Model, Msg(..), init, start, subscriptions, update, view)

import Browser.Dom as Dom
import Browser.Events as Events
import Dict exposing (Dict)
import Frontend.Http as Api
import Html exposing (..)
import Html.Attributes as A
import Html.Events exposing (on, onClick, onInput, onSubmit)
import Json.Decode as D
import Json.Encode as E
import Random
import Task
import Time
import Url


type alias Person =
    { id : String, name : String, role : String, unread : Int }


type alias Message =
    { id : Int, senderId : String, body : String, createdAt : String }


type alias Pending =
    { userId : String, peer : String, body : String, clientId : String }


type alias Model =
    { userId : String
    , people : Dict Int (List Person)
    , query : String
    , rosterRequest : Int
    , rosterBusy : Bool
    , rosterError : String
    , peer : Maybe Person
    , generation : Int
    , messages : Dict Int Message
    , drafts : Dict String String
    , pending : Maybe Pending
    , sending : Bool
    , loading : Bool
    , historyDone : Bool
    , historyBusy : Bool
    , notice : String
    , readId : Int
    , visible : Bool
    , stickBottom : Bool
    }


type Msg
    = Poll Time.Posix
    | Visibility Events.Visibility
    | Search String
    | RetryPeople
    | MorePeople
    | PeopleLoaded String Int Int (Result String (List Person))
    | Choose Person
    | Back
    | Changed String
    | Send
    | ClientId String String String (List Int)
    | Sent Pending (Result String ())
    | MessagesLoaded String Int Bool (Result String (List Message))
    | Older
    | Read String Int Int (Result String ())
    | Scrolled Bool
    | DomFinished (Result Dom.Error ())


init : Model
init =
    { userId = "", people = Dict.empty, query = "", rosterRequest = 0, rosterBusy = False, rosterError = "", peer = Nothing, generation = 0, messages = Dict.empty, drafts = Dict.empty, pending = Nothing, sending = False, loading = False, historyDone = False, historyBusy = False, notice = "", readId = 0, visible = True, stickBottom = True }


personDecoder : D.Decoder Person
personDecoder =
    D.map4 Person (D.field "id" D.string) (D.field "name" D.string) (D.field "role" D.string) (D.field "unread" D.int)


messageDecoder : D.Decoder Message
messageDecoder =
    D.map4 Message (D.field "id" D.int) (D.field "senderId" D.string) (D.field "body" D.string) (D.field "createdAt" D.string)


people : Model -> List Person
people model =
    model.people |> Dict.values |> List.concat


getPeople : Int -> Model -> Cmd Msg
getPeople offset model =
    Api.get ("/api/team-chat/people?q=" ++ Url.percentEncode model.query ++ "&offset=" ++ String.fromInt offset) (D.list personDecoder) (PeopleLoaded model.userId model.rosterRequest offset)


start : String -> Model -> ( Model, Cmd Msg )
start userId previous =
    let
        model = if previous.userId == userId then { previous | peer = Nothing, generation = previous.generation + 1 } else init
        next = { model | userId = userId, rosterRequest = model.rosterRequest + 1, rosterBusy = True }
    in
    ( next, getPeople 0 next )


getMessages : Bool -> Model -> Cmd Msg
getMessages older model =
    case model.peer of
        Nothing -> Cmd.none
        Just peer ->
            let
                before = if older then model.messages |> Dict.keys |> List.head |> Maybe.map (\id -> "?before=" ++ String.fromInt id) |> Maybe.withDefault "" else ""
            in
            Api.get ("/api/team-chat/" ++ Url.percentEncode peer.id ++ before) (D.list messageDecoder) (MessagesLoaded model.userId model.generation older)


send : Pending -> Model -> ( Model, Cmd Msg )
send pending model =
    ( { model | sending = True, pending = Just pending, notice = "Sending…" }
    , Api.post ("/api/team-chat/" ++ Url.percentEncode pending.peer) (E.object [ ( "body", E.string pending.body ), ( "clientId", E.string pending.clientId ) ]) (D.succeed ()) (Sent pending)
    )


scrollBottom : Cmd Msg
scrollBottom =
    Dom.getViewportOf "team-chat-messages"
        |> Task.andThen (\viewport -> Dom.setViewportOf "team-chat-messages" 0 viewport.scene.height)
        |> Task.attempt DomFinished


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Search query ->
            let next = { model | query = query, people = Dict.empty, rosterRequest = model.rosterRequest + 1, rosterBusy = True, rosterError = "" } in
            ( next, getPeople 0 next )
        RetryPeople ->
            let next = { model | rosterRequest = model.rosterRequest + 1, rosterBusy = True } in ( next, getPeople 0 next )
        MorePeople ->
            if model.rosterBusy then ( model, Cmd.none ) else ( { model | rosterBusy = True }, getPeople (List.length (people model)) model )
        PeopleLoaded userId request offset result ->
            if userId /= model.userId || request /= model.rosterRequest then ( model, Cmd.none )
            else case result of
                Ok batch -> ( { model | people = Dict.insert offset batch model.people, rosterBusy = False, rosterError = "" }, Cmd.none )
                Err message -> ( { model | rosterBusy = False, rosterError = message }, Cmd.none )
        Choose peer ->
            let next = { model | peer = Just peer, generation = model.generation + 1, messages = Dict.empty, historyDone = False, historyBusy = False, loading = True, notice = "Loading conversation…", readId = 0, stickBottom = True } in
            ( next, Cmd.batch [ getMessages False next, Dom.focus "team-chat-heading" |> Task.attempt DomFinished ] )
        Back ->
            ( { model | peer = Nothing, generation = model.generation + 1, loading = False }, Dom.focus "team-chat-search" |> Task.attempt DomFinished )
        Changed body ->
            case model.peer of
                Nothing -> ( model, Cmd.none )
                Just peer -> ( { model | drafts = Dict.insert peer.id body model.drafts }, Cmd.none )
        Send ->
            case model.peer of
                Nothing -> ( model, Cmd.none )
                Just peer ->
                    let body = Dict.get peer.id model.drafts |> Maybe.withDefault "" |> String.trim in
                    if body == "" || model.sending then ( model, Cmd.none )
                    else case model.pending of
                        Just pending -> if pending.peer == peer.id && pending.body == body then send pending model else ( { model | sending = True }, Random.generate (ClientId model.userId peer.id body) (Random.list 4 (Random.int 0 2147483647)) )
                        Nothing -> ( { model | sending = True }, Random.generate (ClientId model.userId peer.id body) (Random.list 4 (Random.int 0 2147483647)) )
        ClientId userId peer body numbers ->
            if userId /= model.userId then ( model, Cmd.none )
            else send (Pending userId peer body ("elm-" ++ String.join "-" (List.map String.fromInt numbers))) model
        Sent pending result ->
            if pending.userId /= model.userId then ( model, Cmd.none )
            else case result of
                Err message -> ( { model | sending = False, notice = message ++ " Your draft is kept; tap Send to retry." }, Cmd.none )
                Ok _ ->
                    let
                        unchanged = Dict.get pending.peer model.drafts |> Maybe.map String.trim |> Maybe.withDefault "" |> (==) pending.body
                        next = { model | sending = False, pending = Nothing, drafts = if unchanged then Dict.remove pending.peer model.drafts else model.drafts, notice = "", stickBottom = True }
                    in
                    if Maybe.map .id model.peer == Just pending.peer then ( { next | loading = True }, getMessages False next ) else ( next, Cmd.none )
        Older ->
            if model.historyBusy || model.historyDone then ( model, Cmd.none ) else ( { model | historyBusy = True, stickBottom = False }, getMessages True model )
        MessagesLoaded userId generation older result ->
            if userId /= model.userId || generation /= model.generation then ( model, Cmd.none )
            else case result of
                Err message -> ( { model | loading = False, historyBusy = False, notice = message }, Cmd.none )
                Ok batch ->
                    let
                        messages = List.foldl (\message -> Dict.insert message.id message) model.messages batch
                        newest = List.map .id batch |> List.maximum |> Maybe.withDefault 0
                        next = { model | messages = messages, loading = False, historyBusy = False, historyDone = model.historyDone || (older && List.length batch < 100) || (Dict.isEmpty model.messages && List.length batch < 100), notice = if model.sending then model.notice else "" }
                        markRead =
                            case model.peer of
                                Just peer -> if not older && newest > model.readId && model.visible then Api.post ("/api/team-chat/" ++ Url.percentEncode peer.id) (E.object [ ( "readId", E.int newest ) ]) (D.succeed ()) (Read model.userId generation newest) else Cmd.none
                                Nothing -> Cmd.none
                    in
                    ( next, Cmd.batch [ markRead, if model.stickBottom && not older then scrollBottom else Cmd.none ] )
        Read userId generation newest result ->
            if userId == model.userId && generation == model.generation && Result.toMaybe result /= Nothing then ( { model | readId = newest }, Cmd.none ) else ( model, Cmd.none )
        Poll _ ->
            if not model.visible then ( model, Cmd.none )
            else
                let next = { model | rosterRequest = model.rosterRequest + 1 } in
                ( next, Cmd.batch ((Dict.keys model.people |> (\offsets -> if List.isEmpty offsets then [ 0 ] else offsets) |> List.map (\offset -> getPeople offset next)) ++ [ if model.loading then Cmd.none else getMessages False next ]) )
        Visibility visibility -> ( { model | visible = visibility == Events.Visible }, Cmd.none )
        Scrolled atBottom -> ( { model | stickBottom = atBottom }, Cmd.none )
        DomFinished _ -> ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch [ Time.every 5000 Poll, Events.onVisibilityChange Visibility ]


view : Model -> Html Msg
view model =
    let
        peerName = model.peer |> Maybe.map .name |> Maybe.withDefault "Choose a colleague"
        draft = model.peer |> Maybe.andThen (\peer -> Dict.get peer.id model.drafts) |> Maybe.withDefault ""
        atBottom = D.map3 (\height top client -> Scrolled (height - top - client < 100)) (D.at [ "target", "scrollHeight" ] D.float) (D.at [ "target", "scrollTop" ] D.float) (D.at [ "target", "clientHeight" ] D.float)
    in
    div [ A.class "team-chat-elm" ]
        [ node "link" [ A.rel "stylesheet", A.href "/public/team-chat-elm.css" ] []
        , div [ A.class ("layout" ++ (if model.peer /= Nothing then " open" else "")) ]
            [ section [ A.class "people", A.attribute "aria-label" "Colleagues" ]
                [ h2 [] [ text "Team chat" ]
                , input [ A.id "team-chat-search", A.class "search", A.type_ "search", A.placeholder "Find a colleague", A.attribute "aria-label" "Find a colleague", A.value model.query, A.maxlength 200, onInput Search ] []
                , p [ A.class "roster-status", A.attribute "role" "status" ] [ text (if model.rosterError /= "" then model.rosterError else if model.rosterBusy then "Loading colleagues…" else "") ]
                , if model.rosterError == "" then text "" else button [ A.type_ "button", onClick RetryPeople ] [ text "Retry loading colleagues" ]
                , div [ A.class "list" ]
                    (List.map (\person -> button [ A.type_ "button", A.class "person", A.attribute "aria-pressed" (if Maybe.map .id model.peer == Just person.id then "true" else "false"), onClick (Choose person) ] [ span [] [ text person.name, span [ A.class "role" ] [ text person.role ] ], if person.unread > 0 then span [ A.class "badge", A.attribute "aria-label" (String.fromInt person.unread ++ " unread messages") ] [ text (String.fromInt person.unread) ] else text "" ]) (people model)
                    ++ [ if model.people |> Dict.values |> List.reverse |> List.head |> Maybe.map List.length |> Maybe.withDefault 0 |> (==) 200 then button [ A.type_ "button", A.disabled model.rosterBusy, onClick MorePeople ] [ text "Load more colleagues" ] else text ""
                       , if List.isEmpty (people model) && not model.rosterBusy && model.rosterError == "" then p [] [ text (if model.query == "" then "No other active workspace members yet." else "No matching colleagues.") ] else text ""
                       ])
                ]
            , section [ A.class "conversation", A.attribute "aria-label" "Conversation" ]
                [ header [ A.class "heading" ] [ button [ A.class "back", A.type_ "button", A.attribute "aria-label" "Back to colleagues", onClick Back ] [ text "←" ], h2 [ A.id "team-chat-heading", A.tabindex -1 ] [ text peerName ] ]
                , div [ A.class "messages", A.id "team-chat-messages", A.attribute "role" "log", A.attribute "aria-label" "Messages", A.attribute "aria-live" "polite", on "scroll" atBottom ]
                    ([ if model.peer /= Nothing && not model.historyDone && not (Dict.isEmpty model.messages) then button [ A.type_ "button", A.disabled model.historyBusy, onClick Older ] [ text "Load earlier messages" ] else text "" ]
                    ++ List.map (\message -> div [ A.class ("message" ++ (if message.senderId == model.userId then " mine" else "")) ] [ text message.body, time [ A.datetime message.createdAt ] [ text (String.replace "T" " " (String.left 16 message.createdAt) ++ " UTC") ] ]) (Dict.values model.messages)
                    ++ [ if Dict.isEmpty model.messages && not model.loading then p [ A.class "empty" ] [ text (if model.peer == Nothing then "Private conversations with your workspace team." else "Start a conversation with " ++ peerName ++ ".") ] else text "" ])
                , form [ A.class "composer", A.hidden (model.peer == Nothing), onSubmit Send ] [ textarea [ A.rows 2, A.maxlength 4000, A.attribute "aria-label" "Message", A.placeholder "Write a message…", A.required True, A.value draft, onInput Changed ] [], button [ A.class "send", A.type_ "submit", A.disabled model.sending ] [ text "Send" ] ]
                , p [ A.class "status", A.attribute "role" "status" ] [ text model.notice ]
                ]
            ]
        ]
