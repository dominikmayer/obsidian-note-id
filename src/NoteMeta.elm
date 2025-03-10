module NoteMeta exposing (NoteMeta, sort)

import NoteId


type alias NoteMeta =
    { title : String
    , tocTitle : Maybe String
    , id : Maybe String
    , filePath : String
    }


sort : List NoteMeta -> List NoteMeta
sort notes =
    List.sortWith
        (\a b ->
            case ( a.id, b.id ) of
                ( Nothing, Nothing ) ->
                    compare (String.toLower a.title) (String.toLower b.title)

                ( Nothing, Just _ ) ->
                    GT

                ( Just _, Nothing ) ->
                    LT

                ( Just idA, Just idB ) ->
                    NoteId.compareId idA idB
        )
        notes
