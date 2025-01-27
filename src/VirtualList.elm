module VirtualList exposing (Model, init, RowHeight(..), calculateCumulativeHeights, update, Msg(..), handleViewportUpdate, rowId, scrollToItem)

-- module VirtualList exposing (..)

import Browser.Dom
import Dict exposing (Dict, foldl)
import Html exposing (Html, div)
import Html.Attributes
import Html.Events exposing (on, onClick)
import List.Extra exposing (..)
import Task


type alias Model =
    { containerHeight : Float
    , cumulativeHeights : Dict Int Float
    , rowHeights : Dict Int RowHeight
    , scrollTop : Float
    , buffer : Int
    , visibleRange : ( Int, Int )
    }


type Msg
    = RowHeightMeasured Int (Result Browser.Dom.Error Browser.Dom.Element)
    | NoOp


type RowHeight
    = Measured Float
    | Default Float


init : Model
init =
    { containerHeight = 500
    , cumulativeHeights = Dict.empty
    , rowHeights = Dict.empty
    , scrollTop = 0
    , buffer = 5
    , visibleRange = ( 0, 20 )
    }


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        RowHeightMeasured index result ->
            handleRowHeightMeasurementResult model index result

        NoOp ->
            ( model, Cmd.none )


rowHeightToFloat : RowHeight -> Float
rowHeightToFloat rowHeight =
    case rowHeight of
        Measured value ->
            value

        Default value ->
            value


calculateCumulativeHeights : Dict Int RowHeight -> Dict Int Float
calculateCumulativeHeights heights =
    foldl
        (\index rowHeight ( accumHeights, cumulative ) ->
            let
                height =
                    rowHeightToFloat rowHeight

                cumulativeHeight =
                    cumulative + height
            in
                ( Dict.insert index cumulativeHeight accumHeights, cumulativeHeight )
        )
        ( Dict.empty, 0 )
        heights
        |> Tuple.first


calculateVisibleRange : Model -> Float -> Float -> ( Int, Int )
calculateVisibleRange model scrollTop containerHeight =
    let
        start =
            Dict.keys model.cumulativeHeights
                |> List.filter (\i -> Maybe.withDefault 0 (Dict.get i model.cumulativeHeights) >= scrollTop)
                |> List.head
                |> Maybe.withDefault 0

        end =
            Dict.keys model.cumulativeHeights
                |> List.filter (\i -> Maybe.withDefault 0 (Dict.get i model.cumulativeHeights) < scrollTop + containerHeight)
                |> last
                |> Maybe.withDefault (Dict.size model.rowHeights - 1)

        buffer =
            model.buffer
    in
        ( (max 0 (start - buffer)), (min (Dict.size model.rowHeights) (end + buffer)) )


handleRowHeightMeasurementResult : Model -> Int -> Result Browser.Dom.Error Browser.Dom.Element -> ( Model, Cmd Msg )
handleRowHeightMeasurementResult model index result =
    case result of
        Ok element ->
            updateRowHeight model index element

        Err _ ->
            ( model, Cmd.none )


updateRowHeight : Model -> Int -> Browser.Dom.Element -> ( Model, Cmd Msg )
updateRowHeight model index element =
    let
        height =
            element.element.height

        updatedRowHeights =
            Dict.insert index (Measured height) model.rowHeights

        updatedCumulativeHeights =
            calculateCumulativeHeights updatedRowHeights
    in
        ( { model
            | cumulativeHeights = updatedCumulativeHeights
            , rowHeights = updatedRowHeights
          }
        , Cmd.none
        )


handleViewportUpdate : Model -> Result Browser.Dom.Error Browser.Dom.Viewport -> ( Model, Cmd Msg )
handleViewportUpdate model result =
    case result of
        Ok viewport ->
            handleViewportUpdateSucceeded model viewport

        Err _ ->
            ( model, Cmd.none )


handleViewportUpdateSucceeded : Model -> Browser.Dom.Viewport -> ( Model, Cmd Msg )
handleViewportUpdateSucceeded model viewport =
    let
        newScrollTop =
            viewport.viewport.y

        newContainerHeight =
            viewport.viewport.height

        (( start, end ) as visibleRange) =
            calculateVisibleRange model newScrollTop newContainerHeight

        unmeasuredIndices =
            List.range start (end - 1)
                |> List.filter
                    (\index ->
                        case Dict.get index model.rowHeights of
                            Just (Default _) ->
                                True

                            Just (Measured _) ->
                                False

                            Nothing ->
                                True
                    )

        measureCmds =
            unmeasuredIndices
                |> List.map
                    (\index ->
                        Browser.Dom.getElement (rowId index)
                            |> Task.attempt (RowHeightMeasured index)
                    )
                |> Cmd.batch
    in
        ( { model
            | containerHeight = newContainerHeight
            , scrollTop = newScrollTop
            , visibleRange = visibleRange
          }
        , measureCmds
        )


rowId : Int -> String
rowId index =
    "virtual-list-row-" ++ String.fromInt index


scrollToItem : Model -> Int -> Cmd Msg
scrollToItem model index =
    let
        elementStart =
            Maybe.withDefault 0 (Dict.get (index - 1) model.cumulativeHeights)
    in
        scrollToPosition "virtual-list" elementStart model.containerHeight


scrollToPosition : String -> Float -> Float -> Cmd Msg
scrollToPosition targetId elementStart containerHeight =
    let
        position =
            elementStart - 0.5 * containerHeight
    in
        Browser.Dom.setViewportOf targetId 0 position
            |> Task.attempt (\_ -> NoOp)



-- viewRow : Model -> Int -> NoteMeta -> Html Msg
-- viewRow model index note =
--     let
--         top =
--             Maybe.withDefault 0 (Dict.get (index - 1) model.cumulativeHeights)
--     in
--         div
--             [ Html.Attributes.id note.filePath
--             , Html.Attributes.classList
--                 [ ( "tree-item-self", True )
--                 , ( "is-clickable", True )
--                 , ( "is-active", Just note.filePath == model.currentFile )
--                 ]
--             , Html.Attributes.style "transform" ("translateY(" ++ toString top ++ "px)")
--             , Html.Attributes.attribute "data-path" note.filePath
--             , onClick (NoteClicked note.filePath)
--             , Mouse.onContextMenu (\event -> ContextMenuTriggered event note.filePath)
--             ]
--             [ div
--                 [ Html.Attributes.class "tree-item-inner" ]
--                 (case note.id of
--                     Just id ->
--                         [ Html.span [ Html.Attributes.class "note-id" ] [ Html.text (id ++ ": ") ]
--                         , Html.text note.title
--                         ]
--                     Nothing ->
--                         [ Html.text note.title ]
--                 )
--             ]
