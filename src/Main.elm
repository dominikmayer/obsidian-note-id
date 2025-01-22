module Main exposing (..)

import Browser
import Html exposing (Html, div, text, ul, li)
import Ports exposing (..)


-- Define the model to store notes


type alias Model =
    List Note


type alias Note =
    { title : String
    , id : String
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


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpdateNotes notes ->
            ( Debug.log "Received notes in Elm" notes, Cmd.none )


view : Model -> Html Msg
view notes =
    div []
        [ text "Elm app running"
        , ul [] (List.map viewNote notes)
        ]


viewNote : Note -> Html msg
viewNote note =
    li [] [ text (note.title ++ " (ID: " ++ note.id ++ ")") ]


subscriptions : Model -> Sub Msg
subscriptions _ =
    Ports.receiveNotes UpdateNotes
