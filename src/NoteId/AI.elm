module NoteId.AI exposing (Error(..), Response, Result(..), openAIRequest)

import Http
import Json.Decode as Decode
import Json.Encode


type Result
    = Success Response
    | Failure Error


type alias Response =
    { id : String
    , object : String
    , createdAt : Int
    , status : String
    , model : String
    , text : String
    , usage :
        { inputTokens : Int
        , outputTokens : Int
        , totalTokens : Int
        }
    }


type Error
    = BadRequest String
    | InvalidKey
    | NetworkProblem
    | Timeout
    | UnknownError Int


openAIRequest : (Result -> msg) -> Json.Encode.Value -> Cmd msg
openAIRequest toMsg payload =
    Http.request
        { method = "POST"
        , headers =
            [ Http.header "Authorization" "Bearer API-Key"
            ]
        , url = "https://api.openai.com/v1/responses"
        , body = Http.jsonBody payload
        , expect =
            Http.expectJson
                (\result ->
                    case result of
                        Ok jsonResponse ->
                            case Decode.decodeValue openAIResponseDecoder jsonResponse of
                                Ok parsedResponse ->
                                    toMsg (Success parsedResponse)

                                Err decodeError ->
                                    toMsg (Failure (BadRequest ("JSON decode error: " ++ Decode.errorToString decodeError)))

                        Err error ->
                            case error of
                                Http.BadStatus 401 ->
                                    toMsg (Failure InvalidKey)

                                Http.BadStatus 400 ->
                                    toMsg (Failure (BadRequest "Bad request"))

                                Http.BadStatus code ->
                                    toMsg (Failure (UnknownError code))

                                Http.Timeout ->
                                    toMsg (Failure Timeout)

                                Http.NetworkError ->
                                    toMsg (Failure NetworkProblem)

                                Http.BadUrl _ ->
                                    toMsg (Failure (BadRequest "Malformed URL"))

                                Http.BadBody body ->
                                    toMsg (Failure (BadRequest body))
                )
                Decode.value
        , timeout = Nothing
        , tracker = Nothing
        }


openAIResponseDecoder : Decode.Decoder Response
openAIResponseDecoder =
    Decode.map7 Response
        (Decode.field "id" Decode.string)
        (Decode.field "object" Decode.string)
        (Decode.field "created_at" Decode.int)
        (Decode.field "status" Decode.string)
        (Decode.field "model" Decode.string)
        (Decode.field "output" (Decode.index 0 (Decode.field "content" (Decode.index 0 (Decode.field "text" Decode.string)))))
        (Decode.field "usage"
            (Decode.map3 (\input output total -> { inputTokens = input, outputTokens = output, totalTokens = total })
                (Decode.field "input_tokens" Decode.int)
                (Decode.field "output_tokens" Decode.int)
                (Decode.field "total_tokens" Decode.int)
            )
        )
