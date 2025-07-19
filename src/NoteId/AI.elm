module NoteId.AI exposing (Error(..), Result(..), openAIRequest)

import Http
import Json.Encode


type Result
    = Success String
    | Failure Error


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
            Http.expectString
                (\result ->
                    case result of
                        Ok body ->
                            toMsg (Success body)

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
        , timeout = Nothing
        , tracker = Nothing
        }
