module NoteMeta exposing (NoteMeta)


type alias NoteMeta =
    { title : String
    , tocTitle : Maybe String
    , id : Maybe String
    , filePath : String
    }
