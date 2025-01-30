module NoteId exposing (getNewIdInSequence, getNewIdInSubsequence, parts, IdPart(..), toString)

import Parser exposing (Parser, (|.), (|=), succeed, oneOf, map, chompWhile, getChompedString, problem, andThen)


getNewIdInSequence : String -> String
getNewIdInSequence id =
    let
        ( start, end ) =
            incrementLastElement id
    in
        start ++ end


getNewIdInSubsequence : String -> String
getNewIdInSubsequence input =
    let
        ( _, elementType ) =
            getLastElement input

        newLastElement =
            case elementType of
                Digit ->
                    "a"

                Letter ->
                    "1"

                Other ->
                    ""
    in
        input ++ newLastElement


incrementLastElement : String -> ( String, String )
incrementLastElement input =
    let
        ( lastElement, elementType ) =
            getLastElement input

        start =
            String.dropRight (String.length lastElement) input

        incrementedLastElement =
            incrementElement lastElement elementType
    in
        ( start, Maybe.withDefault lastElement incrementedLastElement )


incrementElement : String -> CharType -> Maybe String
incrementElement element elementType =
    case elementType of
        Digit ->
            String.toInt element
                |> Maybe.andThen (\num -> Just (num + 1))
                |> Maybe.map String.fromInt

        Letter ->
            incrementString element

        Other ->
            Nothing


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


type CharType
    = Digit
    | Letter
    | Other


charType : Char -> CharType
charType c =
    if Char.isDigit c then
        Digit
    else if Char.isAlpha c then
        Letter
    else
        Other


getLastElement : String -> ( String, CharType )
getLastElement string =
    let
        ( reversedElement, elementType ) =
            compareElements [] (string |> String.reverse |> String.toList)
    in
        ( String.reverse reversedElement, elementType )


compareElements : List Char -> List Char -> ( String, CharType )
compareElements acc remaining =
    case remaining of
        [] ->
            case acc of
                [] ->
                    ( "", Other )

                head :: _ ->
                    ( String.fromList (List.reverse acc), charType head )

        c :: rest ->
            case acc of
                [] ->
                    compareElements [ c ] rest

                head :: _ ->
                    if charType head == charType c then
                        compareElements (c :: acc) rest
                    else
                        ( String.fromList (List.reverse acc), charType head )


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
