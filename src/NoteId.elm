module NoteId exposing (getNewIdInSequence, getNewIdInSubsequence, parts, IdPart(..), toString, compareId)

import List.Extra exposing (last)
import Parser exposing (Parser, (|.), (|=), succeed, oneOf, map, chompWhile, getChompedString, problem, andThen)


getNewIdInSequence : String -> String
getNewIdInSequence id =
    let
        idParts =
            parts id

        updatedParts =
            case List.reverse idParts of
                (Number n) :: rest ->
                    List.reverse (Number (n + 1) :: rest)

                (Letters s) :: rest ->
                    case incrementString s of
                        Just newLetters ->
                            List.reverse (Letters newLetters :: rest)

                        Nothing ->
                            idParts

                _ ->
                    idParts
    in
        toString updatedParts


getNewIdInSubsequence : String -> String
getNewIdInSubsequence id =
    let
        idParts =
            parts id

        updatedParts =
            case last idParts of
                Just (Number _) ->
                    idParts ++ [ Letters "a" ]

                Just (Letters _) ->
                    idParts ++ [ Number 1 ]

                Just (Delimiter _) ->
                    idParts

                Nothing ->
                    idParts
    in
        toString updatedParts


incrementString : String -> Maybe String
incrementString str =
    if str == "" then
        Nothing
    else
        str
            |> String.reverse
            |> incrementChars
            |> Maybe.map String.reverse


incrementChars : String -> Maybe String
incrementChars str =
    case String.toList str of
        [] ->
            Nothing

        chars ->
            let
                ( reversedNewString, carry ) =
                    propagateCarry chars
            in
                if carry then
                    Just ("a" ++ reversedNewString)
                else
                    Just reversedNewString


propagateCarry : List Char -> ( String, Bool )
propagateCarry chars =
    case chars of
        [] ->
            ( "", True )

        head :: tail ->
            let
                ( nextChar, carry ) =
                    incrementChar head
            in
                if carry then
                    let
                        ( incrementedTail, nextCarry ) =
                            propagateCarry tail
                    in
                        ( nextChar ++ incrementedTail, nextCarry )
                else
                    ( nextChar ++ String.fromList tail, False )


incrementChar : Char -> ( String, Bool )
incrementChar char =
    if char == 'z' then
        ( "a", True )
        -- Overflow to 'a', with carry
    else
        ( String.fromChar (Char.fromCode (Char.toCode char + 1)), False )


type IdPart
    = Number Int
    | Letters String
    | Delimiter String


parts : String -> List IdPart
parts id =
    case Parser.run idParser id of
        Ok result ->
            result

        Err _ ->
            []


idParser : Parser (List IdPart)
idParser =
    Parser.loop [] parseParts


parseParts : List IdPart -> Parser (Parser.Step (List IdPart) (List IdPart))
parseParts parsed =
    oneOf
        [ parseNumber
            |> map (\p -> Parser.Loop (parsed ++ [ p ]))
        , parseLetters
            |> map (\p -> Parser.Loop (parsed ++ [ p ]))
        , parseDelimiter
            |> map (\p -> Parser.Loop (parsed ++ [ p ]))
        , succeed (Parser.Done parsed)
        ]


parseNumber : Parser IdPart
parseNumber =
    getChompedString (chompWhile Char.isDigit)
        |> andThen
            (\s ->
                case String.toInt s of
                    Just n ->
                        succeed (Number n)

                    Nothing ->
                        problem "Invalid number"
            )


parseLetters : Parser IdPart
parseLetters =
    getChompedString (chompWhile Char.isAlpha)
        |> andThen
            (\s ->
                if s == "" then
                    problem "Expected letters"
                else
                    succeed (Letters s)
            )


parseDelimiter : Parser IdPart
parseDelimiter =
    getChompedString (chompWhile (\c -> not (Char.isAlpha c || Char.isDigit c)))
        |> andThen
            (\s ->
                if s == "" then
                    problem "Expected delimiter"
                else
                    succeed (Delimiter s)
            )


toString : List IdPart -> String
toString idParts =
    idParts
        |> List.map
            (\part ->
                case part of
                    Number n ->
                        String.fromInt n

                    Letters s ->
                        s

                    Delimiter s ->
                        s
            )
        |> String.concat


compareId : String -> String -> Order
compareId a b =
    compareIdParts (parts a) (parts b)


compareIdParts : List IdPart -> List IdPart -> Order
compareIdParts id1 id2 =
    case ( id1, id2 ) of
        ( [], [] ) ->
            EQ

        ( [], _ ) ->
            LT

        ( _, [] ) ->
            GT

        ( part1 :: rest1, part2 :: rest2 ) ->
            case compareIdPart part1 part2 of
                EQ ->
                    compareIdParts rest1 rest2

                order ->
                    order


compareIdPart : IdPart -> IdPart -> Order
compareIdPart a b =
    case ( a, b ) of
        ( Number n1, Number n2 ) ->
            compare n1 n2

        ( Number _, Letters _ ) ->
            LT

        ( Letters _, Number _ ) ->
            GT

        ( Letters s1, Letters s2 ) ->
            case compare (String.length s1) (String.length s2) of
                EQ ->
                    compare s1 s2

                order ->
                    order

        ( Delimiter delimiterA, Delimiter delimiterB ) ->
            compare delimiterA delimiterB

        ( Delimiter _, _ ) ->
            LT

        ( _, Delimiter _ ) ->
            GT
