# Telegram Document Support

**Date:** 2026-03-17

## Problem

When users sent documents (PDFs, etc.) via Telegram, the agent received only a `[Document: filename.pdf]` placeholder text and could not access the file content. This was the same pattern as the photo issue fixed on 2026-03-15 — the handler stored metadata but never downloaded the actual file.

A user needed to share school finance committee meeting papers (PDFs) for the agent to review and prepare questions, but the agent could not read them.

## Solution

### Code Changes

**`src/channels/telegram.ts`**
- Replaced the one-line `message:document` placeholder handler with a full async handler that:
  1. Gets the file info via `ctx.api.getFile()`
  2. Downloads the binary data using the existing `downloadTelegramFile()` helper
  3. Saves to `{groupDir}/documents/tg-{messageId}-{filename}`
  4. Passes `[Document: /workspace/group/documents/tg-{id}-{name}]` to `onMessage`
  5. Falls back to the original placeholder on download failure

**`container/Dockerfile`**
- Added `poppler-utils` package so the agent container has `pdftotext` available for extracting text from PDFs

**`src/channels/telegram.test.ts`**
- Added test for successful document download (verifies container path in message content)
- Added test for download failure fallback (verifies placeholder with filename)
- Added test for missing filename fallback (verifies "file" default)

### Deployment

Both Docker images were rebuilt:
- `nanoclaw:latest` (orchestrator) — picks up the updated Telegram handler
- `nanoclaw-agent:latest` (agent container) — includes `poppler-utils` for PDF text extraction

## How It Works

1. User sends a PDF in Telegram
2. Orchestrator downloads it and saves to the group's `documents/` folder on the host
3. The file is bind-mounted into the agent container at `/workspace/group/documents/`
4. The agent can use `pdftotext /workspace/group/documents/tg-42-report.pdf -` to extract text and analyze the document
