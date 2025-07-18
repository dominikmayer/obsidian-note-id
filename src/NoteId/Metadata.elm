module NoteId.Metadata exposing
    ( FieldNames
    , processMetadata
    , processRawNotes
    )

import NoteId.Id as Id
import NoteId.NoteMeta exposing (NoteMeta)
import NoteId.Path exposing (Path(..))
import NoteId.Ports exposing (RawFileMeta)
import NoteId.Settings as Settings exposing (IdField, TocField)
import String


type alias FieldNames =
    { id : IdField, toc : TocField }


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
                |> Maybe.andThen (fieldNames.id |> Settings.idFieldToString |> String.toLower |> findInFrontmatter)
                |> Maybe.map Id.fromString

        tocTitle =
            normalizedFrontmatter
                |> Maybe.andThen (fieldNames.toc |> Settings.tocFieldToString |> String.toLower |> findInFrontmatter)
    in
    { title = file.basename
    , tocTitle = tocTitle
    , id = id
    , filePath = Path file.path
    }
