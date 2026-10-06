-- Atlas Notes private storage.
-- Files are stored under workspaces/<workspace_id>/...

insert into storage.buckets (id, name, public)
values
  ('atlas-assets', 'atlas-assets', false),
  ('atlas-pdfs', 'atlas-pdfs', false),
  ('atlas-exports', 'atlas-exports', false)
on conflict (id) do update set public = excluded.public;

create policy "atlas storage read"
on storage.objects for select
to authenticated
using (
  bucket_id in ('atlas-assets', 'atlas-pdfs', 'atlas-exports')
  and public.can_access_workspace(
    split_part(name, '/', 2)::uuid
  )
);

create policy "atlas storage upload"
on storage.objects for insert
to authenticated
with check (
  bucket_id in ('atlas-assets', 'atlas-pdfs', 'atlas-exports')
  and public.can_edit_workspace(
    split_part(name, '/', 2)::uuid
  )
);

create policy "atlas storage update"
on storage.objects for update
to authenticated
using (
  bucket_id in ('atlas-assets', 'atlas-pdfs', 'atlas-exports')
  and public.can_edit_workspace(
    split_part(name, '/', 2)::uuid
  )
)
with check (
  bucket_id in ('atlas-assets', 'atlas-pdfs', 'atlas-exports')
  and public.can_edit_workspace(
    split_part(name, '/', 2)::uuid
  )
);

create policy "atlas storage delete"
on storage.objects for delete
to authenticated
using (
  bucket_id in ('atlas-assets', 'atlas-pdfs', 'atlas-exports')
  and public.can_edit_workspace(
    split_part(name, '/', 2)::uuid
  )
);
