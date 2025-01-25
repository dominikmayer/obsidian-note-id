port module Ports exposing (..)


port openFile : String -> Cmd msg


port receiveNotes : (List NoteMeta -> msg) -> Sub msg


port receiveFileOpen : (Maybe String -> msg) -> Sub msg


port receiveFileRenamed : (( String, String ) -> msg) -> Sub msg


type alias NoteMeta =
    { title : String
    , id : Maybe String
    , filePath : String
    }
