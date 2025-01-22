module Main exposing (..)

import Browser
import Html exposing (Html, div, span)
import Html.Attributes
import Html.Events exposing (onClick)
import Ports exposing (..)
import Scroll
import Task


-- Define the model to store notes


type alias Model =
    { notes : List NoteMeta
    , currentFile : Maybe String
    }


type alias NoteMeta =
    { title : String
    , id : Maybe String
    , filePath : String
    }


type alias Settings =
    { includeFolders : List String
    , excludeFolders : List String
    , showNotesWithoutID : Bool
    , customIDField : String
    }


exampleSettings : Settings
exampleSettings =
    { includeFolders = [ "Zettel" ]
    , excludeFolders = []
    , showNotesWithoutID = True
    , customIDField = "id"
    }


main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


init : () -> ( Model, Cmd Msg )
init _ =
    ( { notes = [], currentFile = Nothing }, Cmd.none )


type Msg
    = UpdateNotes (List NoteMeta)
    | OpenFile String
    | FileOpened (Maybe String)
    | NoOp


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    (Debug.log "Processing message" msg)
        |> (\_ ->
                case msg of
                    UpdateNotes notes ->
                        ( { model | notes = notes }, Cmd.none )

                    OpenFile filePath ->
                        ( model, Ports.openFile filePath )

                    FileOpened filePath ->
                        case filePath of
                            Just path ->
                                let
                                    scrollCmd =
                                        Scroll.scrollElementY "note-id-list" path 0.5 0.5
                                            |> Task.attempt
                                                (\result ->
                                                    case result of
                                                        Ok _ ->
                                                            Debug.log "Scroll succeeded" NoOp

                                                        Err err ->
                                                            Debug.log ("Scroll failed with error: " ++ Debug.toString err) NoOp
                                                )
                                in
                                    ( { model | currentFile = Just path }, scrollCmd )

                            Nothing ->
                                ( model, Cmd.none )

                    NoOp ->
                        ( model, Cmd.none )
           )


view : Model -> Html Msg
view model =
    div
        [ Html.Attributes.class "note-id-list"
        , Html.Attributes.id "note-id-list"
        ]
        (List.map (\note -> viewNote note model.currentFile) model.notes)


viewNote : NoteMeta -> Maybe String -> Html Msg
viewNote note currentFile =
    div
        [ Html.Attributes.id note.filePath
        , onClick (OpenFile note.filePath)
        ]
        [ div
            [ Html.Attributes.classList
                [ ( "tree-item-self", True )
                , ( "is-clickable", True )
                , ( "is-active", Just note.filePath == currentFile )
                ]
            , Html.Attributes.attribute "data-file-path" note.filePath
            ]
            [ div
                [ Html.Attributes.class "tree-item-inner" ]
                (case note.id of
                    Just id ->
                        [ span [ Html.Attributes.class "note-id" ] [ Html.text (id ++ ": ") ]
                        , Html.text note.title
                        ]

                    Nothing ->
                        [ Html.text note.title ]
                )
            ]
        ]


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Ports.receiveNotes UpdateNotes
        , Ports.receiveFileOpen FileOpened
        ]
