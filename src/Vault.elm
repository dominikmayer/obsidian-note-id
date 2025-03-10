module Vault exposing (Vault, empty, fill, filteredContent, insert, remove, rename)

import Dict exposing (Dict)
import Metadata exposing (FieldNames)
import NoteMeta exposing (NoteMeta)
import Ports exposing (RawFileMeta)
import Settings exposing (Settings)


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
        |> List.foldl (\note cache -> Dict.insert note.filePath note cache) Dict.empty
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
                |> String.replace "\\" "/"
                -- convert Windows backslashes to forward slashes
                |> String.toLower

        normInclude =
            settings.includeFolders
                |> List.map (\f -> f |> String.replace "/+" "" |> String.toLower)

        normExclude =
            settings.excludeFolders
                |> List.map (\f -> f |> String.replace "/+" "" |> String.toLower)

        included =
            List.isEmpty normInclude
                || List.any (\folder -> String.startsWith (folder ++ "/") filePath) normInclude

        excluded =
            List.any (\folder -> String.startsWith (folder ++ "/") filePath) normExclude
    in
    if not included || excluded then
        False

    else if note.id == Nothing && not settings.showNotesWithoutId then
        False

    else
        True


rename : Vault -> { oldPath : String, newPath : String } -> Vault
rename (Vault vault) { oldPath, newPath } =
    case Dict.get oldPath vault of
        Just note ->
            let
                updatedNote =
                    { note | filePath = newPath, title = getBaseName newPath }
            in
            vault
                |> Dict.remove oldPath
                |> Dict.insert newPath updatedNote
                |> Vault

        Nothing ->
            Vault vault


getBaseName : String -> String
getBaseName path =
    path
        |> String.replace "\\" "/"
        |> String.split "/"
        |> List.reverse
        |> List.head
        |> Maybe.withDefault ""
        |> String.replace ".md" ""


remove : String -> Vault -> Vault
remove path (Vault vault) =
    vault
        |> Dict.remove path
        |> Vault


insert : NoteMeta -> Vault -> Vault
insert meta (Vault vault) =
    vault
        |> Dict.insert meta.filePath meta
        |> Vault
