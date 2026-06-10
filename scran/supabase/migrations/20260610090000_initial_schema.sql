-- ============================================================
-- Scran initial schema (v1). Mirrors the SwiftData models.
-- RLS: auth.uid() = user_id on every table.
-- ============================================================

create table if not exists public.profiles (
    id          uuid primary key references auth.users(id) on delete cascade,
    display_name text,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

create table if not exists public.plans (
    id                uuid primary key default gen_random_uuid(),
    user_id           uuid not null references auth.users(id) on delete cascade,
    height_cm         double precision not null,
    weight_kg         double precision not null,
    date_of_birth     date not null,
    biological_sex    text not null check (biological_sex in ('male','female')),
    activity_level    text not null check (activity_level in ('sedentary','light','moderate','active')),
    weekly_workouts   integer not null default 0,
    goal              text not null check (goal in ('lose','maintain','gain')),
    weekly_rate_kg    double precision not null default 0,
    bmr               double precision not null,
    tdee              double precision not null,
    daily_target_kcal double precision not null,
    protein_target_g  double precision not null,
    carbs_target_g    double precision not null,
    fat_target_g      double precision not null,
    sat_fat_limit_g   double precision not null,
    fibre_target_g    double precision not null,
    explanation       text,
    explanation_version integer not null default 0,
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now(),
    deleted_at        timestamptz
);
create index if not exists plans_user_idx on public.plans(user_id);

create table if not exists public.food_entries (
    id               uuid primary key default gen_random_uuid(),
    user_id          uuid not null references auth.users(id) on delete cascade,
    logged_at        timestamptz not null,
    name             text not null,
    brand            text,
    source           text not null check (source in ('label','barcode','estimate','manual','saved')),
    confidence       double precision,
    barcode          text,
    per100g          jsonb not null,
    serving_size_g   double precision not null,
    quantity         double precision not null default 1,
    photo_remote_path text,
    clarifications   jsonb not null default '[]'::jsonb,
    created_at       timestamptz not null default now(),
    updated_at       timestamptz not null default now(),
    deleted_at       timestamptz
);
create index if not exists food_entries_user_logged_idx on public.food_entries(user_id, logged_at desc);

create table if not exists public.saved_meals (
    id              uuid primary key default gen_random_uuid(),
    user_id         uuid not null references auth.users(id) on delete cascade,
    name            text not null,
    entries         jsonb not null default '[]'::jsonb,
    times_logged    integer not null default 0,
    last_logged_at  timestamptz,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),
    deleted_at      timestamptz
);
create index if not exists saved_meals_user_idx on public.saved_meals(user_id);

create table if not exists public.weight_entries (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null references auth.users(id) on delete cascade,
    date        date not null,
    weight_kg   double precision not null,
    created_at  timestamptz not null default now(),
    deleted_at  timestamptz
);
create index if not exists weight_entries_user_idx on public.weight_entries(user_id, date desc);

create table if not exists public.ai_scan_events (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid not null references auth.users(id) on delete cascade,
    kind        text not null check (kind in ('label','plate')),
    created_at  timestamptz not null default now()
);
create index if not exists ai_scan_events_user_day_idx on public.ai_scan_events(user_id, created_at);

-- RLS
alter table public.profiles       enable row level security;
alter table public.plans          enable row level security;
alter table public.food_entries   enable row level security;
alter table public.saved_meals    enable row level security;
alter table public.weight_entries enable row level security;
alter table public.ai_scan_events enable row level security;

create policy "profiles_select_own" on public.profiles for select using (auth.uid() = id);
create policy "profiles_insert_own" on public.profiles for insert with check (auth.uid() = id);
create policy "profiles_update_own" on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);
create policy "profiles_delete_own" on public.profiles for delete using (auth.uid() = id);

create policy "plans_all_own" on public.plans for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "food_entries_all_own" on public.food_entries for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "saved_meals_all_own" on public.saved_meals for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "weight_entries_all_own" on public.weight_entries for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "ai_scan_events_select_own" on public.ai_scan_events for select using (auth.uid() = user_id);

-- updated_at trigger (search_path hardened)
create or replace function public.set_updated_at()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger profiles_set_updated_at     before update on public.profiles     for each row execute function public.set_updated_at();
create trigger plans_set_updated_at        before update on public.plans        for each row execute function public.set_updated_at();
create trigger food_entries_set_updated_at before update on public.food_entries for each row execute function public.set_updated_at();
create trigger saved_meals_set_updated_at  before update on public.saved_meals  for each row execute function public.set_updated_at();
