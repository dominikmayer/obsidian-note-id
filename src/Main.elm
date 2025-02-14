module Main exposing (..)

import Browser
import Html exposing (Html, div)
import Html.Attributes
import Html.Events exposing (onClick)
import Html.Events.Extra.Mouse as Mouse
import Json.Decode as Decode
import Json.Encode as Encode
import NoteId
import Ports exposing (..)
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
    let
        default =
            VirtualList.defaultConfig

        config =
            { default | buffer = 10 }
    in
        { notes = []
        , currentFile = Nothing
        , settings = defaultSettings
        , fileOpenedByPlugin = False
        , virtualList = VirtualList.initWithConfig config
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
    { includeFolders = []
    , excludeFolders = []
    , showNotesWithoutId = True
    , idField = "id"
    }


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
    | NotesProvided ( List NoteMeta, List String )
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

        NotesProvided ( notes, changedNotes ) ->
            updateNotes model notes changedNotes

        VirtualListMsg virtualListMsg ->
            translate (VirtualList.update virtualListMsg model.virtualList) model


translate : ( VirtualList.Model, Cmd VirtualList.Msg ) -> Model -> ( Model, Cmd Msg )
translate ( virtualListModel, virtualListCmd ) model =
    ( { model | virtualList = virtualListModel }, Cmd.map VirtualListMsg virtualListCmd )


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
                Maybe.map NoteId.getNewIdInSubsequence id
            else
                Maybe.map NoteId.getNewIdInSequence id

        newUniqueId =
            Maybe.map (getUniqueId model.notes) newId

        fileContent =
            case newUniqueId of
                Just justId ->
                    createNoteContent model.settings.idField justId

                Nothing ->
                    ""
    in
        ( model, Ports.createNote ( newPath, fileContent ) )


getUniqueId : List NoteMeta -> String -> String
getUniqueId notes id =
    -- Prevents infinite loops
    getUniqueIdHelper notes id 25


getUniqueIdHelper : List NoteMeta -> String -> Int -> String
getUniqueIdHelper notes id remainingAttempts =
    if remainingAttempts <= 0 then
        id
    else if isNoteIdTaken notes id then
        getUniqueIdHelper notes (NoteId.getNewIdInSequence id) (remainingAttempts - 1)
    else
        id


isNoteIdTaken : List NoteMeta -> String -> Bool
isNoteIdTaken notes noteId =
    List.any (\note -> note.id == Just noteId) notes


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


updateNotes : Model -> List NoteMeta -> List String -> ( Model, Cmd Msg )
updateNotes model newNotes changedNotes =
    let
        ids =
            sortNotes newNotes
                |> List.map .filePath

        ( newVirtualList, virtualListCmd ) =
            VirtualList.setItemsAndRemeasure model.virtualList ids changedNotes
    in
        ( { model
            | notes = newNotes
            , virtualList = newVirtualList
          }
        , Cmd.map VirtualListMsg virtualListCmd
        )


sortNotes : List NoteMeta -> List NoteMeta
sortNotes notes =
    List.sortWith
        (\a b ->
            case ( a.id, b.id ) of
                ( Nothing, Nothing ) ->
                    compare a.title b.title

                ( Nothing, Just _ ) ->
                    GT

                ( Just _, Nothing ) ->
                    LT

                ( Just idA, Just idB ) ->
                    NoteId.compareId idA idB
        )
        notes


handleFileRename : Model -> ( String, String ) -> ( Model, Cmd Msg )
handleFileRename model ( oldPath, newPath ) =
    let
        updatedCurrentFile =
            updateCurrentFile model.currentFile oldPath newPath

        cmd =
            if model.currentFile == Just oldPath then
                scrollToNote model newPath
            else
                Cmd.none
    in
        ( { model | currentFile = updatedCurrentFile }, cmd )


updateCurrentFile : Maybe String -> String -> String -> Maybe String
updateCurrentFile current oldPath newPath =
    if current == Just oldPath then
        Just newPath
    else
        current


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
    Cmd.map VirtualListMsg (VirtualList.scrollToItem model.virtualList path VirtualList.Center)



-- VIEW


view : Model -> Html Msg
view model =
    VirtualList.view (renderRow model) model.virtualList VirtualListMsg


renderRow : Model -> String -> Html Msg
renderRow model filePath =
    case getNoteByPath filePath model.notes of
        Just note ->
            renderNote model note

        Nothing ->
            div [] []


renderNote : Model -> NoteMeta -> Html Msg
renderNote model note =
    div
        [ Html.Attributes.classList
            [ ( "tree-item-self", True )
            , ( "is-clickable", True )
            , ( "is-active", Just note.filePath == model.currentFile )
            ]
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
