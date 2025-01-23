module Main exposing (..)

import Browser
import Browser.Dom
import Html exposing (Html, div, span)
import Html.Attributes
import Html.Events exposing (onClick)
import InfiniteList
import Ports exposing (..)
import Scroll
import Task


-- Define the model to store notes


type alias Model =
    { notes : List NoteMeta
    , currentFile : Maybe String
    , settings : Settings
    , infiniteList : InfiniteList.Model
    , containerHeight : Int
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
    ( { notes = []
      , currentFile = Nothing
      , settings = exampleSettings
      , infiniteList = InfiniteList.init
      , containerHeight = 500
      }
    , getContainerHeightCmd
    )


type Msg
    = UpdateNotes (List NoteMeta)
    | OpenFile String
    | FileOpened (Maybe String)
    | NoOp
    | InfiniteListMsg InfiniteList.Model
    | UpdateContainerHeight Int


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
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

        InfiniteListMsg infiniteList ->
            ( { model | infiniteList = infiniteList }, Cmd.none )

        UpdateContainerHeight height ->
            ( { model | containerHeight = height }, Cmd.none )


config : Model -> InfiniteList.Config NoteMeta Msg
config model =
    InfiniteList.config
        { itemView = itemView model.currentFile
        , itemHeight = InfiniteList.withConstantHeight 50
        , containerHeight = model.containerHeight
        }
        |> InfiniteList.withClass "note-id-list-scroll"


getContainerHeight : Task.Task Browser.Dom.Error Float
getContainerHeight =
    Task.map
        (\element -> element.element.height)
        (Browser.Dom.getElement "note-id-list")


getContainerHeightCmd : Cmd Msg
getContainerHeightCmd =
    getContainerHeight
        |> Task.attempt
            (\result ->
                case result of
                    Ok height ->
                        Debug.log "Container height"
                            UpdateContainerHeight
                            (round height)

                    -- Convert to Int
                    Err _ ->
                        Debug.log "Container height failed"
                            NoOp
            )


itemView : Maybe String -> Int -> Int -> NoteMeta -> Html Msg
itemView currentFile _ _ item =
    viewNote item currentFile


view : Model -> Html Msg
view model =
    div
        [ Html.Attributes.class "note-id-list"
        , Html.Attributes.id "note-id-list"
        , InfiniteList.onScroll InfiniteListMsg
        , Html.Attributes.style "height" "100%"
        ]
        -- (List.map (\note -> Html.Lazy.lazy2 viewNote note model.currentFile) model.notes)
        [ InfiniteList.view (config model) model.infiniteList model.notes ]


viewNote : NoteMeta -> Maybe String -> Html Msg
viewNote note currentFile =
    div
        [ Html.Attributes.id note.filePath
        , onClick (OpenFile note.filePath)
        , Html.Attributes.style "height" "26px"
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
