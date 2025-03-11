module NoteId.NoteMeta exposing (NoteMeta, forPort, sort)

import NoteId.Id
import NoteId.Path as Path exposing (Path)
import NoteId.Ports as Ports


type alias NoteMeta =
    { title : String
    , tocTitle : Maybe String
    , id : Maybe String
    , filePath : Path
    }


forPort : NoteMeta -> Ports.NoteMeta
forPort note =
    { title = note.title
    , tocTitle = note.tocTitle
    , id = note.id
    , filePath = Path.toString note.filePath
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
                    NoteId.Id.compareId idA idB
        )
        notes
