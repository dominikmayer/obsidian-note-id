module NoteId exposing (getNewIdInSequence, getNewChildId)


getNewIdInSequence : String -> String
getNewIdInSequence id =
    let
        ( start, end ) =
            incrementLastElement id
    in
        start ++ end


getNewChildId : String -> String
getNewChildId input =
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

        head :: tail ->
            let
                ( nextChar, carry ) =
                    incrementChar head
            in
                if carry then
                    incrementChars (String.fromList tail)
                        |> Maybe.map (\incrementedTail -> nextChar ++ incrementedTail)
                else
                    Just (nextChar ++ String.fromList tail)


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
                    ( String.fromList acc, charType head )

        c :: rest ->
            case acc of
                [] ->
                    compareElements [ c ] rest

                head :: _ ->
                    if charType head == charType c then
                        compareElements (c :: acc) rest
                    else
                        ( String.fromList acc |> String.reverse, charType head )
