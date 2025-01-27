module VirtualList exposing (Model, init, update, Msg, scrollToItem, view, updateItems)

import Browser.Dom
import Debug exposing (toString)
import Dict exposing (Dict, foldl)
import Html exposing (Html, div)
import Html.Attributes
import Html.Events exposing (on)
import Json.Decode as Decode
import List.Extra exposing (..)
import Task


type alias Model a =
    { items : List a
    , containerHeight : Float
    , cumulativeHeights : Dict Int Float
    , rowHeights : Dict Int RowHeight
    , scrollTop : Float
    , buffer : Int
    , visibleRange : ( Int, Int )
    }


defaultItemHeight : Float
defaultItemHeight =
    26


type Msg
    = RowHeightMeasured Int (Result Browser.Dom.Error Browser.Dom.Element)
    | Scrolled
    | NoOp
    | ViewportUpdated (Result Browser.Dom.Error Browser.Dom.Viewport)


type RowHeight
    = Measured Float
    | Default Float


init : Model a
init =
    { items = []
    , containerHeight = 500
    , cumulativeHeights = Dict.empty
    , rowHeights = Dict.empty
    , scrollTop = 0
    , buffer = 5
    , visibleRange = ( 0, 20 )
    }


update : Msg -> Model a -> ( Model a, Cmd Msg )
update msg model =
    case msg of
        RowHeightMeasured index result ->
            handleRowHeightMeasurementResult model index result

        Scrolled ->
            ( model, measureViewport )

        NoOp ->
            ( model, Cmd.none )

        ViewportUpdated result ->
            handleViewportUpdate model result


updateItems : (a -> String) -> Model a -> List a -> ( Model a, Cmd Msg )
updateItems getId model newNotes =
    let
        existingHeights =
            newNotes
                |> List.filterMap
                    (\note ->
                        findIndex (\oldNote -> getId oldNote == getId note) model.items
                            |> Maybe.andThen (\index -> Dict.get index model.rowHeights)
                            |> Maybe.map (\height -> ( getId note, height ))
                    )
                |> Dict.fromList

        updatedRowHeights =
            newNotes
                |> List.indexedMap
                    (\i note ->
                        case Dict.get (getId note) existingHeights of
                            Just height ->
                                ( i, height )

                            Nothing ->
                                ( i, Default defaultItemHeight )
                    )
                |> Dict.fromList

        updatedCumulativeHeights =
            calculateCumulativeHeights updatedRowHeights
    in
        ( { model
            | items = newNotes
            , cumulativeHeights = updatedCumulativeHeights
            , rowHeights = updatedRowHeights
          }
        , measureViewport
        )


findIndex : (a -> Bool) -> List a -> Maybe Int
findIndex predicate notes =
    notes
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, note ) -> predicate note)
        |> List.head
        |> Maybe.map Tuple.first


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


calculateVisibleRange : Model a -> Float -> Float -> ( Int, Int )
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


handleRowHeightMeasurementResult : Model a -> Int -> Result Browser.Dom.Error Browser.Dom.Element -> ( Model a, Cmd Msg )
handleRowHeightMeasurementResult model index result =
    case result of
        Ok element ->
            updateRowHeight model index element

        Err _ ->
            ( model, Cmd.none )


updateRowHeight : Model a -> Int -> Browser.Dom.Element -> ( Model a, Cmd Msg )
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


handleViewportUpdate : Model a -> Result Browser.Dom.Error Browser.Dom.Viewport -> ( Model a, Cmd Msg )
handleViewportUpdate model result =
    case result of
        Ok viewport ->
            handleViewportUpdateSucceeded model viewport

        Err _ ->
            ( model, Cmd.none )


handleViewportUpdateSucceeded : Model a -> Browser.Dom.Viewport -> ( Model a, Cmd Msg )
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


scrollToItem : Model a -> Int -> Cmd Msg
scrollToItem model index =
    let
        elementStart =
            Maybe.withDefault 0 (Dict.get (index - 1) model.cumulativeHeights)
    in
        scrollToPosition virtualListId elementStart model.containerHeight


scrollToPosition : String -> Float -> Float -> Cmd Msg
scrollToPosition targetId elementStart containerHeight =
    let
        position =
            elementStart - 0.5 * containerHeight
    in
        Browser.Dom.setViewportOf targetId 0 position
            |> Task.attempt (\_ -> NoOp)


totalHeight : Model a -> Float
totalHeight model =
    case Dict.get (Dict.size model.cumulativeHeights - 1) model.cumulativeHeights of
        Just height ->
            height

        Nothing ->
            0


view : (a -> Int -> Html msg) -> Model a -> (Msg -> msg) -> Html msg
view renderRow model toSelf =
    let
        ( start, end ) =
            model.visibleRange

        visibleItems =
            slice start end model.items

        rows =
            List.indexedMap
                (\localIndex item ->
                    let
                        globalIndex =
                            start + localIndex
                    in
                        -- viewRow model globalIndex item
                        renderVirtualRow globalIndex model (renderRow item globalIndex)
                )
                visibleItems
    in
        div
            [ Html.Attributes.class "virtual-list"
            , Html.Attributes.id virtualListId
              -- Height needs to be in the element for fast measurement
            , Html.Attributes.style "height" "100%"
            , Html.Attributes.style "overflow" "auto"
            , onScroll (toSelf Scrolled)
            ]
            [ div
                [ Html.Attributes.style "height" (String.fromFloat (totalHeight model) ++ "px")
                , Html.Attributes.style "position" "relative"
                ]
                [ div [ Html.Attributes.class "note-id-list-items" ]
                    rows
                ]
            ]


renderVirtualRow : Int -> Model a -> Html msg -> Html msg
renderVirtualRow index model renderRow =
    let
        top =
            Maybe.withDefault 0 (Dict.get (index - 1) model.cumulativeHeights)
    in
        div
            [ Html.Attributes.id (rowId index)
            , Html.Attributes.style "transform" ("translateY(" ++ toString top ++ "px)")
            , Html.Attributes.style "position" "absolute"
            ]
            [ renderRow
            ]


slice : Int -> Int -> List a -> List a
slice start end list =
    list
        |> List.drop start
        |> List.take (end - start)


onScroll : msg -> Html.Attribute msg
onScroll msg =
    on "scroll" (Decode.succeed msg)


measureViewport : Cmd Msg
measureViewport =
    Task.attempt ViewportUpdated (Browser.Dom.getViewportOf virtualListId)


virtualListId : String
virtualListId =
    "virtual-list"
