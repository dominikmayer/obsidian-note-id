module Main exposing (..)

import Browser
import Browser.Dom
import Dict exposing (Dict, foldl)
import Html exposing (Html, div)
import Html.Attributes
import Html.Events exposing (on, onClick)
import Html.Events.Extra.Mouse as Mouse
import Json.Decode as Decode
import Json.Encode as Encode
import NoteId
import Ports exposing (..)
import Task
import Debug exposing (toString)
import VirtualList


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
    , fileOpenedByPlugin : Bool
    , virtualList : VirtualList.Model
    }


defaultModel : Model
defaultModel =
    { notes = []
    , currentFile = Nothing
    , settings = defaultSettings
    , fileOpenedByPlugin = False
    , virtualList = VirtualList.init
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
    | NoOp
    | Scrolled
    | ViewportUpdated (Result Browser.Dom.Error Browser.Dom.Viewport)
    | VirtualListMsg VirtualList.Msg


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

        NoOp ->
            ( model, Cmd.none )

        Scrolled ->
            ( model, measureViewport )

        ViewportUpdated result ->
            translate (VirtualList.handleViewportUpdate model.virtualList result) model

        VirtualListMsg virtualListMsg ->
            let
                ( newVirtualList, virtualListCmd ) =
                    VirtualList.update virtualListMsg model.virtualList
            in
                ( { model | virtualList = newVirtualList }, Cmd.none )


translate : ( VirtualList.Model, Cmd VirtualList.Msg ) -> Model -> ( Model, Cmd Msg )
translate ( virtualListModel, virtualListMsg ) model =
    ( { model | virtualList = virtualListModel }, Cmd.map VirtualListMsg virtualListMsg )


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
                Maybe.map NoteId.getNewChildId id
            else
                Maybe.map NoteId.getNewIdInSequence id

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
                            |> Maybe.andThen (\index -> Dict.get index model.virtualList.rowHeights)
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
                                ( i, VirtualList.Default defaultItemHeight )
                    )
                |> Dict.fromList

        updatedCumulativeHeights =
            VirtualList.calculateCumulativeHeights updatedRowHeights

        oldVirtualList =
            model.virtualList

        newVirtualList =
            { oldVirtualList
                | cumulativeHeights = updatedCumulativeHeights
                , rowHeights = updatedRowHeights
            }
    in
        ( { model
            | notes = newNotes
            , virtualList = newVirtualList
          }
        , measureViewport
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
                    Maybe.withDefault 0 (Dict.get (index - 1) model.virtualList.cumulativeHeights)
            in
                scrollToPosition "virtual-list" elementStart model.virtualList.containerHeight

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
            model.virtualList.visibleRange

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
    case Dict.get (List.length model.notes - 1) model.virtualList.cumulativeHeights of
        Just height ->
            height

        Nothing ->
            0


viewRow : Model -> Int -> NoteMeta -> Html Msg
viewRow model index note =
    let
        top =
            Maybe.withDefault 0 (Dict.get (index - 1) model.virtualList.cumulativeHeights)
    in
        div
            [ Html.Attributes.id (VirtualList.rowId index)
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
