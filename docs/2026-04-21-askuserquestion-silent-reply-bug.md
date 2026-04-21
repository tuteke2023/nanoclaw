# AskUserQuestion silently swallowed agent replies

**Date:** 2026-04-21
**Area:** `container/agent-runner/src/index.ts`
**Symptom:** NanoClaw stored the user's inbound message, spawned the agent
container, the agent ran to completion — but no reply was sent to the channel.
The host log showed `subtype=success` with `result: null` and an earlier
`type=rate_limit_event` message (which looks alarming but is just an
informational signal about remaining rate-limit headroom, not an error).

## Root cause

The agent used `ToolSearch` with `select:AskUserQuestion` to load the SDK's
built-in `AskUserQuestion` tool, then called it to ask the user to pick XPM
job codes for three ambiguous time entries. `AskUserQuestion` is an
interactive tool that expects a host-side UI (like an IDE extension) to
surface an option picker. In a headless agent container there is no such UI,
so the tool returns immediately with:

```json
{
  "type": "tool_result",
  "content": "Answer questions?",
  "is_error": true,
  "tool_use_id": "..."
}
```

The SDK treats this error tool_result as the terminal event of the turn and
emits `type: result, subtype: success, result: null`. The agent had already
produced a perfectly good text reply in the *same* assistant turn as the
`AskUserQuestion` tool_use (text + tool_use in one message), but
`container/agent-runner/src/index.ts` only forwarded `message.result` —
which was null — so the user got nothing.

`allowedTools` did **not** block the tool. That option only gates auto-approval,
not availability; the SDK still loads any tool discovered via `ToolSearch`.

## Evidence from the failing session

Session `c6ec65f1-...` jsonl, lines 2747–2749:

- `2747 assistant text`: *"Yes — full SOP + all credentials are in memory. Last updated 7 April 2026. ..."*
- `2748 assistant tool_use`: `AskUserQuestion` with three job-code questions
- `2749 user tool_result`: `is_error: true`, content `"Answer questions?"`

Agent runner stdout:

```
[msg #14] type=user
[msg #15] type=result
Result #1: subtype=success
{"status":"success","result":null,"newSessionId":"c6ec65f1-..."}
```

Host log then had no `Agent output:` line and no outbound Telegram message.

## Fix

Two changes in `container/agent-runner/src/index.ts`:

1. **Block `AskUserQuestion` outright.** Use `disallowedTools:
   ['AskUserQuestion']` in the query options. Unlike `allowedTools`, this
   removes the tool from the model's context entirely, so it can't be loaded
   via `ToolSearch` either. The agent falls back to sending its reply through
   the regular channel (Telegram/IPC), which is what we want.

2. **Fallback to the last assistant text when the result is null.** During
   SDK iteration, keep the most recent assistant-message text content. If the
   query ends with a null `result`, emit that captured text instead. This is
   a safety net for *any* future SDK path that ends a turn with no final
   assistant message — silent failures become visible replies.

Both fixes are in one commit. They compose: (1) prevents the specific
failure mode; (2) catches analogous failures we haven't seen yet.

## Verification

- Stopped the stale agent container (`docker stop
  nanoclaw-telegram-main-1776772233954`).
- The host's retry logic (see `src/group-queue.ts` `scheduleRetry` and
  `src/index.ts` cursor rollback on error) re-processed the 11:50 message.
- In the retry, the agent picked a different path — used `SendMessage`
  directly — and the user received the reply. The fix is in the cached
  per-group copy at `data/sessions/telegram_main/agent-runner-src/index.ts`
  and will take effect on the next fresh container spawn.

## Why "rate limit" was a red herring

`type: rate_limit_event` in the SDK stream is *informational* — it reports
remaining capacity against per-org rate limits. It does not interrupt the
agent. The actual terminator was the errored `AskUserQuestion` tool_result.

## Related: messages queued during a running container

A separate observation from the investigation (not fixed here): when a
follow-up message arrives while the previous query is running, it is piped
into the container via IPC (`src/group-queue.ts` `sendMessage`) and the host
cursor advances immediately. If the container then produces `result: null`
for that piped message (the bug above), the host logs no `Agent output` and
no `Processing messages` entry appears for that specific inbound message —
because "Processing messages" is only logged for new container spawns, not
for IPC-piped follow-ups. This made the 2026-04-20 10:43 message look
"dropped" in logs; it was actually processed but silently returned no text,
for the same reason as above.
