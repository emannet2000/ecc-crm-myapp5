module RecordBrowserChecks exposing (checks)

import Dict
import Json.Decode as D
import Json.Encode as E
import RecordBrowser as Records


checks : List ( String, Bool )
checks =
    let
        query = { entity = "contacts", search = "", status = "", sort = "name", direction = "asc", columns = [], page = 0 }
        initial = Records.init { userId = "owner", modules = [ "contacts", "deals", "invoices" ], payments = True, query = query } |> Tuple.first
        result = D.decodeString (Records.decoder "contacts") "{\"contacts\":[{\"id\":\"contact/a\",\"name\":\"Alice\",\"email\":\"alice@example.com\"}],\"total\":1}" |> Result.mapError D.errorToString
        loaded = Records.update (Records.Loaded initial.generation initial.query result) initial |> Tuple.first
        search = Records.update (Records.Search "new search") loaded |> Tuple.first |> Records.update Records.Apply |> Tuple.first
        stale = Records.update (Records.Loaded initial.generation initial.query result) search |> Tuple.first
        switched = Records.update (Records.Module "deals") loaded |> Tuple.first
        foreignModule = Records.update (Records.Loaded initial.generation initial.query result) switched |> Tuple.first
        pendingColumn = Records.update (Records.Column "email" True) initial |> Tuple.first
        repliedColumn = Records.update (Records.Loaded initial.generation initial.query result) pendingColumn |> Tuple.first
        previous = Records.update Records.Previous loaded |> Tuple.first
        next = Records.update Records.Next loaded |> Tuple.first
        failed = Records.update (Records.Loaded search.generation search.query (Err "Network failure")) search |> Tuple.first
        row = Dict.fromList [ ( "id", D.decodeString D.value "\"contact/a\"" |> Result.withDefault E.null ) ]
        sample key value = Dict.fromList [ ( key, D.decodeString D.value ("\"" ++ value ++ "\"") |> Result.withDefault E.null ) ]
    in
    [ ( "Record query changes invalidate older search replies", stale == search && search.loading && search.data == Nothing )
    , ( "Record module changes cannot mix earlier rows", foreignModule == switched && switched.query.columns == [] && switched.query.entity == "deals" )
    , ( "Column changes during a fetch do not leave the browser loading", not repliedColumn.loading && repliedColumn.data /= Nothing && List.member "email" repliedColumn.query.columns )
    , ( "Record pagination stays within bounds", previous == loaded && next == loaded )
    , ( "Record errors do not display old results", failed.error == "Network failure" && not failed.loading && failed.data == Nothing )
    , ( "Record links percent-encode identifiers", Records.recordLink "contacts" row == "/contacts/contact%2Fa" )
    , ( "Documents navigate to their application", Records.recordLink "documents" (sample "caseId" "case/a") == "/cases/case%2Fa#record-tools?tab=documents" )
    , ( "Documents without an application navigate to their lead", Records.recordLink "documents" (sample "leadId" "lead/a") == "/leads/lead%2Fa#record-tools?tab=documents" )
    , ( "Payments navigate to their invoice", Records.recordLink "payments" (sample "invoiceId" "invoice/a") == "/invoices/invoice%2Fa" )
    , ( "Record decoder rejects incomplete or negative-count replies", Result.toMaybe (D.decodeString (Records.decoder "contacts") "{\"contacts\":[],\"total\":-1}") == Nothing && Result.toMaybe (D.decodeString (Records.decoder "contacts") "{}") == Nothing )
    ]
