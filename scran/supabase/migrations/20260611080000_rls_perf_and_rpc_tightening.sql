-- Advisor cleanup (2026-06-11):
-- 1. auth_rls_initplan: wrap auth.uid() in a scalar sub-select so Postgres
--    evaluates it once per query instead of once per row.
-- 2. ai_scans_used_today(): anonymous-auth users run as the `authenticated`
--    role, so the `anon` grant was never needed for the app — revoke it.

alter policy "profiles_select_own" on public.profiles
  using ((select auth.uid()) = id);
alter policy "profiles_insert_own" on public.profiles
  with check ((select auth.uid()) = id);
alter policy "profiles_update_own" on public.profiles
  using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
alter policy "profiles_delete_own" on public.profiles
  using ((select auth.uid()) = id);

alter policy "plans_all_own" on public.plans
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
alter policy "food_entries_all_own" on public.food_entries
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
alter policy "saved_meals_all_own" on public.saved_meals
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
alter policy "weight_entries_all_own" on public.weight_entries
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
alter policy "ai_scan_events_select_own" on public.ai_scan_events
  using ((select auth.uid()) = user_id);

alter policy "food_photos_select_own" on storage.objects
  using (bucket_id = 'food-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
alter policy "food_photos_insert_own" on storage.objects
  with check (bucket_id = 'food-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
alter policy "food_photos_update_own" on storage.objects
  using (bucket_id = 'food-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);
alter policy "food_photos_delete_own" on storage.objects
  using (bucket_id = 'food-photos' and (storage.foldername(name))[1] = (select auth.uid())::text);

revoke execute on function public.ai_scans_used_today() from anon;
