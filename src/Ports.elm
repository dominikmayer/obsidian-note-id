port module Ports exposing (..)

import Json.Decode as Decode
import Json.Encode as Encode


port openFile : String -> Cmd msg


port sendNotes : List Encode.Value -> Cmd msg


port receiveNotes : (List Note -> msg) -> Sub msg


type alias Note =
    { title : String
    , id : Maybe String
    , filePath : String
    }


decodeNote : Decode.Decoder Note
decodeNote =
    Decode.map3 Note
        (Decode.field "title" Decode.string)
        (Decode.field "id" (Decode.string |> Decode.andThen decodeMaybeId))
        (Decode.field "filePath" Decode.string)


decodeMaybeId : String -> Decode.Decoder (Maybe String)
decodeMaybeId id =
    if id == "null" then
        Decode.succeed Nothing
    else
        Decode.succeed (Just id)
