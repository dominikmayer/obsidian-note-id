module Main exposing (..)

import Browser
import Browser.Dom
import Dict exposing (Dict, foldl)
import Html exposing (Html, div)
import Html.Attributes
import Html.Events exposing (on, onClick)
import List.Extra exposing (..)
import Json.Decode as Decode
import Ports exposing (..)
import Task
import Debug exposing (toString)


type alias Model =
    { notes : List NoteMeta
    , currentFile : Maybe String
    , settings : Settings
    , cumulativeHeights : Dict Int Float
    , rowHeights : Dict Int RowHeight
    , scrollTop : Float
    , containerHeight : Float
    , buffer : Int
    , visibleRange : ( Int, Int )
    }


type RowHeight
    = Measured Float
    | Default Float


rowHeightToFloat : RowHeight -> Float
rowHeightToFloat rowHeight =
    case rowHeight of
        Measured value ->
            value

        Default value ->
            value


defaultModel : Model
defaultModel =
    { notes = []
    , currentFile = Nothing
    , settings = defaultSettings
    , cumulativeHeights = Dict.empty
    , rowHeights = Dict.empty
    , scrollTop = 0
    , containerHeight = 500
    , buffer = 5
    , visibleRange = ( 0, 20 )
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


defaultItemHeight : Float
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
    = FileOpened (Maybe String)
    | NoteClicked String
    | NotesProvided (List NoteMeta)
    | NotesUpdated
    | NoOp
    | RowHeightMeasured Int (Result Browser.Dom.Error Browser.Dom.Element)
    | Scrolled
    | ViewportUpdated (Result Browser.Dom.Error Browser.Dom.Viewport)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FileOpened filePath ->
            fileOpened model filePath

        NoteClicked filePath ->
            ( model, Ports.openFile filePath )

        NotesProvided notes ->
            updateNotes model notes

        NotesUpdated ->
            ( model, measureViewport )

        NoOp ->
            ( model, Cmd.none )

        RowHeightMeasured index result ->
            handleRowHeightMeasurementResult model index result

        Scrolled ->
            ( model, measureViewport )

        ViewportUpdated result ->
            handleViewportUpdate model result


updateNotes : Model -> List NoteMeta -> ( Model, Cmd Msg )
updateNotes model notes =
    let
        initialHeights =
            List.indexedMap (\i _ -> ( i, Default defaultItemHeight )) notes
                -- Default initial height of 40
                |>
                    Dict.fromList

        cumulativeHeights =
            calculateCumulativeHeights initialHeights
    in
        ( { model
            | notes =
                notes
            , rowHeights = initialHeights
            , cumulativeHeights = cumulativeHeights
          }
        , Task.perform (\_ -> NotesUpdated) (Task.succeed ())
        )


measureViewport : Cmd Msg
measureViewport =
    Task.attempt ViewportUpdated (Browser.Dom.getViewportOf "virtual-list")


findIndexByFilePath : String -> List NoteMeta -> Maybe Int
findIndexByFilePath targetFilePath notes =
    notes
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, note ) -> note.filePath == targetFilePath)
        |> List.head
        |> Maybe.map Tuple.first


fileOpened : Model -> Maybe String -> ( Model, Cmd Msg )
fileOpened model filePath =
    case filePath of
        Just path ->
            let
                scrollCmd =
                    scrollTo model path
            in
                ( { model | currentFile = Just path }, scrollCmd )

        Nothing ->
            ( model, Cmd.none )


scrollTo : Model -> String -> Cmd Msg
scrollTo model path =
    let
        index =
            Maybe.withDefault 0 (findIndexByFilePath path model.notes)

        elementStart =
            Maybe.withDefault 0 (Dict.get (index - 1) model.cumulativeHeights)

        position =
            elementStart - 0.5 * model.containerHeight
    in
        Browser.Dom.setViewportOf "virtual-list" 0 position
            |> Task.attempt handleScrollResult


handleScrollResult : Result Browser.Dom.Error x -> Msg
handleScrollResult result =
    case result of
        Ok _ ->
            Debug.log "Scroll succeeded" NoOp

        Err err ->
            Debug.log ("Scroll failed with error: " ++ Debug.toString err) NoOp


handleViewportUpdate : Model -> Result Browser.Dom.Error Browser.Dom.Viewport -> ( Model, Cmd Msg )
handleViewportUpdate model result =
    case result of
        Ok viewport ->
            handleViewportUpdateSucceeded model viewport

        Err error ->
            Debug.log "Error fetching viewport" error
                |> always
                    ( model, Cmd.none )


handleViewportUpdateSucceeded : Model -> Browser.Dom.Viewport -> ( Model, Cmd Msg )
handleViewportUpdateSucceeded model viewport =
    let
        newScrollTop =
            viewport.viewport.y

        newContainerHeight =
            viewport.viewport.height

        visibleRange =
            calculateVisibleRange model newScrollTop newContainerHeight

        ( start, end ) =
            visibleRange

        unmeasuredIndices =
            List.range start end
                |> List.filter
                    (\index ->
                        case Dict.get index model.rowHeights of
                            Just (Default _) ->
                                True

                            -- Include rows with default value
                            Just (Measured _) ->
                                False

                            -- Exclude rows with measured value
                            Nothing ->
                                True
                     -- Include rows not yet in the dictionary
                    )

        measureCmds =
            unmeasuredIndices
                |> List.filterMap
                    (\index ->
                        noteFilePath model index
                            |> Maybe.map
                                (\filePath ->
                                    Browser.Dom.getElement filePath
                                        |> Task.attempt (RowHeightMeasured index)
                                )
                    )
                |> Cmd.batch
    in
        ( { model
            | scrollTop = newScrollTop
            , containerHeight = newContainerHeight
            , visibleRange = visibleRange
          }
        , measureCmds
        )


handleRowHeightMeasurementResult : Model -> Int -> Result Browser.Dom.Error Browser.Dom.Element -> ( Model, Cmd Msg )
handleRowHeightMeasurementResult model index result =
    case result of
        Ok element ->
            updateRowHeight model index element

        Err err ->
            Debug.log "Couldn't measure" err
                |> always
                    ( model, Cmd.none )


updateRowHeight : Model -> Int -> Browser.Dom.Element -> ( Model, Cmd Msg )
updateRowHeight model index element =
    let
        height =
            Debug.log "Measured" element.element.height

        updatedRowHeights =
            Dict.insert index (Measured height) model.rowHeights

        updatedCumulativeHeights =
            calculateCumulativeHeights updatedRowHeights
    in
        ( { model
            | rowHeights = updatedRowHeights
            , cumulativeHeights = updatedCumulativeHeights
          }
        , Cmd.none
        )


noteId : Model -> Int -> String
noteId model index =
    List.Extra.getAt index model.notes
        |> Maybe.map .filePath
        |> Maybe.withDefault ("row-" ++ String.fromInt index)


noteFilePath : Model -> Int -> Maybe String
noteFilePath model index =
    List.Extra.getAt index model.notes
        |> Maybe.map .filePath


getElementsInRange : Int -> Int -> Dict Int v -> List ( Int, v )
getElementsInRange start end dict =
    Dict.toList dict
        |> List.filter (\( key, _ ) -> key >= start && key <= end)


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
        -- Find the start of the visible range
        start =
            Dict.keys model.cumulativeHeights
                |> List.filter (\i -> Maybe.withDefault 0 (Dict.get i model.cumulativeHeights) >= scrollTop)
                |> List.head
                |> Maybe.withDefault 0

        -- Find the end of the visible range
        end =
            Dict.keys model.cumulativeHeights
                |> List.filter (\i -> Maybe.withDefault 0 (Dict.get i model.cumulativeHeights) < scrollTop + containerHeight)
                |> last
                |> Maybe.withDefault (List.length model.notes - 1)

        -- Apply buffer to the range
        buffer =
            model.buffer
    in
        ( (max 0 (start - buffer)), (min (List.length model.notes - 1) (end + buffer)) )


slice : Int -> Int -> List a -> List a
slice start end list =
    list
        |> List.drop start
        |> List.take (end - start)


view : Model -> Html Msg
view model =
    let
        ( start, end ) =
            model.visibleRange

        visibleItems =
            slice start end model.notes

        rows =
            List.indexedMap
                (\localIndex item ->
                    let
                        globalIndex =
                            start + localIndex
                    in
                        viewRow model globalIndex item
                )
                visibleItems
    in
        div
            [ Html.Attributes.class "virtual-list"
            , Html.Attributes.id "virtual-list"
              -- Height needs to be in the element for fast measurement
            , Html.Attributes.style "height" "100%"
            , onScroll Scrolled
            ]
            [ div
                [ Html.Attributes.style "height" (String.fromFloat (totalHeight model) ++ "px")
                , Html.Attributes.class "note-id-list-spacer"
                ]
                [ div [ Html.Attributes.class "note-id-list-items" ]
                    rows
                ]
            ]


onScroll : msg -> Html.Attribute msg
onScroll msg =
    on "scroll" (Decode.succeed msg)


scrollTopDecoder : Decode.Decoder Float
scrollTopDecoder =
    Decode.field "target" (Decode.field "scrollTop" Decode.float)


totalHeight : Model -> Float
totalHeight model =
    case Dict.get (List.length model.notes - 1) model.cumulativeHeights of
        Just height ->
            height

        Nothing ->
            0


viewRow : Model -> Int -> NoteMeta -> Html Msg
viewRow model index note =
    let
        height =
            rowHeightToFloat (Maybe.withDefault (Default defaultItemHeight) (Dict.get index model.rowHeights))

        top =
            Maybe.withDefault 0 (Dict.get (index - 1) model.cumulativeHeights)
    in
        div
            [ Html.Attributes.id note.filePath
            , Html.Attributes.class "note-id-item"
            , Html.Attributes.style "transform" ("translateY(" ++ toString top ++ "px)")
            , Html.Attributes.style "height" ("height: " ++ toString height ++ "px")
            , onClick (NoteClicked note.filePath)
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
                            [ Html.span [ Html.Attributes.class "note-id" ] [ Html.text (id ++ ": ") ]
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
        [ Ports.receiveNotes NotesProvided
        , Ports.receiveFileOpen FileOpened
        ]
