module Main exposing (..)

import Browser
import Browser.Dom
import Dict exposing (Dict, foldl)
import Html exposing (Html, div, span, text)
import Html.Attributes
import Html.Events exposing (on, onClick)
import Html.Lazy
import Json.Decode as Decode
import Ports exposing (..)
import Scroll
import Task
import Debug exposing (toString)


type alias Model =
    { notes : List NoteMeta
    , currentFile : Maybe String
    , settings : Settings
    , cumulativeHeights : Dict Int Int
    , rowHeights :
        Dict Int Int
        -- , renderStart : Int
        -- , renderEnd : Int
    , scrollTop : Float
    , containerHeight : Float
    , buffer : Int
    }


defaultModel : Model
defaultModel =
    { notes = []
    , currentFile = Nothing
    , settings = defaultSettings
    , cumulativeHeights = Dict.empty
    , rowHeights =
        Dict.empty
        -- , renderStart = 0
        -- , renderEnd = -1
    , scrollTop = 0
    , containerHeight = 500
    , buffer = 5
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


defaultSettings : Settings
defaultSettings =
    { includeFolders = [ "Zettel" ]
    , excludeFolders = []
    , showNotesWithoutID = True
    , customIDField = "id"
    }


defaultItemHeight : Int
defaultItemHeight =
    26


main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


init : () -> ( Model, Cmd Msg )
init _ =
    ( defaultModel
    , Cmd.none
    )


type Msg
    = UpdateNotes (List NoteMeta)
    | OpenFile String
    | FileOpened (Maybe String)
    | NoOp
    | Scroll Float
    | RowHeightMeasured Int Int


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UpdateNotes notes ->
            let
                initialHeights =
                    List.indexedMap (\i _ -> ( i, defaultItemHeight )) notes
                        -- Default initial height of 40
                        |>
                            Dict.fromList

                cumulativeHeights =
                    calculateCumulativeHeights initialHeights
            in
                ( { model
                    | notes = notes
                    , rowHeights = initialHeights
                    , cumulativeHeights = cumulativeHeights
                  }
                , Cmd.none
                )

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

        Scroll scrollTop ->
            ( { model | scrollTop = scrollTop }, Cmd.none )

        RowHeightMeasured path height ->
            let
                updatedHeights =
                    Dict.insert path height model.rowHeights

                updatedCumulativeHeights =
                    calculateCumulativeHeights updatedHeights
            in
                ( { model
                    | rowHeights = updatedHeights
                    , cumulativeHeights = updatedCumulativeHeights
                  }
                , Cmd.none
                )


findStartIndex : Float -> Int -> List Float -> Int
findStartIndex scrollTop buffer cumulativeHeights =
    -- Implement binary search or linear logic to find the start index
    0


calculateCumulativeHeights : Dict Int Int -> Dict Int Int
calculateCumulativeHeights heights =
    foldl
        (\index height ( accumHeights, cumulative ) ->
            let
                cumulativeHeight =
                    cumulative + height
            in
                ( Dict.insert index cumulativeHeight accumHeights, cumulativeHeight )
        )
        ( Dict.empty, 0 )
        heights
        |> Tuple.first


calculateVisibleRange : Model -> { start : Int, end : Int }
calculateVisibleRange model =
    let
        start =
            Dict.keys model.cumulativeHeights
                |> List.filter (\i -> toFloat (Maybe.withDefault 0 (Dict.get i model.cumulativeHeights)) > model.scrollTop)
                |> List.head
                |> Maybe.withDefault 0

        buffer =
            model.buffer

        end =
            Dict.keys model.cumulativeHeights
                |> List.filter (\i -> toFloat (Maybe.withDefault 0 (Dict.get i model.cumulativeHeights)) < model.scrollTop + model.containerHeight)
                |> lastElement
                |> Maybe.withDefault (List.length model.notes - 1)
    in
        { start = max 0 (start - buffer), end = min (List.length model.notes) (end + buffer) }


measureRowHeight : Int -> Html.Attribute Msg
measureRowHeight index =
    on "resize"
        (Decode.map
            (\value ->
                case String.toInt value of
                    Just intValue ->
                        RowHeightMeasured index intValue

                    Nothing ->
                        RowHeightMeasured index 0
            )
            Decode.string
        )


lastElement : List a -> Maybe a
lastElement list =
    list
        |> List.reverse
        |> List.head



-- findEndIndex : Float -> Float -> Int -> List Float -> Int
-- findEndIndex scrollTop containerHeight buffer cumulativeHeights =
--     -- Implement logic to find the end index
--     List.length cumulativeHeights
-- recalculateHeights : Model -> List Float -> Model
-- recalculateHeights model newHeights =
--     -- Update heights and recalculate cumulative heights
--     model
-- getContainerHeight : Task.Task Browser.Dom.Error Float
-- getContainerHeight =
--     Task.map
--         (\element -> element.element.height)
--         (Browser.Dom.getElement "note-id-list")
-- measureRowHeights : Int -> Int -> Cmd Msg
-- measureRowHeights start end =
--     getContainerHeight
--         |> Task.attempt
--             (\result ->
--                 case result of
--                     Ok height ->
--                         Debug.log "Container height"
--                             UpdateContainerHeight
--                             (round height)
--                     -- Convert to Int
--                     Err _ ->
--                         Debug.log "Container height failed"
--                             NoOp
--             )


slice : Int -> Int -> List a -> List a
slice start end list =
    list
        |> List.drop start
        |> List.take (end - start)


view : Model -> Html Msg
view model =
    let
        visibleRange =
            calculateVisibleRange model

        visibleItems =
            slice visibleRange.start visibleRange.end model.notes
    in
        -- div
        --     [ Html.Attributes.class "note-id-list"
        --     , Html.Attributes.id "note-id-list"
        --     ]
        --     (List.map (\note -> Html.Lazy.lazy2 viewNote note model.currentFile) model.notes)
        div [ Html.Attributes.class "virtual-list", onScroll Scroll ]
            [ div [ Html.Attributes.style "height" (String.fromInt (totalHeight model) ++ "px") ] []
            , div []
                (List.indexedMap (viewRow model) visibleItems)
            ]


onScroll : (Float -> msg) -> Html.Attribute msg
onScroll msg =
    on "scroll" (Decode.map msg scrollTopDecoder)


scrollTopDecoder : Decode.Decoder Float
scrollTopDecoder =
    Decode.field "target" (Decode.field "scrollTop" Decode.float)


totalHeight : Model -> Int
totalHeight model =
    case Dict.get (List.length model.notes - 1) model.cumulativeHeights of
        Just height ->
            height

        Nothing ->
            0


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


viewRow : Model -> Int -> NoteMeta -> Html Msg
viewRow model index note =
    let
        top =
            Debug.log "Top Position" (Dict.get (index - 1) model.cumulativeHeights)

        resizeDecoder : Decode.Decoder Msg
        resizeDecoder =
            Decode.field "target"
                (Decode.field "value"
                    (Decode.string
                        |> Decode.andThen
                            (\value ->
                                case String.toInt value of
                                    Just intValue ->
                                        Decode.succeed (RowHeightMeasured index intValue)

                                    Nothing ->
                                        Decode.succeed (RowHeightMeasured index 0)
                            )
                    )
                )
    in
        div
            [ Html.Attributes.id note.filePath
            , Html.Attributes.style "transform" ("translateY(" ++ toString top ++ "px)")
            , onClick (OpenFile note.filePath)
            , on "resize" resizeDecoder
            ]
            [ div
                [ Html.Attributes.classList
                    [ ( "tree-item-self", True )
                    , ( "is-clickable", True )
                    , ( "is-active", Just note.filePath == model.currentFile )
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
