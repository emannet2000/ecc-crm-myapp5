module ReportChecks exposing (checks)

import Dict
import Frontend.Date as Date
import Frontend.Money as Money
import Json.Decode as D
import ManagementReport as Report


fixture : String
fixture =
    """{"today":"2024-03-01","generatedAt":"2024-03-01T12:00:00Z","scopeLabel":"=SUM(A1)","reportingCurrency":"USD","missingRates":["EUR"],"contacts":5,"students":2,"leads":3,"activeCases":1,"openTasks":4,"totalCases":3,"pipelineByCurrency":{"EUR":1234.56},"wonByCurrency":{"USD":100},"balanceByCurrency":{},"pipelineValue":0,"wonValue":100,"outstandingBalance":0,"stageCounts":{"Proposal":1},"stageCurrencyValues":{"Proposal":{"EUR":1234.56}},"caseStages":{"Submitted":3},"createdCounts":{"2024-01-01":2,"2024-02-01":5,"2024-03-01":3,"invalid":100}}"""


checks : List ( String, Bool )
checks =
    case D.decodeString Report.decoder fixture of
        Err _ -> [ ( "Report fixture decodes", False ) ]
        Ok data ->
            let
                loading = Report.start "owner" Report.init |> Tuple.first
                loaded = Report.update (Report.Loaded "owner" loading.generation (Ok data)) loading |> Tuple.first
                refreshing = Report.update Report.Refresh loaded |> Tuple.first
                failed = Report.update (Report.Loaded "owner" refreshing.generation (Err "Outage")) refreshing |> Tuple.first
                stale = Report.update (Report.Loaded "owner" loading.generation (Ok data)) failed |> Tuple.first
                otherUser = Report.start "other" loaded |> Tuple.first
                foreign = Report.update (Report.Loaded "owner" otherUser.generation (Ok data)) otherUser |> Tuple.first
                all = Report.update (Report.Period "all") loaded |> Tuple.first
                invalid = Report.update (Report.From "2099-01-01") loaded |> Tuple.first
                blank = Report.update (Report.To "") loaded |> Tuple.first
                cleared = Report.clear loaded
                again = Report.start "owner" cleared |> Tuple.first
                latePreviousSession = Report.update (Report.Loaded "owner" loading.generation (Ok data)) again |> Tuple.first
                exported = Report.csv all data
                blockedPrint = Report.update (Report.Printed False) loaded |> Tuple.first
            in
            [ ( "Report uses inclusive leap-year workspace dates", loaded.from == "2024-02-01" && loaded.to == "2024-03-01" )
            , ( "Report filters include both date boundaries", Report.activity loaded data == [ ( "2024-02-01", 5 ), ( "2024-03-01", 3 ) ] )
            , ( "All activity ignores invalid dates", all.from == "2024-01-01" && List.sum (List.map Tuple.second (Report.activity all data)) == 10 )
            , ( "Successful report permits export", Report.canExport loaded )
            , ( "Refreshing keeps snapshot but disables export", refreshing.data == loaded.data && not (Report.canExport refreshing) )
            , ( "Failed refresh keeps snapshot but disables export", failed.data == loaded.data && failed.error == "Outage" && not (Report.canExport failed) )
            , ( "Old report responses cannot hide refresh errors", stale == failed )
            , ( "Changed accounts cannot see old report data", otherUser.data == Nothing && foreign == otherUser )
            , ( "Logout protects against a late reply after same-user sign-in", latePreviousSession == again )
            , ( "Reversed and missing dates disable export", not (Report.canExport invalid) && not (Report.canExport blank) )
            , ( "Currency gaps prevent false consolidated CSV totals", not (String.contains "\"Financial consolidated\",\"Open pipeline\"" exported) && String.contains "\"Financial original currency\",\"Open pipeline\",\"EUR\",\"1234.56\"" exported )
            , ( "CSV neutralizes formulas in text fields", String.contains "\"Scope\",\"'=SUM(A1)\"" exported )
            , ( "CSV quotes embedded delimiters and newlines", String.contains "\"Comma, quote\"\"\nnext\"" (Report.csv all { data | meta = let meta = data.meta in { meta | scopeLabel = "Comma, quote\"\nnext" } }) )
            , ( "Blocked print preserves export availability", blockedPrint.printError && Report.canExport blockedPrint )
            , ( "Malformed report payloads are rejected", List.all (\body -> Result.toMaybe (D.decodeString Report.decoder body) == Nothing) [ "null", "{}", "<html>Bad gateway</html>", String.replace "2024-03-01\"" "2024-02-30\"" fixture ] )
            , ( "Gregorian leap and century date boundaries", Date.daysBefore 1 "2024-03-01" == "2024-02-29" && Date.daysBefore 1 "1900-03-01" == "1900-02-28" && Date.daysBefore 1 "2000-03-01" == "2000-02-29" && Date.daysBefore 1 "2025-01-01" == "2024-12-31" )
            , ( "Invalid ISO dates are rejected", List.all (not << Date.valid) [ "", "2024-13-01", "2023-02-29", "2024-02-30", "2024-01-00", "2024-1-01", "abcd-01-01", "0000-01-01" ] )
            , ( "Large financial values cannot wrap into a negative amount", Money.format 3000000000 == "3000000000.00" && Money.format -3000000000 == "-3000000000.00" )
            , ( "Currency formatting retains cents and rejects non-finite totals", Money.format 1234.56 == "1234.56" && Money.format -0.25 == "-0.25" && Money.format 0 == "0.00" && Money.format (0 / 0) == "Unavailable" && Money.format (1 / 0) == "Unavailable" )
            , ( "Date subtraction stays within valid Gregorian dates", Date.daysBefore 89 "0001-01-01" == "0001-01-01" )
            ] ++ List.map (\index ->
                let date = "20" ++ String.padLeft 2 '0' (String.fromInt (modBy 90 index + 10)) ++ "-" ++ String.padLeft 2 '0' (String.fromInt (modBy 12 index + 1)) ++ "-28"
                    shifted = Date.daysBefore 89 date
                in ( "Report date arithmetic property " ++ String.fromInt index, Date.valid shifted && shifted < date && Date.daysBefore 0 date == date && Date.daysBefore 60 date == Date.daysBefore 30 (Date.daysBefore 30 date) )
                ) (List.range 1 1000)
