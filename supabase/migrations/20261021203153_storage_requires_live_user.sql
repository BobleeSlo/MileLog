-- Account deletion (KTD14): a receipt upload with a session issued before the
-- account was deleted must fail, so inserts also require that the user still exists.
-- Client roles can't read auth.users, hence the security-definer helper.

create or replace function public.current_user_exists()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from auth.users u where u.id = auth.uid());
$$;

revoke execute on function public.current_user_exists() from public, anon;
grant execute on function public.current_user_exists() to authenticated;

drop policy if exists "Users can insert own receipts" on storage.objects;
create policy "Users can insert own receipts" on storage.objects for insert
  with check (
    bucket_id = 'receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
    and public.current_user_exists()
  );
