module NoteId.Path exposing
    ( Path(..)
    , isSubpath
    , normalize
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


normalize : Path -> Path
normalize (Path path) =
    Path (path |> String.replace "/+" "" |> String.toLower)


isSubpath : Path -> Path -> Bool
isSubpath (Path parentPath) (Path childPath) =
    String.startsWith (parentPath ++ "/") childPath
