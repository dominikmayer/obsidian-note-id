module NoteId.Notes exposing
    ( Notes
    , annotate
    , empty
    , filter
    , getNewIdFromNote
    , getNoteByPath
    , isEmpty
    , paths
    , splitChanges
    )

import Dict exposing (Dict)
import List
import NoteId.Id as Id exposing (Id, Progression(..))
import NoteId.NoteMeta exposing (NoteMeta)
import NoteId.Path as Path exposing (Path)



-- CONSTANTS


uniqueIdRetries : Int
uniqueIdRetries =
    50


type Notes
    = Notes (List NoteWithSplit)


type alias NoteWithSplit =
    { note : NoteMeta
    , splitLevel : Maybe Int
    }


empty : Notes
empty =
    Notes []


isEmpty : Notes -> Bool
isEmpty (Notes notes) =
    List.isEmpty notes


filter : (NoteMeta -> Bool) -> Notes -> Notes
filter predicate (Notes notes) =
    Notes (List.filter (\noteWithSplit -> predicate noteWithSplit.note) notes)


paths : Notes -> List Path
paths (Notes notes) =
    List.map (.note >> .filePath) notes


getNewIdFromNote : Notes -> Path -> Progression -> Maybe Id
getNewIdFromNote (Notes notes) path child =
    let
        id =
            getNoteByPath path (Notes notes)
                |> Maybe.andThen (\noteWithSplit -> noteWithSplit.note.id)
    in
    Maybe.map (getId child) id
        |> Maybe.andThen (getUniqueId notes)


getId : Progression -> Id -> Id
getId progression id =
    case progression of
        Subsequence ->
            Id.getNewIdInSubsequence id

        Sequence ->
            Id.getNewIdInSequence id


getUniqueId : List NoteWithSplit -> Id -> Maybe Id
getUniqueId notes id =
    -- Prevents infinite loops
    generateUniqueId notes id uniqueIdRetries


generateUniqueId : List NoteWithSplit -> Id -> Int -> Maybe Id
generateUniqueId notes id remainingAttempts =
    if remainingAttempts <= 0 then
        Nothing

    else if isNoteIdTaken notes id then
        generateUniqueId notes (Id.getNewIdInSequence id) (remainingAttempts - 1)

    else
        Just id


isNoteIdTaken : List NoteWithSplit -> Id -> Bool
isNoteIdTaken notes noteId =
    List.any (\noteWithSplit -> noteWithSplit.note.id == Just noteId) notes


getNoteByPath : Path -> Notes -> Maybe NoteWithSplit
getNoteByPath path (Notes notes) =
    notes
        |> List.filter (\noteWithSplit -> noteWithSplit.note.filePath == path)
        |> List.head


splitMap : Notes -> Dict String (Maybe Int)
splitMap (Notes notes) =
    notes
        |> List.map (\noteWithSplit -> ( Path.toString noteWithSplit.note.filePath, noteWithSplit.splitLevel ))
        |> Dict.fromList


splitChanges : { oldNotes : Notes, newNotes : Notes } -> List Path
splitChanges { oldNotes, newNotes } =
    newNotes
        |> filter
            (splitHasChanged
                { oldNoteMap = splitMap oldNotes
                , newNoteMap = splitMap newNotes
                }
            )
        |> paths


splitHasChanged : { oldNoteMap : Dict String (Maybe Int), newNoteMap : Dict String (Maybe Int) } -> NoteMeta -> Bool
splitHasChanged { oldNoteMap, newNoteMap } note =
    let
        oldSplit =
            Dict.get (Path.toString note.filePath) oldNoteMap

        newSplit =
            Dict.get (Path.toString note.filePath) newNoteMap
    in
    oldSplit /= newSplit


annotate : List NoteMeta -> Notes
annotate notes =
    let
        annotateNote xs =
            case xs of
                [] ->
                    []

                first :: rest ->
                    let
                        initialSplit =
                            case first.id of
                                Nothing ->
                                    Just 1

                                Just _ ->
                                    Nothing
                    in
                    { note = first, splitLevel = initialSplit }
                        :: annotateRest first rest

        annotateRest prev xs =
            case xs of
                [] ->
                    []

                current :: rest ->
                    let
                        computedSplit =
                            case ( prev.id, current.id ) of
                                ( Just prevId, Just currId ) ->
                                    Id.splitLevel prevId currId

                                ( Just _, Nothing ) ->
                                    Just 1

                                ( Nothing, Just _ ) ->
                                    Just 1

                                ( Nothing, Nothing ) ->
                                    -- If two consecutive notes lack an id, assume they belong to the same block.
                                    Nothing
                    in
                    { note = current, splitLevel = computedSplit }
                        :: annotateRest current rest
    in
    Notes (annotateNote notes)
