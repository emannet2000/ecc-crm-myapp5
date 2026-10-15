module Frontend.Http exposing (get, post)

import Http
import Json.Decode as D
import Json.Encode as E
import Task


resolver : D.Decoder a -> Http.Resolver String a
resolver decoder =
    Http.stringResolver
        (\response ->
            case response of
                Http.GoodStatus_ _ body -> D.decodeString decoder body |> Result.mapError (\_ -> "Could not read the response. Please retry.")
                Http.BadStatus_ metadata body ->
                    if metadata.statusCode == 401 then Err "session-expired"
                    else Err (D.decodeString (D.oneOf [ D.field "error" D.string, D.field "message" D.string ]) body |> Result.withDefault "Could not complete this request. Please retry.")
                Http.Timeout_ -> Err "The request timed out. Please retry."
                Http.NetworkError_ -> Err "Could not connect. Please retry."
                Http.BadUrl_ _ -> Err "Could not open this request."
        )


request : String -> String -> Http.Body -> D.Decoder a -> (Result String a -> msg) -> Cmd msg
request method path body decoder received =
    let
        operation = Http.task { method = method, headers = [], url = path, body = body, resolver = resolver decoder, timeout = Just 20000 }
        refresh = Http.task { method = "POST", headers = [], url = "/api/session/refresh", body = Http.emptyBody, resolver = resolver (D.succeed ()), timeout = Just 15000 }
    in
    operation
        |> Task.onError (\message -> if message == "session-expired" then refresh |> Task.andThen (\_ -> operation) |> Task.mapError (\err -> if err == "session-expired" then "Your session expired. Sign in again." else err) else Task.fail message)
        |> Task.attempt received


get : String -> D.Decoder a -> (Result String a -> msg) -> Cmd msg
get path decoder received =
    request "GET" path Http.emptyBody decoder received


post : String -> E.Value -> D.Decoder a -> (Result String a -> msg) -> Cmd msg
post path body decoder received =
    request "POST" path (Http.jsonBody body) decoder received
