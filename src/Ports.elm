port module Ports exposing (..)


port createNote : ( String, String ) -> Cmd msg


port openFile : String -> Cmd msg


port openContextMenu : ( Float, Float, String ) -> Cmd msg


port receiveNotes : (( List NoteMeta, List String ) -> msg) -> Sub msg


port receiveFileOpen : (Maybe String -> msg) -> Sub msg


port receiveCreateNote : (( String, Bool ) -> msg) -> Sub msg


port receiveDisplayIsToc : (Bool -> msg) -> Sub msg


port receiveFileRenamed : (( String, String ) -> msg) -> Sub msg


port receiveSettings : (Settings -> msg) -> Sub msg


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
