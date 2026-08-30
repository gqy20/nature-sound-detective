# Prompt Registry

`config/prompts/*.yaml` is the single source of truth for text and media prompts.
Do not edit `app/generated_prompts.py` or
`mobile/lib/core/ai/generated_prompts.dart` by hand.

## Workflow

1. Edit the relevant YAML file.
2. Bump its `version` when prompt behavior or output contracts change.
3. Run `make prompts`.
4. Run `make prompts-check` and the relevant service tests.

`make verify` includes `prompts-check`, so stale generated files fail verification.

## Boundaries

YAML owns prompt wording, declared variables, negative prompts, prompt versions,
and model-generation parameters that are part of the prompt contract. Code still
owns credentials, endpoints, timeouts, request protocols, input preparation,
validation, safety enforcement, retries, fallbacks, and product settings such as
the final video duration and resolution.

Never put API keys, user recordings, rendered user data, or other secrets in the
prompt registry. Rendered prompts are treated as sensitive and must not be logged.
