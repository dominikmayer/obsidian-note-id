module NoteId.Vault exposing (Vault, empty, fill, filteredContent, insert, remove, rename)

import Dict exposing (Dict)
import NoteId.Metadata as Metadata exposing (FieldNames)
import NoteId.NoteMeta exposing (NoteMeta)
import NoteId.Path as Path exposing (Path(..))
import NoteId.Ports exposing (RawFileMeta)
import NoteId.Settings exposing (Settings)


type Vault
    = Vault InternalVault


type alias InternalVault =
    Dict String NoteMeta


empty : Vault
empty =
    Vault Dict.empty


fill : FieldNames -> List RawFileMeta -> Vault
fill fieldNames notes =
    notes
        |> Metadata.processRawNotes fieldNames
        |> List.foldl (\note cache -> Dict.insert (Path.toString note.filePath) note cache) Dict.empty
        |> Vault


content : Vault -> List NoteMeta
content (Vault vault) =
    Dict.values vault


filteredContent : Settings -> Vault -> List NoteMeta
filteredContent settings vault =
    content vault
        |> filterNotesAccordingToSettings settings


filterNotesAccordingToSettings : Settings -> List NoteMeta -> List NoteMeta
filterNotesAccordingToSettings settings notes =
    notes
        |> List.filter (isIncluded settings)


isIncluded : Settings -> NoteMeta -> Bool
isIncluded settings note =
    let
        filePath =
            note.filePath
                |> Path.toString
                |> String.replace "\\" "/"
                -- convert Windows backslashes to forward slashes
                |> String.toLower
                |> Path

        normInclude =
            settings.includeFolders
                |> List.map Path.normalize

        normExclude =
            settings.excludeFolders
                |> List.map Path.normalize

        included =
            List.isEmpty normInclude
                || List.any (\folder -> Path.isSubpath folder filePath) normInclude

        excluded =
            List.any (\folder -> Path.isSubpath folder filePath) normExclude
    in
    if not included || excluded then
        False

    else if note.id == Nothing && not settings.showNotesWithoutId then
        False

    else
        True


rename : Vault -> { oldPath : Path, newPath : Path } -> Vault
rename (Vault vault) { oldPath, newPath } =
    case Dict.get (Path.toString oldPath) vault of
        Just note ->
            let
                updatedNote =
                    { note | filePath = newPath, title = getBaseName newPath }
            in
            vault
                |> Dict.remove (Path.toString oldPath)
                |> Dict.insert (Path.toString newPath) updatedNote
                |> Vault

        Nothing ->
            Vault vault


getBaseName : Path -> String
getBaseName (Path path) =
    path
        |> String.replace "\\" "/"
        |> String.split "/"
        |> List.reverse
        |> List.head
        |> Maybe.withDefault ""
        |> String.replace ".md" ""


remove : Path -> Vault -> Vault
remove path (Vault vault) =
    vault
        |> Dict.remove (Path.toString path)
        |> Vault


insert : NoteMeta -> Vault -> Vault
insert meta (Vault vault) =
    vault
        |> Dict.insert (Path.toString meta.filePath) meta
        |> Vault
