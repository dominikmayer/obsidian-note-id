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
import NoteId
import Ports exposing (..)
import Process
import Task
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


type Display
    = TOC
    | Notes


type alias Model =
    { notes : List NoteMeta
    , splitLevels :
        Dict String (Maybe Int)
        -- TODO: Move to Display
    , currentFile : Maybe String
    , settings : Settings
    , fileOpenedByPlugin : Bool
    , display : Display
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
        , splitLevels = Dict.empty
        , currentFile = Nothing
        , settings = defaultSettings
        , fileOpenedByPlugin = False
        , display = Notes
        , virtualList = VirtualList.initWithConfig config
        }


type alias NoteMeta =
    { title : String
    , tocTitle : Maybe String
    , id : Maybe String
    , filePath : String
    }


type alias Settings =
    { includeFolders : List String
    , excludeFolders : List String
    , showNotesWithoutId : Bool
    , idField : String
    , tocField : String
    , splitLevel : Int
    , indentation : Bool
    }


defaultSettings : Settings
defaultSettings =
    { includeFolders = []
    , excludeFolders = []
    , showNotesWithoutId = True
    , idField = "id"
    , tocField = "toc"
    , splitLevel = 0
    , indentation = False
    }


init : Encode.Value -> ( Model, Cmd Msg )
init flags =
    ( { defaultModel | settings = decodeSettings defaultSettings flags }
    , Cmd.none
    )


decodeSettings : Settings -> Decode.Value -> Settings
decodeSettings settings newSettings =
    case Decode.decodeValue partialSettingsDecoder newSettings of
        Ok decoded ->
            decoded settings

        Err _ ->
            settings



-- UPDATE


type Msg
    = ContextMenuTriggered Mouse.Event String
    | DisplayChanged Bool
    | FileOpened (Maybe String)
    | FileRenamed ( String, String )
    | NoteClicked String
    | NoteCreationRequested ( String, Bool )
    | NotesProvided ( List NoteMeta, List String )
    | ScrollToCurrentNote
    | SettingsChanged Settings
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

        DisplayChanged tocShown ->
            let
                newDisplay =
                    if tocShown then
                        TOC
                    else
                        Notes

                ( newModel, displayCmd ) =
                    updateDisplay model newDisplay

                scrollCmd =
                    Process.sleep 100
                        |> Task.perform (\_ -> ScrollToCurrentNote)
            in
                ( newModel, Cmd.batch [ displayCmd, scrollCmd ] )

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

        ScrollToCurrentNote ->
            ( model, scrollToCurrentNote model )

        SettingsChanged settings ->
            handleSettingsChange model settings

        VirtualListMsg virtualListMsg ->
            translate (VirtualList.update virtualListMsg model.virtualList) model


updateDisplay : Model -> Display -> ( Model, Cmd Msg )
updateDisplay model newDisplay =
    let
        newModel =
            { model | display = newDisplay }

        ( updatedModel, cmd ) =
            updateVirtualList newModel
    in
        ( updatedModel
        , cmd
        )


handleSettingsChange : Model -> Settings -> ( Model, Cmd Msg )
handleSettingsChange model settings =
    let
        ( newModel, cmd ) =
            updateVirtualList model
    in
        ( { newModel
            | settings = settings
          }
        , cmd
        )


updateVirtualList : Model -> ( Model, Cmd Msg )
updateVirtualList model =
    let
        filteredNotes =
            filterNotes model.display model.notes

        ids =
            sortNotes filteredNotes
                |> List.map .filePath

        splitLevels =
            splitLevelByFilePath filteredNotes

        ( newVirtualList, virtualListCmd ) =
            VirtualList.setItemsAndRemeasureAll model.virtualList ids
    in
        ( { model
            | virtualList = newVirtualList
            , splitLevels = splitLevels
          }
        , Cmd.map VirtualListMsg virtualListCmd
        )


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
createNoteContent idNameFromSettings id =
    let
        idName =
            if String.isEmpty idNameFromSettings then
                "id"
            else
                idNameFromSettings
    in
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
        filteredNotes =
            filterNotes model.display newNotes

        ids =
            sortNotes filteredNotes
                |> List.map .filePath

        splitLevels =
            splitLevelByFilePath filteredNotes

        ( newVirtualList, virtualListCmd ) =
            VirtualList.setItemsAndRemeasure model.virtualList { newIds = ids, idsToRemeasure = changedNotes }
    in
        ( { model
            | notes = newNotes
            , virtualList = newVirtualList
            , splitLevels = splitLevels
          }
        , Cmd.map VirtualListMsg virtualListCmd
        )


filterNotes : Display -> List NoteMeta -> List NoteMeta
filterNotes display notes =
    case display of
        TOC ->
            List.filter (\note -> note.tocTitle /= Nothing) notes

        Notes ->
            notes


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


scrollToCurrentNote : Model -> Cmd Msg
scrollToCurrentNote model =
    Maybe.map (scrollToNote model) model.currentFile
        |> Maybe.withDefault Cmd.none



-- VIEW


type alias NoteWithSplit =
    { note : NoteMeta
    , splitLevel : Maybe Int
    }


annotateNotes : List NoteMeta -> List NoteWithSplit
annotateNotes notes =
    let
        sortedNotes =
            sortNotes notes

        annotate xs =
            case xs of
                [] ->
                    []

                first :: rest ->
                    let
                        initialSplit =
                            case first.id of
                                Nothing ->
                                    Just 1

                                Just _ ->
                                    Nothing
                    in
                        { note = first, splitLevel = initialSplit }
                            :: annotateRest first rest

        annotateRest prev xs =
            case xs of
                [] ->
                    []

                current :: rest ->
                    let
                        computedSplit =
                            case ( prev.id, current.id ) of
                                ( Just prevId, Just currId ) ->
                                    NoteId.splitLevel prevId currId

                                ( Just _, Nothing ) ->
                                    Just 1

                                ( Nothing, Just _ ) ->
                                    Just 1

                                ( Nothing, Nothing ) ->
                                    -- If two consecutive notes lack an id, assume they belong to the same block.
                                    Nothing
                    in
                        { note = current, splitLevel = computedSplit }
                            :: annotateRest current rest
    in
        annotate sortedNotes


splitLevelByFilePath : List NoteMeta -> Dict String (Maybe Int)
splitLevelByFilePath notes =
    annotateNotes notes
        |> List.map (\nws -> ( nws.note.filePath, nws.splitLevel ))
        |> Dict.fromList


view : Model -> Html Msg
view model =
    VirtualList.view (lazy (renderRow model)) model.virtualList VirtualListMsg


renderRow : Model -> String -> Html Msg
renderRow model filePath =
    case getNoteByPath filePath model.notes of
        Just note ->
            let
                maybeSplit =
                    Dict.get filePath model.splitLevels
                        |> Maybe.andThen identity
            in
                renderNote model note maybeSplit

        Nothing ->
            div [] []


renderNote : Model -> NoteMeta -> Maybe Int -> Html Msg
renderNote model note maybeSplit =
    let
        marginTopStyle =
            if model.display == TOC then
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
            if model.display == TOC then
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
             , Html.Attributes.attribute "data-path" note.filePath
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


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Ports.receiveNotes NotesProvided
        , Ports.receiveCreateNote NoteCreationRequested
        , Ports.receiveDisplayIsToc DisplayChanged
        , Ports.receiveFileOpen FileOpened
        , Ports.receiveFileRenamed FileRenamed
        , Ports.receiveSettings SettingsChanged
        ]


partialSettingsDecoder : Decode.Decoder (Settings -> Settings)
partialSettingsDecoder =
    Decode.map7
        (\includeFolders excludeFolders showNotesWithoutId idField tocField splitLevel indentation settings ->
            { settings
                | includeFolders = includeFolders |> Maybe.withDefault settings.includeFolders
                , excludeFolders = excludeFolders |> Maybe.withDefault settings.excludeFolders
                , showNotesWithoutId = showNotesWithoutId |> Maybe.withDefault settings.showNotesWithoutId
                , idField = idField |> Maybe.withDefault settings.idField
                , tocField = tocField |> Maybe.withDefault settings.tocField
                , splitLevel = splitLevel |> Maybe.withDefault settings.splitLevel
                , indentation = indentation |> Maybe.withDefault settings.indentation
            }
        )
        (Decode.field "includeFolders" (Decode.list Decode.string) |> Decode.maybe)
        (Decode.field "excludeFolders" (Decode.list Decode.string) |> Decode.maybe)
        (Decode.field "showNotesWithoutId" Decode.bool |> Decode.maybe)
        (Decode.field "idField" Decode.string |> Decode.maybe)
        (Decode.field "tocField" Decode.string |> Decode.maybe)
        (Decode.field "splitLevel" Decode.int |> Decode.maybe)
        (Decode.field "indentation" Decode.bool |> Decode.maybe)
