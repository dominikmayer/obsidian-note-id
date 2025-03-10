module Metadata exposing
    ( processMetadata
    , processRawNotes
    , updateNoteCache
    )

import Dict exposing (Dict)
import Ports exposing (NoteMeta, RawFileMeta)
import String


{-| Settings type from Main module
-}
type alias Settings =
    { includeFolders : List String
    , excludeFolders : List String
    , showNotesWithoutId : Bool
    , idField : String
    , tocField : String
    , tocLevel : Maybe Int
    , splitLevel : Int
    , indentation : Bool
    }


{-| Process multiple raw file metadata records into NoteMeta records
-}
processRawNotes : Settings -> List RawFileMeta -> List NoteMeta
processRawNotes settings rawMetas =
    rawMetas
        |> List.filterMap (processMetadata settings)


{-| Process a single file's metadata
-}
processMetadata : Settings -> RawFileMeta -> Maybe NoteMeta
processMetadata settings file =
    let
        filePath =
            file.path
                |> String.replace "\\" "/"
                -- convert Windows backslashes to forward slashes
                |> String.toLower

        -- Normalize folder paths to remove trailing slashes and convert to lowercase
        normInclude =
            settings.includeFolders
                |> List.map (\f -> f |> String.replace "/+" "" |> String.toLower)

        normExclude =
            settings.excludeFolders
                |> List.map (\f -> f |> String.replace "/+" "" |> String.toLower)

        -- Check if the file should be included based on folder settings
        included =
            List.isEmpty normInclude
                || List.any (\folder -> String.startsWith (folder ++ "/") filePath) normInclude

        excluded =
            List.any (\folder -> String.startsWith (folder ++ "/") filePath) normExclude

        -- Normalize frontmatter keys to lowercase for case-insensitive matching
        normalizedFrontmatter =
            file.frontmatter
                |> Maybe.map
                    (\fm ->
                        fm
                            |> List.map (\( k, v ) -> ( String.toLower k, v ))
                    )

        -- Find a value in the frontmatter list by key
        findInFrontmatter key fm =
            fm
                |> List.filter (\( k, _ ) -> k == key)
                |> List.head
                |> Maybe.map Tuple.second

        normalizedIdField =
            String.toLower settings.idField

        normalizedTocField =
            String.toLower settings.tocField

        -- Extract ID and TOC title from frontmatter
        id =
            normalizedFrontmatter
                |> Maybe.andThen (findInFrontmatter normalizedIdField)

        tocTitle =
            normalizedFrontmatter
                |> Maybe.andThen (findInFrontmatter normalizedTocField)
    in
    -- Apply filtering rules
    if not included || excluded then
        Nothing

    else if id == Nothing && not settings.showNotesWithoutId then
        Nothing

    else
        Just
            { title = file.basename
            , tocTitle = tocTitle
            , id = id
            , filePath = file.path
            }


{-| Update the note cache with a new or changed file
-}
updateNoteCache : Settings -> Dict String NoteMeta -> RawFileMeta -> Dict String NoteMeta
updateNoteCache settings cache rawMeta =
    case processMetadata settings rawMeta of
        Just noteMeta ->
            Dict.insert noteMeta.filePath noteMeta cache

        Nothing ->
            -- If file should not be included, remove it from cache if it existed
            Dict.remove rawMeta.path cache
