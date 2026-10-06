# Atlas Notes 2.0 Architecture

## Product boundary

Atlas Notes is a zero-AI note-taking and document workspace inspired by the non-AI capabilities of modern handwriting/PDF apps.

Explicitly excluded:
- AI chat
- AI summaries
- AI search
- AI transcription
- handwriting OCR
- LLM integrations
- AI-generated study content
- semantic/embedding search

## Platform strategy

Flutter is the primary client framework.

Target order:
1. Android phones and tablets
2. iPad/iOS
3. Windows/macOS
4. Web share/viewer experience

The client is local-first even though the product is cloud-based.

## High-level architecture

User input
→ Presentation layer
→ Domain/use-case layer
→ Repository
→ Local SQLite/Drift store
→ Sync queue
→ Supabase API / Realtime / Storage

The local database is the immediate source for UI reads and writes. Remote synchronization is asynchronous.

## Core client modules

- auth
- workspace
- notebooks
- notes
- pages
- canvas
- strokes
- objects
- pdf
- audio
- media
- templates
- tags
- search
- sharing
- collaboration
- history
- sync
- settings

## Document model

Workspace
- notebooks
- folders
- tags
- notes

Note
- metadata
- ordered pages

Page
- page properties
- ordered canvas objects
- vector strokes
- embedded document/media references

Canvas objects
- text
- image
- video
- audio
- shape
- connector
- table
- sticky note
- PDF page/document reference
- link
- sticker
- tape/reveal object

## Sync model

Every mutable local entity carries:
- stable UUID
- created_at
- updated_at
- deleted_at
- sync_status
- revision/version

Local writes are committed first.

A sync queue then uploads mutations. Remote changes are consumed through Realtime and periodic reconciliation.

Conflict strategy:
- object/page-level identity
- deterministic revision metadata
- avoid last-write-wins for rich documents where possible
- preserve conflicting revisions in history
- future collaboration layer can move toward operation-based synchronization

## Storage

Postgres:
- structured metadata
- document graph
- permissions
- revisions
- sync metadata

Supabase Storage:
- PDFs
- images
- audio
- videos
- imported/exported files
- thumbnails

## Security

- Supabase Auth
- Row Level Security on every user-owned table
- private Storage buckets
- signed URLs for private assets
- least-privilege client access
- no service-role keys in client builds

## Design principle

The app must remain useful with no network connection.

Cloud adds:
- backup
- cross-device sync
- sharing
- collaboration
- version history
- large-file storage

It must never become a dependency for basic writing.
