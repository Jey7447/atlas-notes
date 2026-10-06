-- Atlas Notes 2.0 ownership and collaborator security.
-- AI-free by design.

create table if not exists public.workspace_members (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('editor','commenter','viewer')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);

create index if not exists workspace_members_user_idx
  on public.workspace_members(user_id);

alter table public.workspace_members enable row level security;

create or replace function public.can_access_workspace(
  target_workspace uuid,
  allowed_roles text[] default array['owner','editor','commenter','viewer']::text[]
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.workspaces w
    where w.id = target_workspace
      and w.owner_id = auth.uid()
  )
  or exists (
    select 1
    from public.workspace_members wm
    where wm.workspace_id = target_workspace
      and wm.user_id = auth.uid()
      and wm.role = any(allowed_roles)
  );
$$;

create or replace function public.can_edit_workspace(target_workspace uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_access_workspace(
    target_workspace,
    array['owner','editor']::text[]
  );
$$;

create or replace function public.can_comment_workspace(target_workspace uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_access_workspace(
    target_workspace,
    array['owner','editor','commenter']::text[]
  );
$$;

create policy "profiles own row"
on public.profiles for all
using (id = auth.uid())
with check (id = auth.uid());

create policy "workspace members visible to participants"
on public.workspace_members for select
using (public.can_access_workspace(workspace_id));

create policy "workspace owner manages members"
on public.workspace_members for all
using (
  exists (
    select 1 from public.workspaces w
    where w.id = workspace_members.workspace_id
      and w.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1 from public.workspaces w
    where w.id = workspace_members.workspace_id
      and w.owner_id = auth.uid()
  )
);

create policy "workspace participants read"
on public.workspaces for select
using (public.can_access_workspace(id));

create policy "workspace owner creates"
on public.workspaces for insert
with check (owner_id = auth.uid());

create policy "workspace owner updates"
on public.workspaces for update
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

create policy "workspace owner deletes"
on public.workspaces for delete
using (owner_id = auth.uid());

create policy "folders participants read"
on public.folders for select
using (public.can_access_workspace(workspace_id));

create policy "folders editors write"
on public.folders for all
using (public.can_edit_workspace(workspace_id))
with check (public.can_edit_workspace(workspace_id));

create policy "notebooks participants read"
on public.notebooks for select
using (public.can_access_workspace(workspace_id));

create policy "notebooks editors write"
on public.notebooks for all
using (public.can_edit_workspace(workspace_id))
with check (public.can_edit_workspace(workspace_id));

create policy "notes participants read"
on public.notes for select
using (
  exists (
    select 1 from public.notebooks n
    where n.id = notes.notebook_id
      and public.can_access_workspace(n.workspace_id)
  )
);

create policy "notes editors write"
on public.notes for all
using (
  exists (
    select 1 from public.notebooks n
    where n.id = notes.notebook_id
      and public.can_edit_workspace(n.workspace_id)
  )
)
with check (
  exists (
    select 1 from public.notebooks n
    where n.id = notes.notebook_id
      and public.can_edit_workspace(n.workspace_id)
  )
);

create policy "pages participants read"
on public.pages for select
using (
  exists (
    select 1
    from public.notes n
    join public.notebooks nb on nb.id = n.notebook_id
    where n.id = pages.note_id
      and public.can_access_workspace(nb.workspace_id)
  )
);

create policy "pages editors write"
on public.pages for all
using (
  exists (
    select 1
    from public.notes n
    join public.notebooks nb on nb.id = n.notebook_id
    where n.id = pages.note_id
      and public.can_edit_workspace(nb.workspace_id)
  )
)
with check (
  exists (
    select 1
    from public.notes n
    join public.notebooks nb on nb.id = n.notebook_id
    where n.id = pages.note_id
      and public.can_edit_workspace(nb.workspace_id)
  )
);

create policy "assets participants read"
on public.assets for select
using (public.can_access_workspace(workspace_id));

create policy "assets editors write"
on public.assets for all
using (public.can_edit_workspace(workspace_id))
with check (
  owner_id = auth.uid()
  and public.can_edit_workspace(workspace_id)
);

create policy "tags participants read"
on public.tags for select
using (public.can_access_workspace(workspace_id));

create policy "tags editors write"
on public.tags for all
using (public.can_edit_workspace(workspace_id))
with check (public.can_edit_workspace(workspace_id));

create policy "note tags participants read"
on public.note_tags for select
using (
  exists (
    select 1
    from public.notes n
    join public.notebooks nb on nb.id = n.notebook_id
    where n.id = note_tags.note_id
      and public.can_access_workspace(nb.workspace_id)
  )
);

create policy "note tags editors write"
on public.note_tags for all
using (
  exists (
    select 1
    from public.notes n
    join public.notebooks nb on nb.id = n.notebook_id
    where n.id = note_tags.note_id
      and public.can_edit_workspace(nb.workspace_id)
  )
)
with check (
  exists (
    select 1
    from public.notes n
    join public.notebooks nb on nb.id = n.notebook_id
    where n.id = note_tags.note_id
      and public.can_edit_workspace(nb.workspace_id)
  )
);

create policy "note links participants read"
on public.note_links for select
using (
  exists (
    select 1
    from public.notes n
    join public.notebooks nb on nb.id = n.notebook_id
    where n.id = note_links.source_note_id
      and public.can_access_workspace(nb.workspace_id)
  )
);

create policy "note links editors write"
on public.note_links for all
using (
  exists (
    select 1
    from public.notes n
    join public.notebooks nb on nb.id = n.notebook_id
    where n.id = note_links.source_note_id
      and public.can_edit_workspace(nb.workspace_id)
  )
)
with check (
  exists (
    select 1
    from public.notes n
    join public.notebooks nb on nb.id = n.notebook_id
    where n.id = note_links.source_note_id
      and public.can_edit_workspace(nb.workspace_id)
  )
);

create policy "revisions participants read"
on public.revisions for select
using (
  exists (
    select 1
    from public.notes n
    join public.notebooks nb on nb.id = n.notebook_id
    where n.id = revisions.note_id
      and public.can_access_workspace(nb.workspace_id)
  )
);

create policy "revisions editors write"
on public.revisions for all
using (
  exists (
    select 1
    from public.notes n
    join public.notebooks nb on nb.id = n.notebook_id
    where n.id = revisions.note_id
      and public.can_edit_workspace(nb.workspace_id)
  )
)
with check (
  created_by = auth.uid()
  and exists (
    select 1
    from public.notes n
    join public.notebooks nb on nb.id = n.notebook_id
    where n.id = revisions.note_id
      and public.can_edit_workspace(nb.workspace_id)
  )
);

create policy "sync events participants read"
on public.sync_events for select
using (public.can_access_workspace(workspace_id));

create policy "sync events editors write"
on public.sync_events for insert
with check (
  created_by = auth.uid()
  and public.can_edit_workspace(workspace_id)
);

grant execute on function public.can_access_workspace(uuid, text[]) to authenticated;
grant execute on function public.can_edit_workspace(uuid) to authenticated;
grant execute on function public.can_comment_workspace(uuid) to authenticated;
