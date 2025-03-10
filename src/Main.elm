module Main exposing (..)

import Browser
import Dict exposing (Dict)
import Html exposing (Html, div)
import Html.Attributes
import Html.Events exposing (onClick)
import Html.Events.Extra.Mouse as Mouse
import Html.Lazy exposing (lazy)
import Json.Decode as Decode
import Json.Encode as Encode
import Metadata
import NoteId
import NoteMeta exposing (NoteMeta)
import Notes exposing (Notes)
import Path exposing (Path(..))
import Ports exposing (RawFileMeta)
import Settings exposing (Settings)
import Task
import Vault exposing (Vault)
import VirtualList
import VirtualList.Config



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


type DisplayMode
    = TOC
    | Notes


type alias Model =
    { includedNotes : Notes
    , currentFile : Maybe Path
    , settings : Settings
    , scrollToNewlyOpenedNote : Bool
    , currentDisplayMode : DisplayMode
    , virtualList : VirtualList.Model
    , vault : Vault
    }


defaultModel : Model
defaultModel =
    let
        config =
            VirtualList.Config.default
                |> VirtualList.Config.setBuffer 10
    in
    { includedNotes = Notes.empty
    , currentFile = Nothing
    , settings = Settings.default
    , scrollToNewlyOpenedNote = True
    , currentDisplayMode = Notes
    , virtualList = VirtualList.initWithConfig config
    , vault = Vault.empty
    }


init : Encode.Value -> ( Model, Cmd Msg )
init flags =
    let
        model =
            { defaultModel
                | settings = Settings.decode Settings.default flags
                , currentFile = decodeActiveFile flags
            }
    in
    -- Won't find the note yet but will initiate the future scroll
    scrollToCurrentNote model


decodeActiveFile : Encode.Value -> Maybe Path
decodeActiveFile flags =
    Decode.decodeValue (Decode.field "activeFile" Decode.string) flags
        |> Result.toMaybe
        |> Maybe.map Path



-- UPDATE


type Msg
    = AttachRequested Path
    | ContextMenuTriggered Mouse.Event Path
    | DisplayChanged Bool
    | NewIdRequestedForNoteFromNote ( Path, Path, Bool )
    | NoteChangeReceived RawFileMeta
    | NoteClicked Path
    | NoteCreationRequested ( Path, Bool )
    | NoteDeleted Path
    | NoteOpened (Maybe Path)
    | NoteRenamed ( Path, Path )
    | RawFileMetaReceived (List RawFileMeta)
    | SearchRequested
    | ScrollRequested Path
    | SettingsChanged Ports.Settings
    | VirtualListMsg VirtualList.Msg


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        AttachRequested currentNotePath ->
            let
                allNotes =
                    Vault.filteredContent model.settings model.vault
                        |> List.filter (\note -> note.filePath /= currentNotePath)
                        |> List.map NoteMeta.forPort
            in
            ( model, Ports.provideNotesForAttach ( Path.toString currentNotePath, allNotes ) )

        ContextMenuTriggered event path ->
            let
                ( x, y ) =
                    event.clientPos
            in
            ( model, Ports.openContextMenu ( x, y, Path.toString path ) )

        DisplayChanged tocShown ->
            handleDisplayChange model tocShown

        NewIdRequestedForNoteFromNote ( for, from, subsequence ) ->
            let
                cmd =
                    Notes.getNewIdFromNote model.includedNotes from subsequence
                        |> Maybe.map (\id -> Ports.provideNewIdForNote ( id, Path.toString for ))
                        |> Maybe.withDefault Cmd.none
            in
            ( model, cmd )

        NoteChangeReceived rawMeta ->
            handleNoteChange model rawMeta

        NoteClicked filePath ->
            handleNoteClick model filePath

        NoteCreationRequested ( filePath, child ) ->
            createNote model filePath child

        NoteDeleted path ->
            handleFileDeleted model path

        NoteOpened filePath ->
            fileOpened model filePath

        NoteRenamed paths ->
            handleFileRename model paths

        RawFileMetaReceived rawMetas ->
            handleRawFileMetas model rawMetas

        SearchRequested ->
            ( model
            , Ports.provideNotesForSearch
                (Vault.filteredContent model.settings model.vault |> List.map NoteMeta.forPort)
            )

        ScrollRequested path ->
            scrollToNote model path

        SettingsChanged settings ->
            handleSettingsChange model settings

        VirtualListMsg virtualListMsg ->
            mapVirtualListResult (VirtualList.update virtualListMsg model.virtualList) model


handleDisplayChange : Model -> Bool -> ( Model, Cmd Msg )
handleDisplayChange model tocShown =
    let
        newDisplay =
            if tocShown then
                TOC

            else
                Notes
    in
    reloadNotesAndScroll model newDisplay


reloadNotesAndScroll : Model -> DisplayMode -> ( Model, Cmd Msg )
reloadNotesAndScroll model newDisplay =
    let
        ( newModelPre, displayCmd ) =
            updateDisplay model newDisplay

        ( newModel, scrollCmd ) =
            scrollToCurrentNote newModelPre
    in
    ( newModel, Cmd.batch [ displayCmd, scrollCmd ] )


handleNoteClick : Model -> Path -> ( Model, Cmd Msg )
handleNoteClick model filePath =
    let
        ( newModel, updateCmd ) =
            if model.currentDisplayMode == TOC then
                updateDisplay model Notes

            else
                ( model, Cmd.none )

        fileIsAlreadyOpen =
            Maybe.map ((==) filePath) model.currentFile |> Maybe.withDefault False

        fileCmd =
            if fileIsAlreadyOpen then
                Task.perform (\_ -> ScrollRequested filePath) (Task.succeed ())

            else
                Ports.openFile (Path.toString filePath)

        cmd =
            Cmd.batch [ fileCmd, updateCmd ]
    in
    ( { newModel | scrollToNewlyOpenedNote = model.currentDisplayMode == TOC }, cmd )


updateDisplay : Model -> DisplayMode -> ( Model, Cmd Msg )
updateDisplay model newDisplay =
    let
        ( updatedModel, updateCmd ) =
            updateVirtualList { model | currentDisplayMode = newDisplay }

        cmd =
            Cmd.batch
                [ updateCmd
                , Ports.toggleTOCButton (newDisplay == TOC)
                ]
    in
    ( updatedModel
    , cmd
    )


handleSettingsChange : Model -> Ports.Settings -> ( Model, Cmd Msg )
handleSettingsChange model portSettings =
    updateNotes
        { model | settings = Settings.fromPort portSettings }
        []


updateVirtualList : Model -> ( Model, Cmd Msg )
updateVirtualList model =
    Notes.paths model.includedNotes
        |> updateVirtualListHelper model


updateVirtualListHelper : Model -> List Path -> ( Model, Cmd Msg )
updateVirtualListHelper model idsToRemeasure =
    let
        filteredNotes =
            filterNotesForDisplay model.currentDisplayMode model.settings.tocLevel model.includedNotes

        ( newVirtualList, virtualListCmd ) =
            VirtualList.setItemsAndRemeasure model.virtualList
                { newIds = Notes.paths filteredNotes |> List.map Path.toString
                , idsToRemeasure = idsToRemeasure |> List.map Path.toString
                }
    in
    ( { model
        | virtualList = newVirtualList
      }
    , Cmd.map VirtualListMsg virtualListCmd
    )


mapVirtualListResult : ( VirtualList.Model, Cmd VirtualList.Msg ) -> Model -> ( Model, Cmd Msg )
mapVirtualListResult ( virtualListModel, virtualListCmd ) model =
    ( { model | virtualList = virtualListModel }, Cmd.map VirtualListMsg virtualListCmd )


createNote : Model -> Path -> Bool -> ( Model, Cmd Msg )
createNote model path child =
    let
        newPath =
            Path.withoutFileName path ++ "/Untitled.md"

        fileContent =
            Notes.getNewIdFromNote model.includedNotes path child
                |> Maybe.map (createNoteContent model.settings.idField)
                |> Maybe.withDefault ""
    in
    ( model, Ports.createNote ( newPath, fileContent ) )


createNoteContent : String -> String -> String
createNoteContent idNameFromSettings id =
    let
        idName =
            if String.isEmpty idNameFromSettings then
                "id"

            else
                idNameFromSettings
    in
    "---\n" ++ idName ++ ": " ++ id ++ "\n---"


updateNotes : Model -> List Path -> ( Model, Cmd Msg )
updateNotes model changedNotes =
    let
        newNotes =
            Vault.filteredContent model.settings model.vault

        annotatedNotes =
            Notes.annotate (NoteMeta.sort newNotes)

        affectedIds =
            if Notes.isEmpty model.includedNotes then
                -- On initial load, all new notes need to be measured
                Notes.paths annotatedNotes

            else
                let
                    changedSplitIds =
                        Notes.splitChanges { oldNotes = model.includedNotes, newNotes = annotatedNotes }
                in
                List.append changedSplitIds changedNotes

        modelWithSortedNotes =
            { model | includedNotes = annotatedNotes }

        ( modelWithUpdatedVirtualList, cmd ) =
            updateVirtualListHelper modelWithSortedNotes affectedIds
    in
    ( modelWithUpdatedVirtualList, cmd )


filterNotesForDisplay : DisplayMode -> Maybe Int -> Notes -> Notes
filterNotesForDisplay display maybeTocLevel notes =
    case display of
        TOC ->
            Notes.filter (showInToc maybeTocLevel) notes

        Notes ->
            notes


showInToc : Maybe Int -> NoteMeta -> Bool
showInToc maybeTocLevel note =
    let
        hasTocField =
            note.tocTitle /= Nothing

        noteLevel =
            Maybe.withDefault 0 (note.id |> Maybe.map NoteId.level)
    in
    case maybeTocLevel of
        Just tocLevel ->
            hasTocField || (0 < noteLevel && noteLevel <= tocLevel)

        Nothing ->
            hasTocField


handleFileRename : Model -> ( Path, Path ) -> ( Model, Cmd Msg )
handleFileRename model ( oldPath, newPath ) =
    let
        updatedCurrentFile =
            updateCurrentFile model.currentFile oldPath newPath

        updatedVault =
            Vault.rename model.vault { oldPath = oldPath, newPath = newPath }

        oldCurrentFile =
            model.currentFile

        updatedModel =
            { model | currentFile = updatedCurrentFile, vault = updatedVault }

        ( newModel, scrollCmd ) =
            if oldCurrentFile == Just oldPath then
                scrollToNote updatedModel newPath

            else
                ( updatedModel, Cmd.none )

        ( finalModel, listCmd ) =
            updateNotes newModel [ oldPath, newPath ]
    in
    ( finalModel, Cmd.batch [ scrollCmd, listCmd ] )


updateCurrentFile : Maybe Path -> Path -> Path -> Maybe Path
updateCurrentFile current oldPath newPath =
    if current == Just oldPath then
        Just newPath

    else
        current


fileOpened : Model -> Maybe Path -> ( Model, Cmd Msg )
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


scrollToExternallyOpenedNote : Model -> Path -> ( Model, Cmd Msg )
scrollToExternallyOpenedNote model path =
    if model.scrollToNewlyOpenedNote then
        scrollToNote model path

    else
        ( { model | scrollToNewlyOpenedNote = True }, Cmd.none )


scrollToNote : Model -> Path -> ( Model, Cmd Msg )
scrollToNote model path =
    let
        ( newVirtualList, virtualListCmd ) =
            VirtualList.scrollToItem model.virtualList (Path.toString path) VirtualList.Center
    in
    ( { model | virtualList = newVirtualList }
    , Cmd.map VirtualListMsg virtualListCmd
    )


scrollToCurrentNote : Model -> ( Model, Cmd Msg )
scrollToCurrentNote model =
    model.currentFile
        |> Maybe.map (scrollToNote model)
        |> Maybe.withDefault ( model, Cmd.none )



-- VIEW


view : Model -> Html Msg
view model =
    VirtualList.view (lazy (renderRow model)) model.virtualList VirtualListMsg


renderRow : Model -> String -> Html Msg
renderRow model filePath =
    case Notes.getNoteByPath (Path filePath) model.includedNotes of
        Just noteWithSplit ->
            renderNote model noteWithSplit.note noteWithSplit.splitLevel

        Nothing ->
            div [] []


renderNote : Model -> NoteMeta -> Maybe Int -> Html Msg
renderNote model note maybeSplit =
    let
        marginTopStyle =
            if model.currentDisplayMode == TOC then
                []

            else
                case maybeSplit of
                    Just splitLevel ->
                        if 0 < splitLevel && splitLevel <= model.settings.splitLevel then
                            adaptedMarginTopStyle model.settings.splitLevel splitLevel

                        else
                            []

                    Nothing ->
                        []

        level =
            note.id
                |> Maybe.map NoteId.level
                |> Maybe.withDefault 0
                |> toFloat

        marginLeftStyle =
            if model.settings.indentation then
                [ marginLeft level ]

            else
                []

        title =
            if model.currentDisplayMode == TOC then
                Maybe.withDefault note.title note.tocTitle

            else
                note.title
    in
    div
        ([ Html.Attributes.classList
            [ ( "tree-item-self", True )
            , ( "is-clickable", True )
            , ( "is-active", Just note.filePath == model.currentFile )
            ]
         , Html.Attributes.attribute "data-path" (Path.toString note.filePath)
         , onClick (NoteClicked note.filePath)
         , Mouse.onContextMenu (\event -> ContextMenuTriggered event note.filePath)
         ]
            ++ marginTopStyle
        )
        [ div
            (Html.Attributes.class "tree-item-inner" :: marginLeftStyle)
            (case note.id of
                Just id ->
                    [ Html.span [ Html.Attributes.class "note-id" ] [ Html.text (id ++ ": ") ]
                    , Html.text title
                    ]

                Nothing ->
                    [ Html.text title ]
            )
        ]


adaptedMarginTopStyle : Int -> Int -> List (Html.Attribute msg)
adaptedMarginTopStyle splitLevelSetting level =
    let
        availableSizes =
            [ "--size-4-8"
            , "--size-4-9"
            , "--size-4-12"
            , "--size-4-16"
            , "--size-4-18"
            ]

        sizeMap : Dict Int String
        sizeMap =
            List.indexedMap (\i size -> ( splitLevelSetting - i, size )) availableSizes
                |> Dict.fromList

        marginSize =
            Dict.get level sizeMap
                |> Maybe.withDefault "--size-4-18"
    in
    [ Html.Attributes.style "margin-top" ("var(" ++ marginSize ++ ")") ]


marginLeft : Float -> Html.Attribute msg
marginLeft level =
    Html.Attributes.style "margin-left" ("calc(var(--size-2-3) * " ++ String.fromFloat level ++ ")")



-- New handlers for raw metadata


handleRawFileMetas : Model -> List RawFileMeta -> ( Model, Cmd Msg )
handleRawFileMetas model rawMetas =
    let
        vault =
            Vault.fill (fieldNames model.settings) rawMetas

        changedFiles =
            Vault.filteredContent model.settings vault
                |> List.map .filePath
    in
    updateNotes { model | vault = vault } changedFiles


handleNoteChange : Model -> RawFileMeta -> ( Model, Cmd Msg )
handleNoteChange model rawMeta =
    let
        changedNote =
            Metadata.processMetadata (fieldNames model.settings) rawMeta

        updatedVault =
            Vault.insert changedNote model.vault
    in
    updateNotes { model | vault = updatedVault } [ changedNote.filePath ]


fieldNames : Settings -> Metadata.FieldNames
fieldNames settings =
    { id = settings.idField, toc = settings.tocField }


handleFileDeleted : Model -> Path -> ( Model, Cmd Msg )
handleFileDeleted model path =
    let
        updatedVault =
            Vault.remove path model.vault
    in
    updateNotes { model | vault = updatedVault } []


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Ports.receiveCreateNote (\( path, subsequence ) -> NoteCreationRequested ( Path path, subsequence ))
        , Ports.receiveDisplayIsToc DisplayChanged
        , Ports.receiveFileOpen (\path -> NoteOpened (Maybe.map Path path))
        , Ports.receiveFileRenamed (\( from, to ) -> NoteRenamed ( Path from, Path to ))
        , Ports.receiveFileDeleted (\path -> NoteDeleted (Path path))
        , Ports.receiveRawFileMeta RawFileMetaReceived
        , Ports.receiveFileChange NoteChangeReceived
        , Ports.receiveGetNewIdForNoteFromNote (\( for, from, subsequence ) -> NewIdRequestedForNoteFromNote ( Path for, Path from, subsequence ))
        , Ports.receiveSettings SettingsChanged
        , Ports.receiveRequestSearch (\_ -> SearchRequested)
        , Ports.receiveRequestAttach (\path -> AttachRequested (Path path))
        ]
