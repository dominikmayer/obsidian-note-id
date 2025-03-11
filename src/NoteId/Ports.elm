port module NoteId.Ports exposing (..)

--- PORTS


port createNote : ( String, String ) -> Cmd msg


port openContextMenu : ( Float, Float, String ) -> Cmd msg


port openFile : String -> Cmd msg


port provideNewIdForNote : ( String, String ) -> Cmd msg


port provideNotesForAttach : ( String, List NoteMeta ) -> Cmd msg


port provideNotesForSearch : List NoteMeta -> Cmd msg


port toggleTOCButton : Bool -> Cmd msg



--- SUBSCRIPTIONS


port receiveCreateNote : (( String, Bool ) -> msg) -> Sub msg


port receiveDisplayIsToc : (Bool -> msg) -> Sub msg


port receiveFileRenamed : (( String, String ) -> msg) -> Sub msg


port receiveFileOpen : (Maybe String -> msg) -> Sub msg


port receiveFilter : (Maybe String -> msg) -> Sub msg


port receiveGetNewIdForNoteFromNote : (( String, String, Bool ) -> msg) -> Sub msg


port receiveRawFileMeta : (List RawFileMeta -> msg) -> Sub msg


port receiveFileChange : (RawFileMeta -> msg) -> Sub msg


port receiveFileDeleted : (String -> msg) -> Sub msg


port receiveRequestAttach : (String -> msg) -> Sub msg


port receiveRequestSearch : (() -> msg) -> Sub msg


port receiveSettings : (Settings -> msg) -> Sub msg


type alias RawFileMeta =
    { path : String
    , basename : String
    , frontmatter : Maybe (List ( String, String ))
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
    , autoToc : Bool
    , tocLevel : Int
    , splitLevel : Int
    , indentation : Bool
    }
