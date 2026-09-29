# PDF Summary + RAG Chat App — Requirements

**App identifier:** `com.nihesh.pdfsummary`

---

## 1. Problem & Value

A user uploads a PDF and gets back two things: a clean sectioned summary they can scan in under a minute, and a chat interface that lets them ask questions grounded in that PDF or across their full library. Each user has their own private collection.

The interface aims for a calm, text-first feel: generous whitespace, restrained accents in Oxford Blue (`#0A2463`) and Brand Green (`#4FA463`), real typographic hierarchy.

## 2. Users & Auth

- **One user type.** Authenticated end-users; each user sees only their own documents.
- **Sign-in methods:** email + password (bcrypt) **and** Google OAuth.
- **Session model:** short-lived access JWT (15 min) + httpOnly rotating refresh token (30 days). Logout revokes the refresh token.
- **Password reset:** email link with a single-use, time-limited (15 min) signed token.
- **Failed-login lockout:** 5 consecutive failures → 15 minute lockout per account.
- **Email verification:** required for email+password signups before first upload.
- **Account linking (OAuth ↔ email-password):** identity is the verified email address.
  - If a Google sign-in returns an email already registered with a password, the user must sign in with their password once to confirm linking. **Never auto-link** without proving ownership.
  - If a Google-first user later sets a password, both methods become valid for the same account.
  - If Google returns `email_verified=false`, treat as a fresh signup (no auto-link).
- **Account deletion:** user can delete their account from settings. Deletion cascades to all docs, embeddings, S3 objects under `users/{user_id}/`, all chat threads, and the user record (hard delete after a 7-day grace where the account is disabled but data is recoverable on request).
- **No admin role in v1.** Operational endpoints (health, metrics) are network-restricted, not auth-gated.
- **No "persona" personalization.** "User persona" was clarified to mean per-user account isolation, not inferred preferences.

## 3. Core User Flows

1. **Sign up / sign in** — email+password or Google.
2. **Upload a PDF** — pick a file, see honest progress, land on the doc detail screen when ready.
3. **Read the summary** — sectioned summary with a TL;DR at the top.
4. **View the original PDF** — inline viewer in the same screen (tab/pane).
5. **Chat with the doc** — RAG chat grounded by default in the current PDF; toggle to chat across the user's whole library.
6. **Browse library** — list of uploaded PDFs.
7. **Delete a doc or account** — destructive actions confirmed once, then cascaded.

## 4. Functional Requirements

### 4.1 Upload & ingestion

- Accept PDF only.
- **Hard caps (enforced server-side):** **50 MB** per file, **500 pages** per document. Reject above either with a clear user-facing message and HTTP 413/422. Caps can be raised later; v1 prioritizes predictable cost and time.
- **No minimum page count.**
- **File validity:** validate magic bytes (`%PDF-` header) at the FastAPI layer before writing to S3. Extension and Content-Type are not trusted.
- **Storage:** S3 bucket `pdf-summary-iiith`, key `users/{user_id}/{doc_id}.pdf`.
- **Ingestion is asynchronous.** The upload request returns quickly with a `doc_id` and an initial status. A background worker (FastAPI BackgroundTasks for v1; swap to a queue if needed later) performs:
  1. text extraction (PyMuPDF preferred for heading/font signals)
  2. section detection (headings if available; otherwise page-based fallback chunks)
  3. embedding generation (`text-embedding-3-small`, 1536 dims)
  4. summary generation (map-reduce for long docs)
- **Document state machine:** `uploading → extracting → embedding → summarizing → ready | failed`. The Flutter client polls `GET /documents/{id}` (every 2s while not terminal) to drive a real progress indicator. No fake progress.
- **Cancellation / mid-processing delete:** delete sets a tombstone on the doc row. The worker checks the tombstone between steps and aborts; partial writes are cleaned up.
- **Failure modes (each surfaces a specific user-facing error):**
  - Image-only / scanned PDF (zero or near-zero extractable text): reject with "This PDF appears to be a scanned image. Text extraction is not supported yet." Do not persist.
  - OpenAI rate-limit / 5xx: per-chunk idempotent retry with exponential backoff (max 3 retries). Terminal failure → state `failed`, user sees a "Retry" affordance.
  - OpenAI key invalid / quota exhausted: distinct user-visible error.
- **Web upload note:** on Flutter Web, file_picker returns bytes (not a path). The backend accepts both bytes-multipart and file-multipart. CORS on the FastAPI host must permit the Flutter Web origin.

### 4.2 Summary

- **Shape:** sectioned. One short TL;DR (3–5 sentences) at top + per-section summaries below.
- **Sections:** detected from PDF headings (font-size signals + structural hints) when available; otherwise fall back to **5-page chunks** as section boundaries.
- **Display:** flat scrollable layout for v1. Each section is a heading + 2–4 sentence summary. (Expand/collapse is a v1.1 polish item — defer the stateful widget.)
- **Caching:** summary generated once at ingestion and cached in DB.
- **Regeneration:** explicit user action via "Regenerate summary" in doc menu. Replaces the cached summary; previous summary is not retained.
- **Processing budget:** per-doc summarization has a wall-clock cap (e.g., 5 minutes) and a token cap. Above either, ingestion fails cleanly rather than running indefinitely.

### 4.3 RAG chat

- **Two modes**, toggleable via a segmented control at the top of the chat tab:
  - **This document** (default) — retrieval scoped to the current PDF.
  - **My library** — retrieval across all of the user's PDFs.
- **Switching modes starts a new thread.** Prior threads are preserved and accessible from a thread list (per-user-per-doc for doc mode; per-user for library mode).
- **Empty library in library-wide mode:** disable the toggle with a tooltip "Upload at least one PDF to chat across your library." No fallback to ungrounded LLM.
- **Citations:** every retrieval-grounded response shows source citations.
  - **Per-doc mode:** chip = section name + page number; click scrolls the adjacent inline PDF viewer to that page.
  - **Library mode:** chip = doc title (primary) + section/page; click navigates to that doc's detail screen with the page pre-selected.
  - If retrieval returns nothing useful, the assistant says so explicitly rather than answering uncited.
- **Retrieval limits (cost + quality):** top-k = 8 in per-doc mode; top-k = 12 in library mode with per-document cap of 4 chunks. Library mode applies an MMR re-rank to reduce near-duplicates.
- **Chat history persistence:** per-(user, doc) thread for per-doc mode; per-user thread for library mode. Threads are deletable individually and cascade-deleted with their doc/account.

### 4.4 Library management

- **List view** = home after login. Default sort: upload date descending. Each row: title, upload date, page count, status badge, delete affordance.
- **Empty state** for first-run: a calm, copy-driven prompt ("Upload your first PDF") with a single primary action. Not an icon-in-circle illustration.
- **Status while processing:** row is visible immediately on upload with state badge (`Extracting…`, `Summarizing…`, etc.); user can open it to see progress.
- **Open** → doc detail with three tabs (Summary, PDF, Chat). Mobile layout: bottom tab bar over a single content area; the chat tab hides the tab bar when the keyboard is up; the PDF tab uses a full-bleed viewer.
- **Delete UX:** confirmation dialog with explicit destructive button. Delete is irreversible.
- **Delete cascade (atomic from the user's POV):**
  1. set `documents.status = 'deleting'`, immediately filter from list/chat endpoints
  2. delete S3 object (idempotent)
  3. delete embeddings + chat threads + doc row in a single DB transaction
  4. a periodic reaper retries any rows stuck in `'deleting'` (S3 transient failure recovery)

### 4.5 Per-user isolation

- Every read/write path filters by `user_id` derived from the auth context, not from the request body. No endpoint accepts a `user_id` parameter.
- S3 keys are prefixed by user id (`users/{user_id}/...`).
- Integration tests assert cross-user isolation across all endpoints before each release.

## 5. Non-Functional Requirements

- **Privacy:** a user must never see another user's documents, summaries, embeddings, or chats.
- **Transport:** HTTPS required for all production traffic. Flutter clients enforce certificate validation; no `allowBadCertificates` in release builds. Local dev over HTTP is gated by an explicit env flag.
- **Cost-awareness:** map-reduce summarization for long docs; per-turn retrieval caps; per-doc processing budget (wall-clock + tokens). See 4.1 and 4.3.
- **Error states (must each have a defined screen):** upload network failure, S3 write failure, scanned-PDF rejection, summarization failure, chat retrieval failure, chat LLM failure, empty library (first-run), library list load failure, OAuth callback failure.
- **Visual quality bar:** UI must not look AI-generic. See Section 12 for operationalized rules.
- **Theming:** Oxford Blue `#0A2463` (primary), Brand Green `#4FA463` (accent). Neutral background, off-white or near-black text — not the brand colors as backgrounds.

## 6. Platforms & Stack (decided)

- **Frontend:** Flutter, single Dart codebase. Targets in priority order: **Android, iOS, Web**. Mac available for iOS builds.
- **Backend:** FastAPI (Python).
- **Storage:** S3, bucket `pdf-summary-iiith`. Per-user prefixing.
- **Database:** **Postgres + pgvector** (≥ 0.7 for HNSW), **local-only for dev**. Production is the user's responsibility.
  - Embedding dim: **1536** (matches `text-embedding-3-small`).
  - Index: **HNSW** on the embeddings table.
  - Migrations via Alembic, including `CREATE EXTENSION IF NOT EXISTS vector` as the first migration.
  - Application connects with a least-privilege Postgres role (CRUD on app tables only).
- **LLM provider:** OpenAI (`gpt-4o-mini` for summary + chat, `text-embedding-3-small` for embeddings). Key supplied by the user.
- **AWS IAM scope:** the access key used by the backend must be scoped to `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` on `arn:aws:s3:::pdf-summary-iiith/*` only. Long-lived static keys are acceptable for v1 but must be rotated on a schedule the user owns.
- **OpenAI key hygiene:** project-scoped key with a hard monthly spend limit set in the OpenAI dashboard. Backend logs never include the key (no DEBUG-level dump of headers).
- **PDF viewer (per platform):** Syncfusion Flutter PDF Viewer or `pdfrx` on mobile + Web (whichever ships consistent gestures). Confirmed during implementation.
- **Repo layout:**
  - `app/` — Flutter app
  - `backend/` — FastAPI service
  - `backend/.env` — secrets (gitignored)
  - `docs/` — brainstorm + plan docs
- `.gitignore` at repo root excluding Claude artifacts, `.env`, build outputs, and venvs. **Nothing is pushed to git from this session** — no `git init`, no commits, no remote operations. The user owns repo creation and pushes.

## 7. Out of Scope (explicit non-goals for v1)

- Inferred user persona / personalization of summaries or chat.
- Sharing PDFs between users, teams, or workspaces.
- Editing or annotating the PDF.
- Non-PDF formats (Word, EPUB, HTML, scanned-image-only PDFs).
- OCR for scanned PDFs (rejected with a clear message; planned as a later add).
- Public links or unauthenticated views.
- Full-text search inside the PDF viewer.
- Annotations / highlights / notes on the PDF.
- Push notifications / mobile re-engagement.
- Billing or paid tiers.

## 8. Success Criteria

Each of these must be verifiable, not aspirational.

- **A1 — Onboarding:** a new user signs up, uploads a representative real PDF, and reaches a readable sectioned summary unaided. Median time-to-first-summary < 60s for a 30-page PDF.
- **A2 — Citation correctness:** on a fixed eval set of 10 PDFs and 30 questions, ≥ 80% of chat answers cite a section/page where the answer is actually supported by the source text.
- **A3 — Delete is total:** deleting a PDF removes it from S3, DB rows, embeddings, and chat threads — verified by a test that lists every store and asserts zero residual rows for the deleted `doc_id`.
- **A4 — Cross-user isolation:** automated test with two concurrent accounts confirms zero cross-user leakage across every read endpoint and every storage system.
- **A5 — Visual quality (rubric, not vibes):** the doc detail screen passes a 5-point rubric: typography hierarchy, contrast (WCAG AA), restrained palette use, no AI-cliché patterns (see §12), one clear primary action per screen.

## 9. Open Questions for Planning

These are technical questions for `/ce:plan` to resolve, not product decisions:

- Embedding chunk size and overlap (e.g., 400 tokens / 80 overlap is a sensible starting point).
- Heading-detection algorithm specifics (font-size thresholds, TOC parsing fallback).
- BackgroundTasks vs. a real queue (RQ / Celery / arq) — depends on whether v1 needs survival across restarts.
- Whether to use SSE instead of polling for the document state machine.
- PDF viewer package final pick after a quick spike across the three platforms.

## 10. Decisions Log

| Decision | Choice |
|---|---|
| LLM provider | OpenAI (`gpt-4o-mini`, `text-embedding-3-small`) |
| Embedding dim | 1536 |
| DB | Postgres + pgvector ≥ 0.7, HNSW index |
| Persona meaning | Per-user account isolation only |
| Auth | Email+password **and** Google OAuth, with email-verified linking |
| Session | Short JWT + rotating refresh; 5-fail lockout |
| Summary shape | Sectioned + TL;DR, flat scroll for v1 |
| Flutter targets | Android + iOS primary, Web secondary |
| Chat scope | Per-doc and library-wide; toggle starts a new thread |
| PDF viewing | Inline viewer, three-tab doc detail |
| Upload caps | 50 MB / 500 pages hard caps |
| Ingestion | Async background worker with state-machine polling |
| Repo layout | `app/` (Flutter), `backend/` (FastAPI) |
| Production deployment | User-owned (out of v1 scope to provision) |

## 11. Security Considerations

Top threats and the v1 mitigation for each:

- **IDOR (Insecure Direct Object Reference):** every DB query filters by the authenticated `user_id` server-derived from the JWT. Integration tests assert cross-user isolation. No endpoint accepts a `user_id` from the request body.
- **Account takeover via OAuth-email collision:** account linking requires re-authentication of the existing credential (see §2).
- **Prompt injection via PDF content:** treat extracted PDF text as untrusted user data. The system prompt instructs the model that retrieved chunks may contain conflicting instructions, which must be ignored. Output is rendered as plain text/markdown, never as code that touches local state.
- **PDF delivery:** PDFs are served via short-lived (≤ 15 min) S3 pre-signed URLs scoped to the exact key. The backend validates user ownership before issuing the URL.
- **Upload abuse:** 50 MB cap + magic-byte validation + per-user concurrent-ingestion cap (max 2 in-flight per user).
- **Secret hygiene:** `.env` is gitignored at repo root; no key is logged. AWS key scoped to bucket-only IAM policy; OpenAI key project-scoped with a spend cap.

## 12. Design Primitives (operationalized "minimal, not AI-flavored")

This section turns the visual quality bar into rules a developer can apply.

- **Typography:** Inter (variable). Scale: 14 / 16 / 20 / 28 / 36 px. Body weight 400, headings 600. Line-height 1.5 for body, 1.2 for headings.
- **Color:**
  - Foreground: `#111827` (near-black) on `#FAFAF7` (off-white) background.
  - Primary: Oxford Blue `#0A2463` for primary actions and links only.
  - Accent: Brand Green `#4FA463` for success states and the active indicator on the chat-mode toggle.
  - **Brand colors are never used as backgrounds.** No gradient hero blocks.
- **Spacing:** 4 / 8 / 12 / 16 / 24 / 32 / 48 px scale. Default content width caps around 720 px on web.
- **Radius:** 8 px on cards/inputs/buttons. No 16+ px pill cards.
- **Iconography:** thin (1.5 px) line icons (e.g., `lucide`). No icons inside colored circles.
- **Disallowed AI-cliché patterns:**
  - Sparkle/wand icons next to features.
  - Gradient borders on cards.
  - Rounded square "feature card" grids on empty states.
  - Floating action button for upload (use a clear top-bar action).
  - Bottom nav with 4+ labeled icons (we have one screen tier; a list/back/title bar is enough).
  - Generic "How can I help you today?" empty chat — use a concrete prompt seeded with the doc title.
- **Motion:** transitions ≤ 200 ms, easing `cubic-bezier(.2,.8,.2,1)`. No scaling/bouncing reveal animations.

