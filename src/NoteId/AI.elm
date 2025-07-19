module NoteId.AI exposing (Error(..), Prompt(..), Response, Result(..), openAIRequest)

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


type alias SuggestionContent =
    { existingNotes : List { id : String, title : String }
    , newNote : { title : String, content : String }
    }


type Prompt
    = SuggestId SuggestionContent


type Error
    = BadRequest String
    | InvalidKey
    | NetworkProblem
    | Timeout
    | UnknownError Int


openAIRequest : (Result -> msg) -> Prompt -> Cmd msg
openAIRequest toMsg prompt =
    let
        payload =
            promptToPayload prompt
    in
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


promptToPayload : Prompt -> Json.Encode.Value
promptToPayload prompt =
    case prompt of
        SuggestId { existingNotes, newNote } ->
            let
                existingNotesJson =
                    Json.Encode.list
                        (\note ->
                            Json.Encode.object
                                [ ( "id", Json.Encode.string note.id )
                                , ( "title", Json.Encode.string note.title )
                                ]
                        )
                        existingNotes

                newNoteJson =
                    Json.Encode.object
                        [ ( "title", Json.Encode.string newNote.title )
                        , ( "content", Json.Encode.string newNote.content )
                        ]

                structuredData =
                    Json.Encode.object
                        [ ( "existing_notes", existingNotesJson )
                        , ( "new_note", newNoteJson )
                        ]

                promptText =
                    Json.Encode.encode 2 structuredData
                        |> suggestionPrompt
            in
            Json.Encode.object
                [ ( "model", Json.Encode.string "gpt-4o-mini" )
                , ( "input", Json.Encode.string <| Debug.log "Prompt" promptText )
                ]


suggestionPrompt : String -> String
suggestionPrompt notes =
    """
    You are an assistant that assigns Zettelkasten IDs.

    ## Inputs:

    - `existing_notes`: list of objects, each with
      - `id`: string like "1.2a3"
      - `title`: string
    - `new_note`: object with
      - `title`: string
      - `content`: the new note's full text

    ## Rules:

    1. Every `new_id` must include at least one dot (second-level or deeper).
    2. Never duplicate an existing ID.
    3. Always assign either:
       - A **top-level sub-ID** of the form `X.1` (where `X` is an existing top-level ID), or
       - A **child ID** under an existing parent (never generate `1.1a` unless `1.1` exists).
    4. Select a parent note using **semantic understanding** — not keyword matching:
       a. Compare the `new_note.content` against all `existing_notes.title`.
       b. Use the following signals to judge conceptual similarity:
          - Shared concepts or topics (e.g., "family structure", "cultural tradition", "legal remedies")
          - Shared framing (e.g., both are about "mechanisms of legal restoration" or "preserving lineage")
          - If multiple titles mention the same domain (e.g. Zettelkasten, law, Japan), that strengthens their candidacy.
       c. Ignore any note with a **non-descriptive title**:
          - Titles like `"Untitled"`, `"Unbenannt"`, `"Note (1)"`, or meaningless numberings must be excluded from consideration.
          - Exception: only allow these if they are part of a clearly semantically labeled group (e.g., `1.6e1` + `1.6e1a` + `1.6e1a1`, all with real content-based clustering).
       d. When in doubt, prefer a parent with a **descriptive, specific title** over one with generic or placeholder labels.
       e. If no match exceeds a reasonable threshold of conceptual overlap (i.e. >70%), fall back to Rule 6 and create a new top-level sub-ID.
    5. If a valid parent is found:
       a. Use its ID as the base (e.g. `2.3`).
       b. Append a new segment:
          - If base ends in a digit → add a lowercase letter (`2.3`→`2.3a`).
          - If base ends in a letter → add a digit (`2.3a`→`2.3a1`).
       c. If that candidate already exists, increment the final segment until you find a unique and valid ID under that parent. Only use IDs that respect the parent structure (e.g., don't assign "1.7.99a" unless "1.7.99" exists).
    6. If no parent clearly fits:
       a. Let M = highest existing top-level integer.
       b. Assign `new_id = "M.1"`.
    7. If two or more parents feel plausible:
       - Return a JSON array of objects sorted by probability, each with `"new_id"` and a concise, human-friendly `"rationale"`.
    8. Determine the rationale language by:
       a. Using the language of the majority of `existing_notes` titles,
       b. If no majority, using the language of `new_note.content`,
       c. If that is also undetectable, default to English.
    9. Always include a clear, human-readable rationale explaining placement.
    10. Output must be valid JSON only
        - Always return a JSON array of one or more objects.
        - Each object must contain:
          - `"new_id"`: a unique string ID like "2.3a1"
          - `"rationale"`: a short, human-readable explanation
        - Do not include any comments, headings, analysis, or other text outside the JSON block.

    ## Output Format

    Return only a valid JSON array of suggestions. No comments, headings, or explanation outside the array.

    Each suggestion must be an object with:
    - "new_id": the new Zettelkasten ID
    - "rationale": a short, human-readable reason in the correct language

    Even if only one ID is appropriate, still return it in a JSON array.

    ### Correct:
    [
        { "new_id": "1.2a3", "rationale": "Ergänzt die Diskussion über XY um kulturelle Perspektiven" }
    ]

    ### Incorrect:
    - Output wrapped in ```json
    - Added commentary, "We assign ID 1.2a3 because..."
    - Not an array

    ## Examples:

    ### Deepening OAuth Flow

    existing_notes = [
      {"id":"2.1","title":"User Authentication"},
      {"id":"2.1a","title":"OAuth Flow"}
    ]

    new_note.content explains refresh-token usage → [
      { "new_id": "2.1a1", "rationale": "Builds on the OAuth series by detailing refresh-token handling" }
    ]

    ### Expanding Zettelkasten Basics

    existing_notes = [
      {"id":"1.1","title":"Zettelkasten Basics"}
    ]

    new_note.content explores interlinking strategies → [
      { "new_id": "1.1a", "rationale": "Fügt Verknüpfungsstrategien zu den Zettelkasten-Grundlagen hinzu" }
    ]

    ### New subtopic when no fit

    existing_notes = [
      {"id":"3.1","title":"Graph Theory Concepts"},
      {"id":"4.1","title":"Cache Invalidation Methods"}
    ]

    new_note.content on functional patterns → [
      { "new_id": "4.1", "rationale": "Introduces a new functional-patterns subtopic" }
    ]

    ### Tie between two clusters

    existing_notes = [
      {"id":"3.2","title":"Cache Design"},
      {"id":"4.1","title":"Invalidation Techniques"}
    ]

    Content matches both → [
      { "new_id":"3.2a", "rationale":"Continues Cache Design with layout details" },
      { "new_id":"4.1b", "rationale":"Equally extends Invalidation Techniques" }
    ]

    ## Task Data
    """
        ++ notes
