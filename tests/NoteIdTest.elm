module NoteIdTest exposing (all)

import Test exposing (Test, describe, test)
import Expect
import NoteId exposing (getNewIdInSequence, getNewIdInSubsequence)


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
            ++ testGetNewIdsInSubsequence
                [ ( "abc1", "abc1a" )
                , ( "abc1da", "abc1da1" )
                , ( "12abc2db27e", "12abc2db27e1" )
                , ( "1.2a8f9", "1.2a8f9a" )
                , ( "abca", "abca1" )
                , ( "1.27ag7f9zz", "1.27ag7f9zz1" )
                ]


testGetNewIdsInSequence : List ( String, String ) -> List Test
testGetNewIdsInSequence cases =
    List.map testGetNewIdInSequence cases


testGetNewIdInSequence : ( String, String ) -> Test
testGetNewIdInSequence ( id, expectedIncrementedId ) =
    test (id ++ " should be incremented to " ++ expectedIncrementedId) <|
        \_ ->
            Expect.equal expectedIncrementedId (getNewIdInSequence id)


testGetNewIdsInSubsequence : List ( String, String ) -> List Test
testGetNewIdsInSubsequence cases =
    List.map testGetNewIdInSubsequence cases


testGetNewIdInSubsequence : ( String, String ) -> Test
testGetNewIdInSubsequence ( id, expectedIncrementedId ) =
    test (id ++ " should get a subsequence of " ++ expectedIncrementedId) <|
        \_ ->
            Expect.equal expectedIncrementedId (getNewIdInSubsequence id)
