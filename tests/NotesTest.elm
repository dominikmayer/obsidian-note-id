module NotesTest exposing (all)

import Expect
import NoteId.Id as Id
import NoteId.NoteMeta exposing (NoteMeta)
import NoteId.Notes as Notes
import NoteId.Path exposing (Path(..))
import Test exposing (Test, describe, test)


all : Test
all =
    describe "Notes module"
        [ test "annotate handles large lists without stack overflow" <|
            \_ ->
                let
                    notes =
                        List.range 1 10000 |> List.map makeNote

                    result =
                        Notes.annotate notes
                in
                Expect.equal 10000 (Notes.paths result |> List.length)
        ]


makeNote : Int -> NoteMeta
makeNote i =
    { title = "Note " ++ String.fromInt i
    , tocTitle = Nothing
    , id = Just (Id.fromString (String.fromInt i))
    , filePath = Path ("note-" ++ String.fromInt i ++ ".md")
    }
