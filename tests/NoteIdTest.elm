module NoteIdTest exposing (all)

import Test exposing (Test, describe, test)
import Expect
import NoteId exposing (getNewIdInSequence, getNewIdInSubsequence)
import NoteId exposing (IdPart(..), parts)


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
            , ( "1.2.8", "1.2.9" )
            , ( "7.9", "7.10" )
            ]
            ++ testGetNewIdsInSubsequence
                [ ( "abc1", "abc1a" )
                , ( "abc1da", "abc1da1" )
                , ( "12abc2db27e", "12abc2db27e1" )
                , ( "1.2a8f9", "1.2a8f9a" )
                , ( "abca", "abca1" )
                , ( "1.27ag7f9zz", "1.27ag7f9zz1" )
                , ( "1.2.8", "1.2.8a" )
                , ( "7.9", "7.9a" )
                ]
            ++ testParts
                [ ( "abc1a", [ Letters "abc", Number 1, Letters "a" ] )
                , ( "abc1da21", [ Letters "abc", Number 1, Letters "da", Number 21 ] )
                , ( "12abc2db27e", [ Number 12, Letters "abc", Number 2, Letters "db", Number 27, Letters "e" ] )
                , ( "1.2a8f9", [ Number 1, Delimiter ".", Number 2, Letters "a", Number 8, Letters "f", Number 9 ] )
                , ( "abca", [ Letters "abca" ] )
                , ( "41as3.27ag.7f9zz"
                  , [ Number 41
                    , Letters "as"
                    , Number 3
                    , Delimiter "."
                    , Number 27
                    , Letters "ag"
                    , Delimiter "."
                    , Number 7
                    , Letters "f"
                    , Number 9
                    , Letters "zz"
                    ]
                  )
                ]
            ++ testCompare
                [ ( "1.1a", "1.1a", EQ )
                , ( "1.1a", "1.1ab", LT )
                , ( "1.1ab", "1.1ab1", LT )
                , ( "1.1ab1", "1.1ab12", LT )
                , ( "1.1ab12", "1.1ab12", EQ )
                , ( "1.2.23.9", "1.23.10", LT )
                , ( "1.2.22.9", "1.22.9", LT )
                , ( "", "", EQ )
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


testParts : List ( String, List IdPart ) -> List Test
testParts cases =
    List.concatMap testSingleParts cases


testSingleParts : ( String, List IdPart ) -> List Test
testSingleParts ( id, expectedSplit ) =
    let
        idParts =
            case parts id of
                Ok partsList ->
                    partsList

                Err _ ->
                    []
    in
        [ test (id ++ " split incorrectly") <|
            \_ ->
                Expect.equal expectedSplit idParts
        , test (id ++ " not being put together correctly") <|
            \_ ->
                Expect.equal id (NoteId.toString idParts)
        ]


testCompare : List ( String, String, Order ) -> List Test
testCompare cases =
    List.concatMap testSingleCompare cases


testSingleCompare : ( String, String, Order ) -> List Test
testSingleCompare ( a, b, order ) =
    [ test (a ++ " and " ++ b ++ " ordered incorrectly") <|
        \_ ->
            Expect.equal (NoteId.compareId a b) order
    ]
