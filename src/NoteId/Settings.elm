module NoteId.Settings exposing
    ( IdField(..)
    , Settings
    , TocField(..)
    , TocLevel(..)
    , decode
    , default
    , fromPort
    , idFieldToString
    , tocFieldToString
    )

import Json.Decode as Decode
import NoteId.Path exposing (Path(..))
import NoteId.Ports as Ports


type alias Settings =
    { includeFolders : List Path
    , excludeFolders : List Path
    , showNotesWithoutId : Bool
    , idField : IdField
    , tocField : TocField
    , tocLevel : TocLevel
    , splitLevel : Int
    , indentation : Bool
    }


type TocLevel
    = TocLevel Int
    | NoAutoToc


type IdField
    = IdField String


idFieldToString : IdField -> String
idFieldToString (IdField idField) =
    idField


type TocField
    = TocField String


tocFieldToString : TocField -> String
tocFieldToString (TocField tocField) =
    tocField


default : Settings
default =
    { includeFolders = []
    , excludeFolders = []
    , showNotesWithoutId = True
    , idField = IdField "id"
    , tocField = TocField "toc"
    , tocLevel = TocLevel 1
    , splitLevel = 0
    , indentation = False
    }


decode : Settings -> Decode.Value -> Settings
decode settings newSettings =
    case Decode.decodeValue (Decode.field "settings" partialSettingsDecoder) newSettings of
        Ok decoded ->
            decoded settings

        Err _ ->
            settings


partialSettingsDecoder : Decode.Decoder (Settings -> Settings)
partialSettingsDecoder =
    Decode.map8
        (\includeFolders excludeFolders showNotesWithoutId idField tocField newTocLevel splitLevel indentation settings ->
            { settings
                | includeFolders = includeFolders |> Maybe.map (List.map Path) |> Maybe.withDefault settings.includeFolders
                , excludeFolders = excludeFolders |> Maybe.map (List.map Path) |> Maybe.withDefault settings.excludeFolders
                , showNotesWithoutId = showNotesWithoutId |> Maybe.withDefault settings.showNotesWithoutId
                , idField = idField |> Maybe.map IdField |> Maybe.withDefault settings.idField
                , tocField = tocField |> Maybe.map TocField |> Maybe.withDefault settings.tocField
                , tocLevel = newTocLevel
                , splitLevel = splitLevel |> Maybe.withDefault settings.splitLevel
                , indentation = indentation |> Maybe.withDefault settings.indentation
            }
        )
        (Decode.field "includeFolders" (Decode.list Decode.string) |> Decode.maybe)
        (Decode.field "excludeFolders" (Decode.list Decode.string) |> Decode.maybe)
        (Decode.field "showNotesWithoutId" Decode.bool |> Decode.maybe)
        (Decode.field "idField" Decode.string |> Decode.maybe)
        (Decode.field "tocField" Decode.string |> Decode.maybe)
        tocLevelDecoder
        (Decode.field "splitLevel" Decode.int |> Decode.maybe)
        (Decode.field "indentation" Decode.bool |> Decode.maybe)


tocLevelDecoder : Decode.Decoder TocLevel
tocLevelDecoder =
    Decode.map2
        (\autoToc tocLevel ->
            if autoToc then
                TocLevel tocLevel

            else
                NoAutoToc
        )
        (Decode.field "autoToc" Decode.bool |> Decode.maybe |> Decode.map (Maybe.withDefault True))
        (Decode.field "tocLevel" Decode.int |> Decode.maybe |> Decode.map (Maybe.withDefault 1))


fromPort : Ports.Settings -> Settings
fromPort portSettings =
    { includeFolders = List.map Path portSettings.includeFolders
    , excludeFolders = List.map Path portSettings.excludeFolders
    , showNotesWithoutId = portSettings.showNotesWithoutId
    , idField = IdField portSettings.idField
    , tocField = TocField portSettings.tocField
    , tocLevel =
        if portSettings.autoToc then
            TocLevel portSettings.tocLevel

        else
            NoAutoToc
    , splitLevel = portSettings.splitLevel
    , indentation = portSettings.indentation
    }
