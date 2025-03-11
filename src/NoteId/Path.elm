module NoteId.Path exposing
    ( Path(..)
    , toString
    , withoutFileName
    )


type Path
    = Path String


toString : Path -> String
toString (Path path) =
    path


withoutFileName : Path -> String
withoutFileName (Path filePath) =
    let
        components =
            String.split "/" filePath
    in
    components
        |> List.take (List.length components - 1)
        |> String.join "/"
