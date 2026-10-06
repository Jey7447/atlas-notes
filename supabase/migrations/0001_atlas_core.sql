-- Atlas Notes 2.0 core schema
-- AI-free by design.
-- Apply only after the dedicated Atlas Supabase project is created.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.workspaces (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null default 'My Workspace',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.folders (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  parent_id uuid references public.folders(id) on delete cascade,
  name text not null,
  position double precision not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.notebooks (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  folder_id uuid references public.folders(id) on delete set null,
  title text not null,
  color text,
  icon text,
  is_pinned boolean not null default false,
  position double precision not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.notes (
  id uuid primary key default gen_random_uuid(),
  notebook_id uuid not null references public.notebooks(id) on delete cascade,
  title text not null default 'Untitled note',
  cover_path text,
  is_pinned boolean not null default false,
  is_archived boolean not null default false,
  position double precision not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.pages (
  id uuid primary key default gen_random_uuid(),
  note_id uuid not null references public.notes(id) on delete cascade,
  page_number integer not null,
  width double precision not null default 1000,
  height double precision not null default 1400,
  background_type text not null default 'blank',
  background_config jsonb not null default '{}'::jsonb,
  content jsonb not null default '{"version":1,"objects":[]}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique(note_id, page_number)
);

create table if not exists public.assets (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  storage_path text not null,
  asset_type text not null,
  mime_type text,
  size_bytes bigint,
  checksum text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.tags (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  unique(workspace_id, name)
);

create table if not exists public.note_tags (
  note_id uuid not null references public.notes(id) on delete cascade,
  tag_id uuid not null references public.tags(id) on delete cascade,
  primary key(note_id, tag_id)
);

create table if not exists public.note_links (
  id uuid primary key default gen_random_uuid(),
  source_note_id uuid not null references public.notes(id) on delete cascade,
  target_note_id uuid not null references public.notes(id) on delete cascade,
  source_page_id uuid references public.pages(id) on delete set null,
  label text,
  created_at timestamptz not null default now()
);

create table if not exists public.revisions (
  id uuid primary key default gen_random_uuid(),
  note_id uuid not null references public.notes(id) on delete cascade,
  revision_number bigint not null,
  snapshot jsonb not null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(note_id, revision_number)
);

create table if not exists public.sync_events (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  entity_type text not null,
  entity_id uuid not null,
  operation text not null,
  payload jsonb not null default '{}'::jsonb,
  client_id text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists folders_workspace_idx on public.folders(workspace_id);
create index if not exists notebooks_workspace_idx on public.notebooks(workspace_id);
create index if not exists notes_notebook_idx on public.notes(notebook_id);
create index if not exists pages_note_idx on public.pages(note_id);
create index if not exists assets_workspace_idx on public.assets(workspace_id);
create index if not exists revisions_note_idx on public.revisions(note_id, revision_number desc);
create index if not exists sync_events_workspace_idx on public.sync_events(workspace_id, created_at);

alter table public.profiles enable row level security;
alter table public.workspaces enable row level security;
alter table public.folders enable row level security;
alter table public.notebooks enable row level security;
alter table public.notes enable row level security;
alter table public.pages enable row level security;
alter table public.assets enable row level security;
alter table public.tags enable row level security;
alter table public.note_tags enable row level security;
alter table public.note_links enable row level security;
alter table public.revisions enable row level security;
alter table public.sync_events enable row level security;

-- Policies will be added in the next migration after the ownership model
-- and collaborator roles are finalized. No table is intentionally public.
