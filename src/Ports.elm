port module Ports exposing (workReady, printResult, printElement, downloadFile, storeTheme, storeToken, logoutSession, logoutFinished, preserveSessionDrafts, sessionIdentity, recordChanged, protectUnsaved)

{-| JavaScript interop.
-}


port storeToken : Maybe String -> Cmd msg


port logoutSession : () -> Cmd msg


port logoutFinished : ({ ok : Bool, message : String } -> msg) -> Sub msg


port preserveSessionDrafts : String -> Cmd msg


port sessionIdentity : String -> Cmd msg


port downloadFile : { filename : String, content : String, mime : String } -> Cmd msg


port storeTheme : String -> Cmd msg


port protectUnsaved : Bool -> Cmd msg


port recordChanged : (String -> msg) -> Sub msg


port printElement : String -> Cmd msg


port printResult : (Bool -> msg) -> Sub msg


port workReady : () -> Cmd msg
