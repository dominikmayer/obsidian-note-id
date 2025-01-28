module VirtualList
    exposing
        ( init
        , defaultConfig
        , update
        , view
        , setItems
        , setItemsAndRemeasure
        , scrollToItem
        , Model
        , Msg
        , Alignment(..)
        )

{-| Efficiently renders large lists by only rendering the visible items in the viewport plus a configurable buffer.

It does so by measuring the height of the displayed elements.

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

@docs Model, defaultConfig, init, Msg, update

# Rendering

@docs view

# Updating the Items

@docs setItems, setItemsAndRemeasure

# Scrolling

@docs scrollToItem, Alignment(..)
-}

import Browser.Dom
import Dict exposing (Dict, foldl)
import Html exposing (Html, div)
import Html.Attributes
import Html.Events exposing (on)
import Json.Decode as Decode
import List.Extra exposing (last)
import Task


type alias Config =
    { initialHeight : Float
    , defaultItemHeight : Float
    , buffer : Int
    , dynamicBuffer : Bool
    }


{-| A default configuration for initializing the virtual list model.

This configuration provides sensible defaults that work for most use cases. You can customize
it to better suit your needs by creating a new `Config` record with adjusted values.

    defaultConfig : Config
    defaultConfig =
    -- The height of the list before the viewport is first measured
    { initialHeight = 500
    -- The height of items before they are first measured
    , defaultItemHeight = 26
    -- The number of items that are loaded outside the visual range
    , buffer = 5
    -- Whether the buffer should be increased on high scroll speeds
    , dynamicBuffer = True
    }
-}
defaultConfig : Config
defaultConfig =
    { initialHeight = 500
    , defaultItemHeight = 26
    , buffer = 5
    , dynamicBuffer = True
    }



{- The `Model` of the virtual list. You need to include it in your model:

       type alias Model =
           { virtualList : VirtualList.Model
           -- other fields
           }

   You create one with the `init` function.
-}


type alias Model =
    { ids : List String
    , height : Float
    , defaultItemHeight : Float
    , baseBuffer : Int
    , dynamicBuffer : Bool
    , buffer : Int
    , visibleRange : ( Int, Int )
    , rowHeights : Dict Int RowHeight
    , cumulativeHeights : Dict Int Float
    , scrollTop : Float
    , previousScrollTop : Float
    }


{-| Initialize the model of the virtual list.

    init defaultConfig

You can modify the default configuration:

    { defaultConfig | buffer = 10 }

-}
init : Config -> Model
init options =
    { ids = []
    , height = options.initialHeight
    , baseBuffer = options.buffer
    , dynamicBuffer = options.dynamicBuffer
    , buffer = options.buffer
    , defaultItemHeight = options.defaultItemHeight
    , visibleRange = ( 0, 20 )
    , rowHeights = Dict.empty
    , cumulativeHeights = Dict.empty
    , scrollTop = 0
    , previousScrollTop = 0
    }


type RowHeight
    = Measured Float
    | Default Float



{- The `Msg` of the virtual list. You need to include it in your `Msg` and make sure it will be processed.

   type Msg
       = VirtualListMsg VirtualList.Msg
       -- other messages
-}


type Msg
    = NoOp
    | RowHeightMeasured Int (Result Browser.Dom.Error Browser.Dom.Element)
    | Scrolled
    | ViewportUpdated (Result Browser.Dom.Error Browser.Dom.Viewport)



{- The virtual list `update` function. You need to make sure this is called from your code.

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

        RowHeightMeasured index result ->
            handleRowHeightMeasurementResult model index result

        Scrolled ->
            handleScroll model

        ViewportUpdated result ->
            handleViewportUpdate model result


handleScroll : Model -> ( Model, Cmd Msg )
handleScroll model =
    let
        scrollSpeed =
            abs (model.scrollTop - model.previousScrollTop)

        newBuffer =
            if model.dynamicBuffer then
                dynamicBuffer model.baseBuffer scrollSpeed
            else
                model.buffer
    in
        ( { model | buffer = newBuffer }, measureViewport )


dynamicBuffer : Int -> Float -> Int
dynamicBuffer base scrollSpeed =
    if scrollSpeed > 200 then
        base * 6
    else if scrollSpeed > 100 then
        base * 4
    else if scrollSpeed > 50 then
        base * 2
    else
        base



{- Sets the items in the virtual list. For each item you provide one stable id.

       VirtualList.setItems model.virtualList ids

   **Note:** For performance reasons we only measure the height of items when they are first rendered. If you need to remeasure, use `setItemsAndRemeasure`.
-}


setItems : Model -> List String -> ( Model, Cmd Msg )
setItems model newIds =
    setItemsAndRemeasure model newIds []



{- Same as `updateItems` but lets you specify which items should be remeasured. -}


setItemsAndRemeasure : Model -> List String -> List String -> ( Model, Cmd Msg )
setItemsAndRemeasure model ids idsToRemeasure =
    let
        heightKnown =
            (\id ->
                findIndex (\oldId -> oldId == id) model.ids
                    |> Maybe.andThen (\index -> Dict.get index model.rowHeights)
                    |> Maybe.map (\height -> ( id, height ))
            )

        existingHeights =
            ids
                |> List.filterMap heightKnown
                |> Dict.fromList

        knownOrDefaultHeight =
            (\index id ->
                if List.member id idsToRemeasure then
                    ( index, Default model.defaultItemHeight )
                else
                    case Dict.get id existingHeights of
                        Just height ->
                            ( index, height )

                        Nothing ->
                            ( index, Default model.defaultItemHeight )
            )

        updatedRowHeights =
            ids
                |> List.indexedMap knownOrDefaultHeight
                |> Dict.fromList

        updatedCumulativeHeights =
            calculateCumulativeHeights updatedRowHeights
    in
        ( { model
            | ids = ids
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


calculateVisibleRange : Model -> Float -> Float -> ( Int, Int )
calculateVisibleRange model scrollTop containerHeight =
    let
        itemCount =
            List.length model.ids

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
                |> Maybe.withDefault (itemCount - 1)

        buffer =
            model.buffer
    in
        ( (max 0 (start - buffer)), (min itemCount (end + buffer)) )


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



{- Scroll the item with the given unique id into the viewport, either at the top, center or bottom.

   You need to make sure that you map the returned `VirtualList.Msg` back to your own `Msg`:

       Cmd.map VirtualListMsg (VirtualList.scrollToItem model.virtualList index VirtualList.Center)
-}


scrollToItem : Model -> Int -> Alignment -> Cmd Msg
scrollToItem model index alignment =
    let
        elementStart =
            Maybe.withDefault 0 (Dict.get (index - 1) model.cumulativeHeights)

        nextElementStart =
            Dict.get index model.cumulativeHeights
    in
        scrollToPosition virtualListId elementStart model.height nextElementStart alignment


scrollToPosition : String -> Float -> Float -> Maybe Float -> Alignment -> Cmd Msg
scrollToPosition targetId elementStart containerHeight nextElementStart alignment =
    let
        position =
            case alignment of
                Top ->
                    elementStart

                Center ->
                    elementStart - 0.5 * containerHeight

                Bottom ->
                    case nextElementStart of
                        Just nextStart ->
                            nextStart - containerHeight

                        Nothing ->
                            elementStart - containerHeight
    in
        Browser.Dom.setViewportOf targetId 0 position
            |> Task.attempt (\_ -> NoOp)



{- Display the virtual list.

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
