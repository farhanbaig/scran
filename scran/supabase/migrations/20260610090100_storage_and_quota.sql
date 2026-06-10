-- Private bucket for food photos: food-photos/{userId}/{entryId}.jpg
insert into storage.buckets (id, name, public)
values ('food-photos', 'food-photos', false)
on conflict (id) do nothing;

create policy "food_photos_select_own"
  on storage.objects for select
  using (bucket_id = 'food-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "food_photos_insert_own"
  on storage.objects for insert
  with check (bucket_id = 'food-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "food_photos_update_own"
  on storage.objects for update
  using (bucket_id = 'food-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "food_photos_delete_own"
  on storage.objects for delete
  using (bucket_id = 'food-photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- Count AI scans used today (UTC) for the calling user only.
create or replace function public.ai_scans_used_today()
returns integer language sql security definer set search_path = public as $$
  select count(*)::int
  from public.ai_scan_events
  where user_id = auth.uid()
    and created_at >= date_trunc('day', now() at time zone 'utc');
$$;

revoke all on function public.ai_scans_used_today() from public;
grant execute on function public.ai_scans_used_today() to authenticated, anon;
