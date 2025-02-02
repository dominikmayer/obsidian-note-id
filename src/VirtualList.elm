module VirtualList
    exposing
        ( init
        , initWithConfig
        , defaultConfig
        , update
        , view
        , setItems
        , setItemsAndRemeasure
        , setItemsAndRemeasureAll
        , scrollToItem
        , Model
        , Msg
        , Alignment(..)
        )

{-| Efficiently renders large lists by only rendering the visible items in the viewport plus a configurable buffer.

It does so by measuring the height of the displayed elements. To prevent a scrambled UI the list is by default hidden until the initial measurement is done.

In case you know the heights in advance you might get a better performance by using [`FabienHenon/elm-infinite-list-view`](https://package.elm-lang.org/packages/FabienHenon/elm-infinite-list-view/latest/InfiniteList).

# How it works

To use a virtual list you need to connect it to your `model`, `view` and `update` functions.

    module Main exposing (..)

    import Html exposing (Html, div, text)
    import VirtualList

    type alias Model =
        { virtualList : VirtualList.Model
        -- other fields
        }

    type Msg
        = VirtualListMsg VirtualList.Msg
        -- other messages

    update : Msg -> Model -> ( Model, Cmd Msg )
    update msg model =
        case msg of
            VirtualListMsg virtualListMsg ->
                let
                    ( virtualListModel, virtualListCmd ) =
                        VirtualList.update virtualListMsg model.virtualList
                in
                    ( { model | virtualList = virtualListModel }, Cmd.map VirtualListMsg virtualListCmd )
            -- other cases

    view : Model -> Html Msg
    view model =
        VirtualList.view (renderRow model) model.virtualList VirtualListMsg

    renderRow : Model -> String -> Html Msg
    renderRow model id =
        div [] [text id]

@docs Model, defaultConfig, init, initWithConfig, Msg, update

# Rendering

@docs view

# Updating the Items

@docs setItems, setItemsAndRemeasure, setItemsAndRemeasureAll

# Scrolling

@docs scrollToItem, Alignment(..)
-}

import Browser.Dom
import Dict exposing (Dict, foldl)
import Html exposing (Html, div)
import Html.Attributes
import Html.Events exposing (on)
import Html.Lazy exposing (lazy2)
import Json.Decode as Decode
import List.Extra
import Set exposing (Set)
import Task


type alias Config =
    { listId : String
    , initialHeight : Float
    , defaultItemHeight : Float
    , showListDuringInitialMeasure : Bool
    , buffer : Int
    , dynamicBuffer : Bool
    }


{-| A default configuration for initializing the virtual list model.

This configuration provides sensible defaults that work for most use cases. You can customize
it to better suit your needs by creating a new `Config` record with adjusted values.

    defaultConfig : Config
    defaultConfig =
        -- The id of the virtual list DOM element
        { listId = "virtual-list"
        -- The height of the list before the viewport is first measured
        , initialHeight = 500
        -- The height of items before they are first being measured
        , defaultItemHeight = 26
        -- Show the list while loading even if this means items are oddly spaced
        , showListDuringInitialMeasure = False
        -- The number of items that are loaded outside the visual range
        , buffer = 5
        -- Whether the buffer should be increased on high scroll speeds
        , dynamicBuffer = True
        }

If you set the buffer to `0` then elements get measured while they are already in view. This might not look good.
-}
defaultConfig : Config
defaultConfig =
    { listId = "virtual-list"
    , initialHeight = 500
    , defaultItemHeight = 26
    , showListDuringInitialMeasure = False
    , buffer = 5
    , dynamicBuffer = True
    }


{-| The `Model` of the virtual list. You need to include it in your model:

    type alias Model =
        { virtualList : VirtualList.Model
        -- other fields
        }

You create one with the `init` function.
-}
type alias Model =
    { listId : String
    , ids : List String
    , height : Float
    , defaultItemHeight : Float
    , baseBuffer : Int
    , dynamicBuffer : Bool
    , buffer : Int
    , showList : Bool
    , visibleRange : ( Int, Int )
    , firstRender : Bool
    , unmeasuredRows : Set Int
    , rowHeights : Dict Int RowHeight
    , cumulativeHeights : Dict Int Float
    , scrollTop : Float
    , previousScrollTop : Float
    }


{-| Initialize the model of the virtual list with the default configuration.
-}
init : Model
init =
    initWithConfig defaultConfig


{-| Initialize the model of the virtual list with your own configuration.

    initWithConfig defaultConfig

You can modify the default configuration:

    { defaultConfig | buffer = 10 }

-}
initWithConfig : Config -> Model
initWithConfig options =
    let
        validListId =
            if String.isEmpty options.listId then
                defaultConfig.listId
            else
                options.listId

        validHeight =
            if options.initialHeight >= 0 then
                options.initialHeight
            else
                defaultConfig.initialHeight

        validBuffer =
            if options.buffer >= 0 then
                options.buffer
            else
                0

        validDefaultItemHeight =
            if options.defaultItemHeight >= 0 then
                options.defaultItemHeight
            else
                defaultConfig.defaultItemHeight
    in
        { listId = validListId
        , ids = []
        , height = validHeight
        , baseBuffer = validBuffer
        , dynamicBuffer = options.dynamicBuffer
        , buffer = validBuffer
        , showList = options.showListDuringInitialMeasure
        , defaultItemHeight = validDefaultItemHeight
        , visibleRange = ( 0, 20 )
        , firstRender = True
        , unmeasuredRows = Set.empty
        , rowHeights = Dict.empty
        , cumulativeHeights = Dict.empty
        , scrollTop = 0
        , previousScrollTop = 0
        }


type RowHeight
    = Unmeasured Float
    | Measured Float


{-| The `Msg` of the virtual list. You need to include it in your `Msg` and make sure it will be processed.

   type Msg
       = VirtualListMsg VirtualList.Msg
       -- other messages
-}
type Msg
    = NoOp
    | RowElementReceived Int (Result Browser.Dom.Error Browser.Dom.Element)
    | Scrolled
    | ViewportUpdated (Result Browser.Dom.Error Browser.Dom.Viewport)


{-| The virtual list `update` function. You need to make sure this is called from your code.

   update : Msg -> Model -> ( Model, Cmd Msg )
   update msg model =
       case msg of
           VirtualListMsg virtualListMsg ->
               let
                   ( virtualListModel, virtualListCmd ) =
                       VirtualList.update virtualListMsg model.virtualList
               in
                   ( { model | virtualList = virtualListModel }, Cmd.map VirtualListMsg virtualListCmd )
           -- other cases
-}
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        RowElementReceived index result ->
            measureRow model index result

        Scrolled ->
            updateOnScroll model

        ViewportUpdated result ->
            updateOnViewportChange model result


updateOnScroll : Model -> ( Model, Cmd Msg )
updateOnScroll model =
    let
        scrollSpeed =
            abs (model.scrollTop - model.previousScrollTop)

        newBuffer =
            if model.dynamicBuffer then
                calculateDynamicBuffer model.baseBuffer scrollSpeed
            else
                model.buffer
    in
        ( { model | buffer = newBuffer }, measureViewport model.listId )


maxBufferMultiplier : Int
maxBufferMultiplier =
    4


calculateDynamicBuffer : Int -> Float -> Int
calculateDynamicBuffer base scrollSpeed =
    base * min maxBufferMultiplier (1 + round (scrollSpeed / 100))


{-| Sets the items in the virtual list. For each item you provide one stable id.

    VirtualList.setItems model.virtualList ids

**Note:** For performance reasons we only measure the height of items when they are first rendered. If you need to remeasure, use `setItemsAndRemeasure`.
-}
setItems : Model -> List String -> ( Model, Cmd Msg )
setItems model newIds =
    setItemsAndRemeasure model { newIds = newIds, idsToRemeasure = [] }


{-| Same as `updateItems` but remeasures the whole list.
-}
setItemsAndRemeasureAll : Model -> List String -> ( Model, Cmd Msg )
setItemsAndRemeasureAll model newIds =
    setItemsAndRemeasure model { newIds = newIds, idsToRemeasure = newIds }


{-| Same as `updateItems` but lets you specify which items should be remeasured.
-}
setItemsAndRemeasure : Model -> { newIds : List String, idsToRemeasure : List String } -> ( Model, Cmd Msg )
setItemsAndRemeasure model { newIds, idsToRemeasure } =
    getRowHeightsFromCache { oldIds = model.ids, newIds = newIds, idsToRemeasure = idsToRemeasure } model.rowHeights model.defaultItemHeight
        |> updateModelWithNewItems model newIds


updateModelWithNewItems : Model -> List String -> Dict Int RowHeight -> ( Model, Cmd Msg )
updateModelWithNewItems model ids updatedRowHeights =
    ( { model
        | ids = ids
        , cumulativeHeights = calculateCumulativeHeights updatedRowHeights
        , rowHeights = updatedRowHeights
      }
    , measureViewport model.listId
    )


getRowHeightsFromCache :
    { oldIds : List String, newIds : List String, idsToRemeasure : List String }
    -> Dict Int RowHeight
       -- currentRowHeights (keyed by the old index)
    -> Float
       -- defaultItemHeight
    -> Dict Int RowHeight
getRowHeightsFromCache ids currentRowHeights defaultItemHeight =
    ids.newIds
        |> List.indexedMap (mapRowHeight ids currentRowHeights defaultItemHeight)
        |> Dict.fromList


mapRowHeight :
    { oldIds : List String, newIds : List String, idsToRemeasure : List String }
    -> Dict Int RowHeight
    -> Float
    -> Int
    -> String
    -> ( Int, RowHeight )
mapRowHeight { oldIds, idsToRemeasure } currentRowHeights defaultItemHeight newIndex id =
    let
        maybeOldIndex =
            findIndexForId oldIds id

        existingHeight =
            maybeOldIndex
                |> Maybe.andThen (\oldIndex -> Dict.get oldIndex currentRowHeights)

        newHeight =
            if List.member id idsToRemeasure then
                Unmeasured (Maybe.withDefault defaultItemHeight (Maybe.map rowHeightToFloat existingHeight))
            else
                Maybe.withDefault (Unmeasured defaultItemHeight) existingHeight
    in
        ( newIndex, newHeight )


findIndex : (a -> Bool) -> List a -> Maybe Int
findIndex predicate items =
    items
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, item ) -> predicate item)
        |> List.head
        |> Maybe.map Tuple.first


findIndexForId : List String -> String -> Maybe Int
findIndexForId ids id =
    findIndex (\listItem -> listItem == id) ids


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

        Unmeasured value ->
            value


calculateVisibleRange : Model -> Float -> Float -> ( Int, Int )
calculateVisibleRange model scrollTop containerHeight =
    let
        keys =
            Dict.keys model.cumulativeHeights

        itemCount =
            List.length model.ids

        height index =
            Maybe.withDefault model.defaultItemHeight (Dict.get index model.cumulativeHeights)

        start =
            keys
                |> List.Extra.find (\index -> height index >= scrollTop)
                |> Maybe.withDefault 0

        end =
            keys
                |> List.reverse
                |> List.Extra.find (\index -> height index < scrollTop + containerHeight)
                |> Maybe.withDefault (itemCount - 1)

        buffer =
            model.buffer
    in
        ( (max 0 (start - buffer)), (min itemCount (end + buffer)) )


measureRow : Model -> Int -> Result Browser.Dom.Error Browser.Dom.Element -> ( Model, Cmd Msg )
measureRow model index result =
    case result of
        Ok element ->
            updateRowHeightWithMeasurement model index element

        Err _ ->
            ( model, Cmd.none )


updateRowHeightWithMeasurement : Model -> Int -> Browser.Dom.Element -> ( Model, Cmd Msg )
updateRowHeightWithMeasurement model index element =
    let
        height =
            element.element.height

        updatedRowHeights =
            Dict.insert index (Measured height) model.rowHeights

        updatedCumulativeHeights =
            calculateCumulativeHeights updatedRowHeights

        remainingUnmeasured =
            Set.remove index model.unmeasuredRows

        showList =
            if Set.isEmpty remainingUnmeasured then
                True
            else
                model.showList
    in
        ( { model
            | showList = showList
            , unmeasuredRows = remainingUnmeasured
            , cumulativeHeights = updatedCumulativeHeights
            , rowHeights = updatedRowHeights
          }
        , Cmd.none
        )


updateOnViewportChange : Model -> Result Browser.Dom.Error Browser.Dom.Viewport -> ( Model, Cmd Msg )
updateOnViewportChange model result =
    case result of
        Ok viewport ->
            handleSuccessfulViewportUpdate model viewport

        Err _ ->
            ( model, Cmd.none )


handleSuccessfulViewportUpdate : Model -> Browser.Dom.Viewport -> ( Model, Cmd Msg )
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
                |> List.map requestRowMeasurement
                |> Cmd.batch
    in
        ( { model
            | height = newContainerHeight
            , scrollTop = newScrollTop
            , previousScrollTop = model.scrollTop
            , visibleRange = visibleRange
            , unmeasuredRows = Set.fromList unmeasuredIndices
          }
        , measureCmds
        )


isUnmeasured : Dict comparable RowHeight -> comparable -> Bool
isUnmeasured rowHeights index =
    case Dict.get index rowHeights of
        Just (Unmeasured _) ->
            True

        Just (Measured _) ->
            False

        Nothing ->
            True


requestRowMeasurement : Int -> Cmd Msg
requestRowMeasurement index =
    Browser.Dom.getElement (rowId index)
        |> Task.attempt (RowElementReceived index)


rowId : Int -> String
rowId index =
    "virtual-list-item-" ++ String.fromInt index


{-| Defines where in the viewport an item should be shown when scrolling to it.

    type Alignment
        = Top
        | Center
        | Bottom
-}
type Alignment
    = Top
    | Center
    | Bottom


{-| Scroll the item with the given unique id into the viewport, either at the top, center or bottom.

We won't scroll if the item is already in the viewport.

You need to make sure that you map the returned `VirtualList.Msg` back to your own `Msg`:

    Cmd.map VirtualListMsg (VirtualList.scrollToItem model.virtualList index VirtualList.Center)
-}
scrollToItem : Model -> String -> Alignment -> Cmd Msg
scrollToItem model id alignment =
    case findIndexForId model.ids id of
        Just index ->
            let
                elementStart =
                    Maybe.withDefault 0 (Dict.get (index - 1) model.cumulativeHeights)

                nextElementStart =
                    Dict.get index model.cumulativeHeights

                needsScroll =
                    abs (model.scrollTop - elementStart) > 1
            in
                if needsScroll then
                    scrollToPosition
                        { targetId = model.listId
                        , elementStart = elementStart
                        , containerHeight = model.height
                        , nextElementStart = nextElementStart
                        , alignment = alignment
                        }
                else
                    Cmd.none

        Nothing ->
            Cmd.none


type alias ScrollPosition =
    { targetId : String
    , elementStart : Float
    , containerHeight : Float
    , nextElementStart : Maybe Float
    , alignment : Alignment
    }


scrollToPosition : ScrollPosition -> Cmd Msg
scrollToPosition position =
    let
        nextElementStart =
            Maybe.withDefault position.elementStart position.nextElementStart

        finalPosition =
            case position.alignment of
                Top ->
                    position.elementStart

                Center ->
                    position.elementStart - 0.5 * position.containerHeight

                Bottom ->
                    nextElementStart - position.containerHeight
    in
        Browser.Dom.setViewportOf position.targetId 0 finalPosition
            |> Task.attempt (\_ -> NoOp)


{-| Display the virtual list.

You provide it with

- a function that returns the `Html` for a given unique id,
- the virtual list `Model` and
- the virtual list message type on your side.

In your code this would look like this:

    view : Model -> Html Msg
    view model =
        VirtualList.view (renderRow model) model.virtualList VirtualListMsg

    renderRow : Model -> String -> Html Msg
    renderRow model id =
        div [] [text id]
-}
view : (String -> Html msg) -> Model -> (Msg -> msg) -> Html msg
view renderRow model toSelf =
    let
        ( start, end ) =
            model.visibleRange

        visibleItems =
            slice start end model.ids

        height =
            String.fromFloat (totalHeight model.cumulativeHeights)

        rows =
            List.indexedMap
                (\localIndex id ->
                    let
                        globalIndex =
                            start + localIndex
                    in
                        renderRow id
                            |> renderLazyVirtualRow globalIndex model.cumulativeHeights
                )
                visibleItems
    in
        div
            (listAttributes model.showList model.listId toSelf)
            [ renderSpacer height rows ]


listAttributes : Bool -> String -> (Msg -> msg) -> List (Html.Attribute msg)
listAttributes showList listId toSelf =
    [ Html.Attributes.class "virtual-list"
    , Html.Attributes.id listId
      -- Height needs to be in the element for fast measurement
    , Html.Attributes.style "height" "100%"
    , Html.Attributes.style "overflow" "auto"
    , onScroll (toSelf Scrolled)
    ]
        ++ if not showList then
            [ Html.Attributes.style "visibility" "hidden" ]
           else
            []


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
        rows


renderLazyVirtualRow : Int -> Dict Int Float -> Html msg -> Html msg
renderLazyVirtualRow index cumulativeHeights renderRow =
    let
        top =
            Maybe.withDefault 0 (Dict.get (index - 1) cumulativeHeights)

        id =
            rowId index
    in
        lazy2 (renderVirtualRow renderRow) id top


renderVirtualRow : Html msg -> String -> Float -> Html msg
renderVirtualRow renderRow id top =
    div
        [ Html.Attributes.id id
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


measureViewport : String -> Cmd Msg
measureViewport listId =
    Task.attempt ViewportUpdated (Browser.Dom.getViewportOf listId)
