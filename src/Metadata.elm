module Metadata exposing
    ( FieldNames
    , processMetadata
    , processRawNotes
    , updateNoteCache
    )

import Dict exposing (Dict)
import Ports exposing (NoteMeta, RawFileMeta)
import String


type alias FieldNames =
    { id : String, toc : String }


{-| Process multiple raw file metadata records into NoteMeta records
-}
processRawNotes : FieldNames -> List RawFileMeta -> List NoteMeta
processRawNotes fieldNames rawMetas =
    rawMetas
        |> List.map (processMetadata fieldNames)


processMetadata : FieldNames -> RawFileMeta -> NoteMeta
processMetadata fieldNames file =
    let
        -- Normalize frontmatter keys to lowercase for case-insensitive matching
        normalizedFrontmatter =
            file.frontmatter
                |> Maybe.map
                    (\fm ->
                        fm
                            |> List.map (\( k, v ) -> ( String.toLower k, v ))
                    )

        -- Find a value in the frontmatter list by key
        findInFrontmatter key frontmatter =
            frontmatter
                |> List.filter (\( k, _ ) -> k == key)
                |> List.head
                |> Maybe.map Tuple.second

        -- Extract ID and TOC title from frontmatter
        id =
            normalizedFrontmatter
                |> Maybe.andThen (String.toLower fieldNames.id |> findInFrontmatter)

        tocTitle =
            normalizedFrontmatter
                |> Maybe.andThen (String.toLower fieldNames.toc |> findInFrontmatter)
    in
    { title = file.basename
    , tocTitle = tocTitle
    , id = id
    , filePath = file.path
    }


{-| Update the note cache with a new or changed file
-}
updateNoteCache : FieldNames -> Dict String NoteMeta -> RawFileMeta -> Dict String NoteMeta
updateNoteCache fieldNames cache rawMeta =
    let
        noteMeta =
            processMetadata fieldNames rawMeta
    in
    Dict.insert noteMeta.filePath noteMeta cache
