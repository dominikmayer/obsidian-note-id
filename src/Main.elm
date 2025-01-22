module Main exposing (..)

import Browser
import Html exposing (Html, div, text, span)
import Html.Attributes exposing (class, style, attribute)
import Ports exposing (..)
import Html.Events exposing (onClick)


-- Define the model to store notes


type alias Model =
    List Note


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
    Debug.log "Elm app initialized" ( [], Cmd.none )


type Msg
    = UpdateNotes (List Note)
    | OpenFile String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpdateNotes notes ->
            ( notes, Cmd.none )

        OpenFile filePath ->
            ( model, Ports.openFile filePath )


view : Model -> Html Msg
view notes =
    div []
        [ text "Elm app running"
        , div
            [ Html.Attributes.class "note-id-list"
            ]
            (List.map viewNote notes)
        ]


viewNote : Note -> Html Msg
viewNote note =
    div
        [ Html.Attributes.class ""
        , onClick (OpenFile note.filePath)
          -- Attach the click handler
        ]
        [ div
            [ Html.Attributes.class "tree-item-self is-clickable"
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
    Ports.receiveNotes UpdateNotes
