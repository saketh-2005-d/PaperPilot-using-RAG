# PDF Summary + RAG Chat

A Flutter mobile app and FastAPI backend for uploading PDFs, generating sectioned summaries, and chatting with document content via retrieval-augmented generation.

- `app/` — Flutter (Android + iOS)
- `backend/` — FastAPI, Postgres with `pgvector`, S3, OpenAI

## Architecture

| Concern | Stack |
|---|---|
| Frontend | Flutter (Dart 3, Material 3) |
| Backend | FastAPI, SQLAlchemy 2, Pydantic v2 |
| Database | Postgres 16+ with `pgvector` |
| Object storage | AWS S3 |
| Embeddings | OpenAI `text-embedding-3-small` (1536 dims) |
| Generation | OpenAI `gpt-4o-mini` |
| Auth | JWT (access tokens), bcrypt password hashing, Google ID token verification |

## Prerequisites

- Postgres 16+ running locally with the `vector` extension available
- Python 3.11+ and [`uv`](https://docs.astral.sh/uv/)
- Flutter 3.11+
- AWS S3 bucket and an IAM user with `GetObject` / `PutObject` / `DeleteObject` on it
- OpenAI API key

## Configuration

Backend secrets live in `backend/.env`:

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | SQLAlchemy URL, e.g. `postgresql+psycopg://user@localhost:5432/pdf_summary` |
| `JWT_SECRET` | Symmetric key for signing access tokens |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `S3_BUCKET` | S3 access |
| `OPENAI_API_KEY`, `OPENAI_MODEL`, `OPENAI_EMBED_MODEL`, `EMBED_DIM` | OpenAI access |
| `GOOGLE_OAUTH_CLIENT_IDS` | Comma-separated audience values accepted by `/auth/google` |
| `MAX_UPLOAD_BYTES` | Hard cap on PDF upload size (default 50 MB) |

## Database setup

```sh
psql -h localhost -d postgres -c "CREATE DATABASE pdf_summary;"
psql -h localhost -d pdf_summary -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

Tables are created automatically on backend startup via SQLAlchemy's `create_all`.

## Running the backend

```sh
cd backend
uv sync
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Health check:

```sh
curl http://localhost:8000/health
```

## Running the Flutter app

```sh
cd app
flutter pub get
flutter run
```

`Api.baseUrl` in `app/lib/api.dart` resolves to `http://10.0.2.2:8000` on the Android emulator and `http://localhost:8000` on iOS simulator and Web. Override at app start when running on a physical device against a host machine.

## Features

- Email + password authentication with JWT-protected endpoints
- PDF upload with magic-byte validation and a 50 MB cap
- Asynchronous ingestion: extract → chunk into 5-page sections → embed → per-section Markdown summary → TL;DR
- Per-user document library with status states and cascading delete (Postgres + S3 + chat history)
- Document detail view with `Summary` and `Chat` tabs, both rendering Markdown (headings, lists, tables, code, blockquotes)
- Single-document RAG chat using pgvector cosine distance, with page-range citation chips on each assistant response
- Backend `/auth/google` endpoint that verifies Google ID tokens and links by verified email

## Google sign-in

The backend route is implemented. To enable the Flutter button:

1. In Google Cloud Console, create an Android OAuth client for package `com.nihesh.pdfsummary` with the debug SHA-1 fingerprint of your build host.
2. Create a Web OAuth client in the same project; pass its client ID to `google_sign_in` as `serverClientId`.
3. Add the Web client ID to `GOOGLE_OAUTH_CLIENT_IDS` in `backend/.env`.
4. Send the resulting ID token to `POST /auth/google`.

## API surface

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/auth/signup` | Create account, returns access token |
| `POST` | `/auth/login` | Email + password login |
| `POST` | `/auth/google` | Exchange Google ID token for access token |
| `GET` | `/documents` | List the caller's documents |
| `POST` | `/documents` | Upload a PDF (multipart) |
| `GET` | `/documents/{id}` | Full document with summary and sections |
| `GET` | `/documents/{id}/pdf-url` | Pre-signed S3 URL (15 min) |
| `DELETE` | `/documents/{id}` | Cascade delete |
| `GET` | `/chat/{doc_id}/messages` | Conversation history for a document |
| `POST` | `/chat/{doc_id}` | Ask a question; returns answer + citations |

## Project layout

| Concern | File |
|---|---|
| FastAPI app entry | `backend/app/main.py` |
| Settings | `backend/app/config.py` |
| ORM models | `backend/app/models.py` |
| Auth helpers | `backend/app/auth.py` |
| S3 wrapper | `backend/app/storage.py` |
| Ingestion pipeline | `backend/app/routes/documents.py` |
| RAG retrieval and chat | `backend/app/routes/chat.py` |
| OpenAI prompts and calls | `backend/app/llm.py` |
| Flutter theme | `app/lib/theme.dart` |
| HTTP client | `app/lib/api.dart` |
| Screens | `app/lib/screens/{login,library,doc_detail}.dart` |
