module Frontend.RequestOrder exposing (State, advance, current, init)

import Dict exposing (Dict)


type alias State =
    { sequence : Int, versions : Dict String Int }


init : State
init =
    { sequence = 0, versions = Dict.empty }


advance : List String -> State -> State
advance keys state =
    if List.isEmpty keys then state
    else
        let next = state.sequence + 1 in
        { sequence = next, versions = List.foldl (\key versions -> Dict.insert key next versions) state.versions keys }


current : String -> State -> State -> Bool
current key issued latest =
    Dict.get key issued.versions == Dict.get key latest.versions
