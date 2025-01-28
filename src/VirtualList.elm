module VirtualList
    exposing
        ( init
        , defaultConfig
        , update
        , view
        , updateItems
        , scrollToItem
        , Model
        , Msg
        )

import Browser.Dom
import Dict exposing (Dict, foldl)
import Html exposing (Html, div)
import Html.Attributes
import Html.Events exposing (on)
import Json.Decode as Decode
import List.Extra exposing (..)
import Task


type alias Config =
    { buffer : Int
    , height : Float
    , defaultItemHeight : Float
    }


defaultConfig : Config
defaultConfig =
    { buffer = 5
    , height = 500
    , defaultItemHeight = 26
    }


type alias Model a =
    { items : List a
    , height : Float
    , defaultItemHeight : Float
    , buffer : Int
    , visibleRange : ( Int, Int )
    , rowHeights : Dict Int RowHeight
    , cumulativeHeights : Dict Int Float
    , scrollTop : Float
    , previousScrollTop : Float
    }


type Msg
    = RowHeightMeasured Int (Result Browser.Dom.Error Browser.Dom.Element)
    | Scrolled
    | NoOp
    | ViewportUpdated (Result Browser.Dom.Error Browser.Dom.Viewport)


type RowHeight
    = Measured Float
    | Default Float


init : Config -> Model a
init options =
    { items = []
    , height = options.height
    , buffer = options.buffer
    , defaultItemHeight = options.defaultItemHeight
    , visibleRange = ( 0, 20 )
    , rowHeights = Dict.empty
    , cumulativeHeights = Dict.empty
    , scrollTop = 0
    , previousScrollTop = 0
    }


update : Msg -> Model a -> ( Model a, Cmd Msg )
update msg model =
    case msg of
        RowHeightMeasured index result ->
            handleRowHeightMeasurementResult model index result

        Scrolled ->
            let
                scrollSpeed =
                    abs (model.scrollTop - model.previousScrollTop)

                newBuffer =
                    if scrollSpeed > 200 then
                        30
                    else if scrollSpeed > 100 then
                        20
                    else if scrollSpeed > 50 then
                        10
                    else
                        5
            in
                ( { model | buffer = newBuffer }, measureViewport )

        NoOp ->
            ( model, Cmd.none )

        ViewportUpdated result ->
            handleViewportUpdate model result


updateItems : (a -> String) -> Model a -> List a -> ( Model a, Cmd Msg )
updateItems getId model newItems =
    let
        heightKnown =
            (\item ->
                findIndex (\oldItem -> getId oldItem == getId item) model.items
                    |> Maybe.andThen (\index -> Dict.get index model.rowHeights)
                    |> Maybe.map (\height -> ( getId item, height ))
            )

        existingHeights =
            newItems
                |> List.filterMap heightKnown
                |> Dict.fromList

        knownOrDefaultHeight =
            (\index item ->
                case Dict.get (getId item) existingHeights of
                    Just height ->
                        ( index, height )

                    Nothing ->
                        ( index, Default model.defaultItemHeight )
            )

        updatedRowHeights =
            newItems
                |> List.indexedMap knownOrDefaultHeight
                |> Dict.fromList

        updatedCumulativeHeights =
            calculateCumulativeHeights updatedRowHeights
    in
        ( { model
            | items = newItems
            , cumulativeHeights = updatedCumulativeHeights
            , rowHeights = updatedRowHeights
          }
        , measureViewport
        )


findIndex : (a -> Bool) -> List a -> Maybe Int
findIndex predicate items =
    items
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, item ) -> predicate item)
        |> List.head
        |> Maybe.map Tuple.first


calculateCumulativeHeights : Dict Int RowHeight -> Dict Int Float
calculateCumulativeHeights heights =
    foldl insertCumulativeHeight ( Dict.empty, 0 ) heights
        |> Tuple.first


insertCumulativeHeight : comparable -> RowHeight -> ( Dict comparable Float, Float ) -> ( Dict comparable Float, Float )
insertCumulativeHeight index rowHeight ( cumulativeHeights, cumulative ) =
    let
        height =
            rowHeightToFloat rowHeight

        cumulativeHeight =
            cumulative + height
    in
        ( Dict.insert index cumulativeHeight cumulativeHeights, cumulativeHeight )


rowHeightToFloat : RowHeight -> Float
rowHeightToFloat rowHeight =
    case rowHeight of
        Measured value ->
            value

        Default value ->
            value


calculateVisibleRange : Model a -> Float -> Float -> ( Int, Int )
calculateVisibleRange model scrollTop containerHeight =
    let
        height =
            (\index -> Maybe.withDefault 0 (Dict.get index model.cumulativeHeights))

        start =
            Dict.keys model.cumulativeHeights
                |> List.filter (\index -> height index >= scrollTop)
                |> List.head
                |> Maybe.withDefault 0

        end =
            Dict.keys model.cumulativeHeights
                |> List.filter (\index -> height index < scrollTop + containerHeight)
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
            handleSuccessfulViewportUpdate model viewport

        Err _ ->
            ( model, Cmd.none )


handleSuccessfulViewportUpdate : Model a -> Browser.Dom.Viewport -> ( Model a, Cmd Msg )
handleSuccessfulViewportUpdate model viewport =
    let
        newScrollTop =
            viewport.viewport.y

        newContainerHeight =
            viewport.viewport.height

        (( start, end ) as visibleRange) =
            calculateVisibleRange model newScrollTop newContainerHeight

        unmeasuredIndices =
            List.range start (end - 1)
                |> List.filter (isUnmeasured model.rowHeights)

        measureCmds =
            unmeasuredIndices
                |> List.map measureRow
                |> Cmd.batch
    in
        ( { model
            | height = newContainerHeight
            , scrollTop = newScrollTop
            , previousScrollTop = model.scrollTop
            , visibleRange = visibleRange
          }
        , measureCmds
        )


isUnmeasured : Dict comparable RowHeight -> comparable -> Bool
isUnmeasured rowHeights index =
    case Dict.get index rowHeights of
        Just (Default _) ->
            True

        Just (Measured _) ->
            False

        Nothing ->
            True


measureRow : Int -> Cmd Msg
measureRow index =
    Browser.Dom.getElement (rowId index)
        |> Task.attempt (RowHeightMeasured index)


rowId : Int -> String
rowId index =
    "virtual-list-row-" ++ String.fromInt index


scrollToItem : Model a -> Int -> Cmd Msg
scrollToItem model index =
    let
        elementStart =
            Maybe.withDefault 0 (Dict.get (index - 1) model.cumulativeHeights)
    in
        scrollToPosition virtualListId elementStart model.height


scrollToPosition : String -> Float -> Float -> Cmd Msg
scrollToPosition targetId elementStart containerHeight =
    let
        position =
            elementStart - 0.5 * containerHeight
    in
        Browser.Dom.setViewportOf targetId 0 position
            |> Task.attempt (\_ -> NoOp)


view : (a -> Int -> Html msg) -> Model a -> (Msg -> msg) -> Html msg
view renderRow model toSelf =
    let
        ( start, end ) =
            model.visibleRange

        visibleItems =
            slice start end model.items

        height =
            String.fromFloat (totalHeight model.cumulativeHeights)

        rows =
            List.indexedMap
                (\localIndex item ->
                    let
                        globalIndex =
                            start + localIndex
                    in
                        renderRow item globalIndex
                            |> renderVirtualRow globalIndex model.cumulativeHeights
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
            [ renderSpacer height rows ]


totalHeight : Dict Int Float -> Float
totalHeight cumulativeHeights =
    let
        lastItemIndex =
            Dict.size cumulativeHeights - 1
    in
        case Dict.get lastItemIndex cumulativeHeights of
            Just height ->
                height

            Nothing ->
                0


renderSpacer : String -> List (Html msg) -> Html msg
renderSpacer height rows =
    div
        [ Html.Attributes.style "height" (height ++ "px")
        , Html.Attributes.style "position" "relative"
        ]
        [ div [] rows ]


renderVirtualRow : Int -> Dict Int Float -> Html msg -> Html msg
renderVirtualRow index cumulativeHeights renderRow =
    let
        top =
            Maybe.withDefault 0 (Dict.get (index - 1) cumulativeHeights)
    in
        div
            [ Html.Attributes.id (rowId index)
            , Html.Attributes.style "transform" ("translateY(" ++ String.fromFloat top ++ "px)")
            , Html.Attributes.style "position" "absolute"
            , Html.Attributes.class "virtual-list-item"
            ]
            [ renderRow ]


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
