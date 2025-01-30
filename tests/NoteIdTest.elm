module NoteIdTest exposing (all)

import Test exposing (Test, describe, test)
import Expect
import NoteId exposing (getNewIdInSequence, getNewChildId)


all : Test
all =
    describe "NoteId module" <|
        testGetNewIdsInSequence
            [ ( "abc1", "abc2" )
            , ( "abc1da", "abc1db" )
            , ( "12abc2db27e", "12abc2db27f" )
            , ( "1.2a8f9", "1.2a8f10" )
            , ( "abca", "abcb" )
            , ( "1.27ag7f9zz", "1.27ag7f9aaa" )
            ]



-- ++ [ test "getNewIdInSequence increments the last number" <|
--         \_ ->
--             Expect.equal "abc2" (getNewIdInSequence "abc1")
--    , test "getNewChildId appends 'a' if last element is a number" <|
--         \_ ->
--             Expect.equal "abc1a" (getNewChildId "abc1")
--    , test "getNewChildId appends '1' if last element is a letter" <|
--         \_ ->
--             Expect.equal "abca1" (getNewChildId "abca")
--    , test "getNewChildId does nothing if last element is neither a number nor letter" <|
--         \_ ->
--             Expect.equal "abc!" (getNewChildId "abc!")
-- , test "getLastElement extracts last number" <|
--     \_ ->
--         Expect.equal ("123", Digit) (getLastElement "abc123")
-- , test "getLastElement extracts last letter" <|
--     \_ ->
--         Expect.equal ("xyz", Letter) (getLastElement "abcxyz")
-- , test "getLastElement extracts last special character" <|
--     \_ ->
--         Expect.equal ("!", Other) (getLastElement "abc123!")
--    ]


testGetNewIdsInSequence : List ( String, String ) -> List Test
testGetNewIdsInSequence cases =
    List.map testGetNewIdInSequence cases


testGetNewIdInSequence : ( String, String ) -> Test
testGetNewIdInSequence ( id, expectedIncrementedId ) =
    test (id ++ " should be incremented to " ++ expectedIncrementedId) <|
        \_ ->
            Expect.equal expectedIncrementedId (getNewIdInSequence id)
