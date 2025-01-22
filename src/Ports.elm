port module Ports exposing (..)

import Json.Decode as Decode
import Json.Encode as Encode


port sendNotes : List Encode.Value -> Cmd msg


port receiveNotes : (List Note -> msg) -> Sub msg


type alias Note =
    { title : String
    , id : String
    }


decodeNote : Decode.Decoder Note
decodeNote =
    Decode.map2 Note
        (Decode.field "title" Decode.string)
        (Decode.field "id" Decode.string)
