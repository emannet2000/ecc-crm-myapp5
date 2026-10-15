module Update.Contacts exposing (update)

{-| Contact messages.
-}

import Api
import Types exposing (..)
import Update.Loaders exposing (loadContacts, pageSize)
import Update.Navigation
import Update.Validate exposing (validateContactForm)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        GotContacts result ->
            case result of
                Ok ( items, total ) ->
                    let
                        prev =
                            case model.contacts of
                                Success d ->
                                    d

                                _ ->
                                    { items = [], query = "", total = 0, offset = 0, limit = pageSize }
                    in
                    ( { model
                        | contacts =
                            Success
                                { items = items
                                , query = prev.query
                                , total = total
                                , offset = prev.offset
                                , limit = pageSize
                                }
                      }
                    , Cmd.none
                    )

                Err message ->
                    ( { model | contacts = Failure message }, Cmd.none )

        UpdatedContactsQuery q ->
            let
                nextContacts =
                    case model.contacts of
                        Success data ->
                            Success { data | query = q, offset = 0 }

                        _ ->
                            Success { items = [], query = q, total = 0, offset = 0, limit = pageSize }
            in
            ( { model | contacts = nextContacts, pendingContactsQuery = Just q }
            , Cmd.none
            )

        FlushContactsSearch ->
            case ( model.token, model.pendingContactsQuery ) of
                ( Just t, Just q ) ->
                    ( { model | pendingContactsQuery = Nothing }
                    , Api.fetchContacts t q pageSize 0 GotContacts
                    )

                _ ->
                    ( { model | pendingContactsQuery = Nothing }, Cmd.none )

        ContactsPageChanged newOffset ->
            case ( model.token, model.contacts ) of
                ( Just t, Success data ) ->
                    ( { model | contacts = Success { data | offset = newOffset } }
                    , Api.fetchContacts t data.query pageSize newOffset GotContacts
                    )

                _ ->
                    ( model, Cmd.none )

        OpenedContactDetail contact ->
            Update.Navigation.update (NavigatedTo (ContactDetail contact.id))
                { model | viewingContact = Just contact, toast = Nothing }

        OpenedAddContact ->
            ( { model
                | contactForm = Just emptyContactForm
                , editingId = Nothing
                , toast = Nothing
              }
            , Cmd.none
            )

        OpenedEditContact contact ->
            ( { model
                | contactForm = Just (contactToForm contact)
                , editingId = Just contact.id
                , toast = Nothing
              }
            , Cmd.none
            )

        RequestedCloseContactForm ->
            case ( model.contactForm, model.deletingContact ) of
                ( _, Just _ ) ->
                    ( { model | deletingContact = Nothing }, Cmd.none )

                ( Just cf, _ ) ->
                    if cf.dirty && not cf.submitting then
                        ( { model | contactForm = Just { cf | confirmDiscard = True } }
                        , Cmd.none
                        )

                    else
                        ( { model | contactForm = Nothing, editingId = Nothing }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ConfirmedCloseContactForm ->
            ( { model | contactForm = Nothing, editingId = Nothing }, Cmd.none )

        CancelledCloseContactForm ->
            case model.contactForm of
                Just cf ->
                    ( { model | contactForm = Just { cf | confirmDiscard = False } }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        UpdatedContactFormField field value ->
            case model.contactForm of
                Just cf ->
                    let
                        updated =
                            case field of
                                "name" ->
                                    { cf | name = value }

                                "email" ->
                                    { cf | email = value }

                                "company" ->
                                    { cf | company = value }

                                "title" ->
                                    { cf | title = value }

                                "phone" ->
                                    { cf | phone = value }

                                "location" ->
                                    { cf | location = value }

                                "stage" ->
                                    { cf | stage = value }

                                "tagInput" ->
                                    { cf | tagInput = value }

                                "notes" ->
                                    { cf | notes = value }

                                _ ->
                                    cf
                    in
                    ( { model
                        | contactForm =
                            Just
                                { updated
                                    | dirty = True
                                    , errors =
                                        List.filter (\( f, _ ) -> f /= field) updated.errors
                                }
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        AddedContactTag ->
            case model.contactForm of
                Just cf ->
                    let
                        tag =
                            String.trim cf.tagInput
                    in
                    if String.isEmpty tag || List.member tag cf.tags then
                        ( { model | contactForm = Just { cf | tagInput = "" } }, Cmd.none )

                    else
                        ( { model
                            | contactForm =
                                Just
                                    { cf
                                        | tags = cf.tags ++ [ tag ]
                                        , tagInput = ""
                                        , dirty = True
                                    }
                          }
                        , Cmd.none
                        )

                Nothing ->
                    ( model, Cmd.none )

        RemovedContactTag tag ->
            case model.contactForm of
                Just cf ->
                    ( { model
                        | contactForm =
                            Just
                                { cf
                                    | tags = List.filter (\t -> t /= tag) cf.tags
                                    , dirty = True
                                }
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        SubmittedContactForm ->
            case ( model.contactForm, model.token ) of
                ( Just cf, Just token ) ->
                    let
                        ( validated, ok ) =
                            validateContactForm cf
                    in
                    if not ok then
                        ( { model | contactForm = Just validated }, Cmd.none )

                    else
                        let
                            cmd =
                                case model.editingId of
                                    Just id ->
                                        Api.updateContact token id validated GotSavedContact

                                    Nothing ->
                                        Api.createContact token validated GotSavedContact
                        in
                        ( { model
                            | contactForm = Just { validated | submitting = True }
                          }
                        , cmd
                        )

                _ ->
                    ( model, Cmd.none )

        GotSavedContact result ->
            let
                wasEdit =
                    model.editingId /= Nothing

                verb =
                    if wasEdit then
                        "Updated "

                    else
                        "Added "
            in
            case result of
                Ok contact ->
                    let
                        freshModel =
                            { model
                                | contactForm = Nothing
                                , editingId = Nothing
                                , viewingContact =
                                    case model.route of
                                        ContactDetail id ->
                                            if id == contact.id then
                                                Just contact

                                            else
                                                model.viewingContact

                                        _ ->
                                            model.viewingContact
                                , toast = Just (verb ++ contact.name)
                            }
                    in
                    ( freshModel, Tuple.second (loadContacts freshModel) )

                Err (FieldErrors fields) ->
                    case model.contactForm of
                        Just cf ->
                            ( { model
                                | contactForm =
                                    Just
                                        { cf
                                            | submitting = False
                                            , errors = fields
                                        }
                              }
                            , Cmd.none
                            )

                        Nothing ->
                            ( model, Cmd.none )

                Err (GenericError message) ->
                    case model.contactForm of
                        Just cf ->
                            ( { model
                                | contactForm =
                                    Just
                                        { cf
                                            | submitting = False
                                            , errors = [ ( "form", message ) ]
                                        }
                              }
                            , Cmd.none
                            )

                        Nothing ->
                            ( model, Cmd.none )

        RequestedDeleteContact contact ->
            ( { model | deletingContact = Just contact }, Cmd.none )

        CancelledDeleteContact ->
            ( { model | deletingContact = Nothing }, Cmd.none )

        ConfirmedDeleteContact ->
            case ( model.deletingContact, model.token ) of
                ( Just contact, Just token ) ->
                    ( model, Api.deleteContact token contact.id (GotDeletedContact contact.id contact.name) )

                _ ->
                    ( model, Cmd.none )

        GotDeletedContact deletedId name result ->
            case result of
                Ok _ ->
                    let
                        backToContacts =
                            case model.route of
                                ContactDetail id ->
                                    id == deletedId

                                _ ->
                                    False

                        freshModel =
                            { model
                                | deletingContact = Nothing
                                , viewingContact =
                                    if backToContacts then
                                        Nothing

                                    else
                                        model.viewingContact
                                , route =
                                    if backToContacts then
                                        Contacts

                                    else
                                        model.route
                                , toast = Just ("Deleted " ++ name)
                            }
                    in
                    ( freshModel, Tuple.second (loadContacts freshModel) )

                Err message ->
                    ( { model
                        | deletingContact = Nothing
                        , toast = Just ("Delete failed: " ++ message)
                      }
                    , Cmd.none
                    )

        _ ->
            ( model, Cmd.none )
