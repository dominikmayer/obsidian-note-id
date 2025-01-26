module Main exposing (..)

import Browser
import Browser.Dom
import Dict exposing (Dict, foldl)
import Html exposing (Html, div)
import Html.Attributes
import Html.Events exposing (on, onClick)
import Html.Events.Extra.Mouse as Mouse
import List.Extra exposing (..)
import Json.Decode as Decode
import Json.Encode as Encode
import Ports exposing (..)
import Task
import Debug exposing (toString)


-- MAIN


main : Program Encode.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }



-- MODEL


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
    , fileOpenedByPlugin : Bool
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
    , fileOpenedByPlugin = False
    }


type alias NoteMeta =
    { title : String
    , id : Maybe String
    , filePath : String
    }


type alias Settings =
    { includeFolders : List String
    , excludeFolders : List String
    , showNotesWithoutId : Bool
    , idField : String
    }


defaultSettings : Settings
defaultSettings =
    { includeFolders = [ "Zettel" ]
    , excludeFolders = []
    , showNotesWithoutId = True
    , idField = "id"
    }


defaultItemHeight : Float
defaultItemHeight =
    26


init : Encode.Value -> ( Model, Cmd Msg )
init flags =
    let
        updatedSettings =
            case Decode.decodeValue partialSettingsDecoder flags of
                Ok decoded ->
                    decoded defaultSettings

                Err _ ->
                    defaultSettings
    in
        ( { defaultModel | settings = updatedSettings }
        , Cmd.none
        )



-- UPDATE


type Msg
    = ContextMenuTriggered Mouse.Event String
    | FileOpened (Maybe String)
    | FileRenamed ( String, String )
    | NoteClicked String
    | NoteCreationRequested ( String, Bool )
    | NotesProvided (List NoteMeta)
    | NotesUpdated
    | NoOp
    | RowHeightMeasured Int (Result Browser.Dom.Error Browser.Dom.Element)
    | Scrolled
    | ViewportUpdated (Result Browser.Dom.Error Browser.Dom.Viewport)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ContextMenuTriggered event path ->
            let
                ( x, y ) =
                    event.clientPos
            in
                ( model, Ports.openContextMenu ( x, y, path ) )

        FileOpened filePath ->
            fileOpened model filePath

        FileRenamed paths ->
            handleFileRename model paths

        NoteCreationRequested ( filePath, child ) ->
            createNote model filePath child

        NoteClicked filePath ->
            ( { model | fileOpenedByPlugin = True }, Ports.openFile filePath )

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


createNote : Model -> String -> Bool -> ( Model, Cmd Msg )
createNote model path child =
    let
        folder =
            getPathWithoutFileName path

        newPath =
            folder ++ "/Untitled.md"

        id =
            getNoteByPath path model.notes
                |> Maybe.andThen (\note -> note.id)

        newId =
            if child then
                Maybe.map getNewChildId id
            else
                Maybe.map getNewIdInSequence id

        fileContent =
            case newId of
                Just justId ->
                    createNoteContent model.settings.idField justId

                Nothing ->
                    ""
    in
        ( model, Ports.createNote ( newPath, fileContent ) )


createNoteContent : String -> String -> String
createNoteContent idName id =
    "---\n" ++ idName ++ ": " ++ id ++ "\n---"


getNewIdInSequence : String -> String
getNewIdInSequence id =
    let
        ( start, end ) =
            incrementLastElement id
    in
        start ++ end


getNewChildId : String -> String
getNewChildId input =
    let
        ( _, elementType ) =
            getLastElement input

        newLastElement =
            case elementType of
                Digit ->
                    "a"

                Letter ->
                    "1"

                Other ->
                    ""
    in
        input ++ newLastElement


incrementLastElement : String -> ( String, String )
incrementLastElement input =
    let
        ( lastElement, elementType ) =
            getLastElement input

        start =
            String.dropRight (String.length lastElement) input

        incrementedLastElement =
            incrementElement lastElement elementType
    in
        ( start, Maybe.withDefault lastElement incrementedLastElement )


incrementElement : String -> CharType -> Maybe String
incrementElement element elementType =
    case elementType of
        Digit ->
            String.toInt element
                |> Maybe.andThen (\num -> Just (num + 1))
                |> Maybe.map String.fromInt

        Letter ->
            incrementString element

        Other ->
            Nothing


incrementString : String -> Maybe String
incrementString str =
    if str == "" then
        Nothing
    else
        str
            |> String.reverse
            |> incrementChars
            |> Maybe.map String.reverse


incrementChars : String -> Maybe String
incrementChars str =
    case String.toList str of
        [] ->
            Nothing

        head :: tail ->
            let
                ( nextChar, carry ) =
                    incrementChar head
            in
                if carry then
                    incrementChars (String.fromList tail)
                        |> Maybe.map (\incrementedTail -> nextChar ++ incrementedTail)
                else
                    Just (nextChar ++ String.fromList tail)


incrementChar : Char -> ( String, Bool )
incrementChar char =
    if char == 'z' then
        ( "a", True )
        -- Overflow to 'a', with carry
    else
        ( String.fromChar (Char.fromCode (Char.toCode char + 1)), False )


type CharType
    = Digit
    | Letter
    | Other


charType : Char -> CharType
charType c =
    if Char.isDigit c then
        Digit
    else if Char.isAlpha c then
        Letter
    else
        Other


getLastElement : String -> ( String, CharType )
getLastElement string =
    let
        ( reversedElement, elementType ) =
            compareElements [] (string |> String.reverse |> String.toList)
    in
        ( String.reverse reversedElement, elementType )


compareElements : List Char -> List Char -> ( String, CharType )
compareElements acc remaining =
    case remaining of
        [] ->
            case acc of
                [] ->
                    ( "", Other )

                head :: _ ->
                    ( String.fromList acc, charType head )

        c :: rest ->
            case acc of
                [] ->
                    compareElements [ c ] rest

                head :: _ ->
                    if charType head == charType c then
                        compareElements (c :: acc) rest
                    else
                        ( String.fromList acc |> String.reverse, charType head )


getPathWithoutFileName : String -> String
getPathWithoutFileName filePath =
    let
        components =
            String.split "/" filePath

        withoutFileName =
            List.take (List.length components - 1) components
    in
        String.join "/" withoutFileName


updateNotes : Model -> List NoteMeta -> ( Model, Cmd Msg )
updateNotes model newNotes =
    let
        existingHeights =
            newNotes
                |> List.filterMap
                    (\note ->
                        findIndexByFilePath note.filePath model.notes
                            |> Maybe.andThen (\index -> Dict.get index model.rowHeights)
                            |> Maybe.map (\height -> ( note.filePath, height ))
                    )
                |> Dict.fromList

        updatedRowHeights =
            newNotes
                |> List.indexedMap
                    (\i note ->
                        case Dict.get note.filePath existingHeights of
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
            | notes = newNotes
            , rowHeights = updatedRowHeights
            , cumulativeHeights = updatedCumulativeHeights
          }
        , Task.perform (\_ -> NotesUpdated) (Task.succeed ())
        )


handleFileRename : Model -> ( String, String ) -> ( Model, Cmd Msg )
handleFileRename model ( oldPath, newPath ) =
    let
        updatedCurrentFile =
            if model.currentFile == Just oldPath then
                Just newPath
            else
                model.currentFile

        cmd =
            if model.currentFile == Just oldPath then
                scrollToNote model newPath
            else
                Cmd.none
    in
        ( { model | currentFile = updatedCurrentFile }, cmd )


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


getNoteByPath : String -> List NoteMeta -> Maybe NoteMeta
getNoteByPath path notes =
    notes
        |> List.filter (\note -> note.filePath == path)
        |> List.head


fileOpened : Model -> Maybe String -> ( Model, Cmd Msg )
fileOpened model filePath =
    case filePath of
        Just path ->
            let
                ( updatedModel, scrollCmd ) =
                    scrollToExternallyOpenedNote model path
            in
                ( { updatedModel | currentFile = Just path }, scrollCmd )

        Nothing ->
            ( model, Cmd.none )


scrollToExternallyOpenedNote : Model -> String -> ( Model, Cmd Msg )
scrollToExternallyOpenedNote model path =
    if model.fileOpenedByPlugin then
        ( { model | fileOpenedByPlugin = False }, Cmd.none )
    else
        ( model, scrollToNote model path )


scrollToNote : Model -> String -> Cmd Msg
scrollToNote model path =
    case findIndexByFilePath path model.notes of
        Just index ->
            let
                elementStart =
                    Maybe.withDefault 0 (Dict.get (index - 1) model.cumulativeHeights)
            in
                scrollToPosition "virtual-list" elementStart model.containerHeight

        Nothing ->
            Cmd.none


scrollToPosition : String -> Float -> Float -> Cmd Msg
scrollToPosition targetId elementStart containerHeight =
    let
        position =
            elementStart - 0.5 * containerHeight
    in
        Browser.Dom.setViewportOf targetId 0 position
            |> Task.attempt (\_ -> NoOp)


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

        visibleRange =
            calculateVisibleRange model newScrollTop newContainerHeight

        ( start, end ) =
            visibleRange

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
            | rowHeights = updatedRowHeights
            , cumulativeHeights = updatedCumulativeHeights
          }
        , Cmd.none
        )


noteFilePath : Model -> Int -> Maybe String
noteFilePath model index =
    List.Extra.getAt index model.notes
        |> Maybe.map .filePath


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
                |> Maybe.withDefault (List.length model.notes - 1)

        buffer =
            model.buffer
    in
        ( (max 0 (start - buffer)), (min (List.length model.notes) (end + buffer)) )


slice : Int -> Int -> List a -> List a
slice start end list =
    list
        |> List.drop start
        |> List.take (end - start)



-- VIEW


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
        top =
            Maybe.withDefault 0 (Dict.get (index - 1) model.cumulativeHeights)
    in
        div
            [ Html.Attributes.id note.filePath
            , Html.Attributes.classList
                [ ( "tree-item-self", True )
                , ( "is-clickable", True )
                , ( "is-active", Just note.filePath == model.currentFile )
                ]
            , Html.Attributes.style "transform" ("translateY(" ++ toString top ++ "px)")
            , Html.Attributes.attribute "data-path" note.filePath
            , onClick (NoteClicked note.filePath)
            , Mouse.onContextMenu (\event -> ContextMenuTriggered event note.filePath)
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


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Ports.receiveNotes NotesProvided
        , Ports.receiveCreateNote NoteCreationRequested
        , Ports.receiveFileOpen FileOpened
        , Ports.receiveFileRenamed FileRenamed
        ]


settingsDecoder : Decode.Decoder Settings
settingsDecoder =
    Decode.map4
        (\includeFolders excludeFolders showNotesWithoutId idField ->
            { includeFolders = includeFolders
            , excludeFolders = excludeFolders
            , showNotesWithoutId = showNotesWithoutId
            , idField = idField
            }
        )
        (Decode.oneOf
            [ Decode.field "includeFolders" (Decode.list Decode.string)
            , Decode.succeed defaultSettings.includeFolders
            ]
        )
        (Decode.oneOf
            [ Decode.field "excludeFolders" (Decode.list Decode.string)
            , Decode.succeed defaultSettings.excludeFolders
            ]
        )
        (Decode.oneOf
            [ Decode.field "showNotesWithoutId" Decode.bool
            , Decode.succeed defaultSettings.showNotesWithoutId
            ]
        )
        (Decode.oneOf
            [ Decode.field "idField" Decode.string
            , Decode.succeed defaultSettings.idField
            ]
        )


partialSettingsDecoder : Decode.Decoder (Settings -> Settings)
partialSettingsDecoder =
    Decode.map4
        (\includeFolders excludeFolders showNotesWithoutId idField settings ->
            { settings
                | includeFolders = includeFolders |> Maybe.withDefault settings.includeFolders
                , excludeFolders = excludeFolders |> Maybe.withDefault settings.excludeFolders
                , showNotesWithoutId = showNotesWithoutId |> Maybe.withDefault settings.showNotesWithoutId
                , idField = idField |> Maybe.withDefault settings.idField
            }
        )
        (Decode.field "includeFolders" (Decode.list Decode.string) |> Decode.maybe)
        (Decode.field "excludeFolders" (Decode.list Decode.string) |> Decode.maybe)
        (Decode.field "showNotesWithoutId" Decode.bool |> Decode.maybe)
        (Decode.field "idField" Decode.string |> Decode.maybe)
