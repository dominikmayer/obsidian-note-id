module Settings exposing (Settings, decode, default, fromPort)

import Json.Decode as Decode
import Ports


type alias Settings =
    { includeFolders : List String
    , excludeFolders : List String
    , showNotesWithoutId : Bool
    , idField : String
    , tocField : String
    , tocLevel : Maybe Int
    , splitLevel : Int
    , indentation : Bool
    }


default : Settings
default =
    { includeFolders = []
    , excludeFolders = []
    , showNotesWithoutId = True
    , idField = "id"
    , tocField = "toc"
    , tocLevel = Just 1
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
                | includeFolders = includeFolders |> Maybe.withDefault settings.includeFolders
                , excludeFolders = excludeFolders |> Maybe.withDefault settings.excludeFolders
                , showNotesWithoutId = showNotesWithoutId |> Maybe.withDefault settings.showNotesWithoutId
                , idField = idField |> Maybe.withDefault settings.idField
                , tocField = tocField |> Maybe.withDefault settings.tocField
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


tocLevelDecoder : Decode.Decoder (Maybe Int)
tocLevelDecoder =
    Decode.map2
        (\autoToc tocLevel ->
            if autoToc then
                tocLevel

            else
                Nothing
        )
        (Decode.field "autoToc" Decode.bool |> Decode.maybe |> Decode.map (Maybe.withDefault True))
        (Decode.field "tocLevel" Decode.int |> Decode.maybe)


fromPort : Ports.Settings -> Settings
fromPort portSettings =
    { includeFolders = portSettings.includeFolders
    , excludeFolders = portSettings.excludeFolders
    , showNotesWithoutId = portSettings.showNotesWithoutId
    , idField = portSettings.idField
    , tocField = portSettings.tocField
    , tocLevel =
        if portSettings.autoToc then
            Just portSettings.tocLevel

        else
            Nothing
    , splitLevel = portSettings.splitLevel
    , indentation = portSettings.indentation
    }
