module Frontend.Date exposing (daysBefore, valid)


import Char


leap : Int -> Bool
leap year =
    modBy 400 year == 0 || (modBy 4 year == 0 && modBy 100 year /= 0)


monthDays : Int -> Int -> Int
monthDays year month =
    if month == 2 then
        if leap year then 29 else 28
    else if List.member month [ 4, 6, 9, 11 ] then 30 else 31


parse : String -> Maybe ( Int, Int, Int )
parse date =
    case String.split "-" date of
        [ y, m, d ] ->
            case ( String.toInt y, String.toInt m, String.toInt d ) of
                ( Just year, Just month, Just day ) ->
                    if String.length y == 4 && String.length m == 2 && String.length d == 2 && String.all Char.isDigit (y ++ m ++ d) && year > 0 && month >= 1 && month <= 12 && day >= 1 && day <= monthDays year month then Just ( year, month, day ) else Nothing
                _ -> Nothing
        _ -> Nothing


valid : String -> Bool
valid date =
    parse date /= Nothing


daysBefore : Int -> String -> String
daysBefore count date =
    let
        previous remaining ( year, month, day ) =
            if remaining <= 0 then ( year, month, day )
            else if day > 1 then previous (remaining - 1) ( year, month, day - 1 )
            else if month > 1 then previous (remaining - 1) ( year, month - 1, monthDays year (month - 1) )
            else if year <= 1 then ( 1, 1, 1 )
            else previous (remaining - 1) ( year - 1, 12, 31 )
        format ( year, month, day ) =
            String.padLeft 4 '0' (String.fromInt year) ++ "-" ++ String.padLeft 2 '0' (String.fromInt month) ++ "-" ++ String.padLeft 2 '0' (String.fromInt day)
    in
    parse date |> Maybe.map (previous (max 0 (min 36600 count)) >> format) |> Maybe.withDefault date
