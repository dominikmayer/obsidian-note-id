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
    ## Inputs:

    - `existing_notes`: list of objects, each with
      - `id`: string like "1.2a3"
      - `title`: string
    - `new_note`: object with
      - `title`: string
    ## Rules:

    1. Every `new_id` must include at least one dot (second-level or deeper).
    2. Never duplicate an existing ID.
    3. Always assign either:
       - A **top-level sub-ID** of the form `X.1` (where `X` is an existing top-level ID), or
       - A **child ID** under an existing parent (never generate `1.1a` unless `1.1` exists).
    Select the IDs of all existing notes that are most conceptually or semantically related to a new note, providing clear justification for each choice.

    Your objectives:

    - Analyze the new note’s content to determine its core idea.
    - Identify all eligible related notes among existing notes:
        - Exclude any note with a placeholder, “Untitled”, non-descriptive, or generic title.
        - Only consider real, existing notes as candidates.
    - For each eligible note, reason through whether it is conceptually or thematically most related to the new note’s main idea.
    - For every selected note, provide a short, clear human rationale (never referencing or echoing the ID itself), written in the correct language.
    - List all valid candidate note IDs in order of most to least likely or appropriate fit, based on the conceptual relationship to the new note.
    - Do not propose or infer any new IDs, structural changes, or branch assignments.
    - Never include any placeholder, non-existent, or generic notes as candidates.

    # Steps

    1. **Core Idea Extraction:**
       - Analyze the title and content of the new note to clarify its main concept.
    2. **Eligibility Filtering:**
       - From the existing notes, exclude any that are placeholders, non-descriptive/“Untitled”/numerical-only titles, or otherwise generic.
    3. **Semantic Matching:**
       - For each eligible note, reason through whether it is among the most semantically or conceptually related to the new note.
    4. **Likelihood Ordering:**
       - Rank all valid candidate IDs in order of most to least closely related.
    5. **Language Detection:**
       - Use the most prominent language among descriptive note titles for rationales; fallback to the new note's language if unclear; default to English as needed.
    6. **Rationale (Reasoning Before Output):**
       - Perform all eligibility and reasoning before writing each rationale, which justifies why the new note is closely related to the selected note (never mention IDs in the rationale).
    7. **Invalid Inputs:**
       - If key input fields are missing or invalid, output a single JSON object with a clear rationale explaining the issue—do not suggest any IDs.

    # Output Format

    - Output a single valid JSON array of one or more objects.
        - Each object must contain:
            - "existing_id": string — the ID of an existing, eligible note that is closely conceptually related
            - "rationale": string — concise, human-readable justification for this connection (never referencing IDs), in the correct language
    - If multiple candidates are valid, list each as a separate object in the array, in order of best fit (most to least likely).
    - No markdown, headings, commentary, or extra output—only the valid JSON array.
    - If inputs are invalid or missing, return a single JSON object with a rationale explaining the issue and do not return any ID.
    - Rationales must be short, specific, and free of ID references, technical terms, or code.

    # Examples

    [
      { "existing_id": "2.1", "rationale": "Explores an alternative approach to authentication similar to the concept in the new note." },
      { "existing_id": "1.4", "rationale": "Discusses credential storage protocols that align closely with this idea." }
    ]
    (Real-world examples should include all existing note IDs strongly related to the new note’s concept; these are illustrative only.)

    # Notes

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

    **Reminder:** For a new note, output an ordered list of the most conceptually related existing note IDs, each with a clear, concise justification free from any mention of note IDs or technical references. Never generate, imply, or create new IDs. Output only the required JSON.
    """
        ++ notes
