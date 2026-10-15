module Frontend.Money exposing (format)


format : Float -> String
format value =
    if isNaN value || isInfinite value then "Unavailable"
    else if abs value >= 1000000000000000000000 then String.fromFloat value
    else
        let
            cents = round (abs value * 100)
            whole = floor (toFloat cents / 100)
        in
        (if value < 0 then "-" else "") ++ String.fromInt whole ++ "." ++ String.padLeft 2 '0' (String.fromInt (modBy 100 cents))
