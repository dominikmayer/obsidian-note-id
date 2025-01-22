module Main exposing (..)

import Browser
import Html exposing (Html, div, text, span)
import Html.Attributes exposing (class, style, attribute)
import Ports exposing (..)
import Html.Events exposing (onClick)


-- Define the model to store notes


type alias Model =
    { notes : List Note
    , currentFile : Maybe String
    }


type alias Note =
    { title : String
    , id : Maybe String
    , filePath : String
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
    = UpdateNotes (List Note)
    | OpenFile String
    | FileOpened (Maybe String)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpdateNotes notes ->
            ( { model | notes = notes }, Cmd.none )

        OpenFile filePath ->
            ( model, Ports.openFile filePath )

        FileOpened filePath ->
            ( { model | currentFile = filePath }, Cmd.none )


view : Model -> Html Msg
view model =
    div []
        [ text "Elm app running"
        , div
            [ Html.Attributes.class "note-id-list"
            ]
            (List.map (\note -> viewNote note model.currentFile) model.notes)
        ]


viewNote : Note -> Maybe String -> Html Msg
viewNote note currentFile =
    div
        [ Html.Attributes.class ""
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
