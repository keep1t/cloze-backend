-- Runtime-managed product settings and private entitlement state.
create schema if not exists private;

revoke all on schema private from public, anon, authenticated, service_role;
grant usage on schema private to service_role;

create table private.product_config (
  key text primary key check (length(key) > 0),
  value jsonb not null,
  updated_at timestamptz not null default now()
);

create table public.user_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  preferences jsonb not null default '{}'::jsonb,
  preferences_schema_version integer not null default 1,
  privacy jsonb not null default '{}'::jsonb,
  privacy_schema_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_settings_preferences_object check (jsonb_typeof(preferences) = 'object'),
  constraint user_settings_privacy_object check (jsonb_typeof(privacy) = 'object'),
  constraint user_settings_preferences_schema_version_positive check (preferences_schema_version > 0),
  constraint user_settings_privacy_schema_version_positive check (privacy_schema_version > 0)
);

create table private.user_entitlements (
  user_id uuid not null references auth.users (id) on delete cascade,
  entitlement_key text not null check (length(entitlement_key) > 0),
  status text not null check (status in ('active', 'inactive', 'revoked')),
  valid_from timestamptz not null,
  valid_until timestamptz,
  source_reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, entitlement_key, valid_from),
  constraint user_entitlements_valid_window check (valid_until is null or valid_until > valid_from)
);

alter table private.product_config enable row level security;
alter table private.product_config force row level security;
alter table public.user_settings enable row level security;
alter table public.user_settings force row level security;
alter table private.user_entitlements enable row level security;
alter table private.user_entitlements force row level security;

revoke all on table private.product_config, private.user_entitlements from public, anon, authenticated, service_role;
revoke all on table public.user_settings from public, anon, authenticated, service_role;
grant select, insert, update, delete on table public.user_settings to authenticated;
grant select on table private.product_config to service_role;
grant select, insert, update, delete on table private.user_entitlements to service_role;

create policy user_settings_select_own
  on public.user_settings for select to authenticated
  using ((select auth.uid()) = user_id);
create policy user_settings_insert_own
  on public.user_settings for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy user_settings_update_own
  on public.user_settings for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy user_settings_delete_own
  on public.user_settings for delete to authenticated
  using ((select auth.uid()) = user_id);

create function private.configuration_error(p_key text)
returns void
language plpgsql
immutable
security invoker
set search_path = ''
as $$
begin
  raise exception using
    errcode = 'P0001',
    message = 'CONFIGURATION_ERROR: ' || coalesce(p_key, '<null>');
end;
$$;

create function private.get_config_integer(p_key text, p_min bigint, p_max bigint)
returns bigint
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_value jsonb;
  v_number numeric;
begin
  select config.value into v_value
  from private.product_config as config
  where config.key = p_key;

  if not found or p_min is null or p_max is null or p_min > p_max
     or jsonb_typeof(v_value) is distinct from 'number' then
    perform private.configuration_error(p_key);
  end if;

  v_number := (v_value #>> '{}')::numeric;
  if trunc(v_number) <> v_number or v_number < p_min::numeric or v_number > p_max::numeric then
    perform private.configuration_error(p_key);
  end if;

  return v_number::bigint;
end;
$$;

create function private.get_config_text(p_key text)
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_value jsonb;
begin
  select config.value into v_value
  from private.product_config as config
  where config.key = p_key;

  if not found or jsonb_typeof(v_value) is distinct from 'string' then
    perform private.configuration_error(p_key);
  end if;

  return v_value #>> '{}';
end;
$$;

create function private.get_config_text_array(p_key text)
returns text[]
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_value jsonb;
  v_result text[];
begin
  select config.value into v_value
  from private.product_config as config
  where config.key = p_key;

  if not found or jsonb_typeof(v_value) is distinct from 'array'
     or exists (
       select 1
       from jsonb_array_elements(case when jsonb_typeof(v_value) = 'array' then v_value else '[]'::jsonb end) as element(value)
       where jsonb_typeof(element.value) is distinct from 'string'
     ) then
    perform private.configuration_error(p_key);
  end if;

  select coalesce(array_agg(element.value #>> '{}' order by element.ordinality), array[]::text[])
  into v_result
  from jsonb_array_elements(v_value) with ordinality as element(value, ordinality);
  return v_result;
end;
$$;

create function private.has_active_entitlement(p_user_id uuid, p_entitlement_key text, p_at timestamptz)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select exists (
    select 1
    from private.user_entitlements as entitlement
    where entitlement.user_id = p_user_id
      and entitlement.entitlement_key = p_entitlement_key
      and entitlement.status = 'active'
      and entitlement.valid_from <= p_at
      and (entitlement.valid_until is null or p_at < entitlement.valid_until)
  );
$$;

create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.user_settings (user_id, preferences, privacy)
  values (new.id, '{}'::jsonb, '{}'::jsonb);
  return new;
end;
$$;

create function private.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger product_config_set_updated_at
  before update on private.product_config
  for each row execute function private.set_updated_at();

create trigger user_settings_set_updated_at
  before update on public.user_settings
  for each row execute function private.set_updated_at();

create trigger user_entitlements_set_updated_at
  before update on private.user_entitlements
  for each row execute function private.set_updated_at();

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

revoke all on function private.configuration_error(text) from public, anon, authenticated, service_role;
revoke all on function private.get_config_integer(text, bigint, bigint) from public, anon, authenticated, service_role;
revoke all on function private.get_config_text(text) from public, anon, authenticated, service_role;
revoke all on function private.get_config_text_array(text) from public, anon, authenticated, service_role;
revoke all on function private.has_active_entitlement(uuid, text, timestamptz) from public, anon, authenticated, service_role;
revoke all on function private.handle_new_user() from public, anon, authenticated, service_role;
revoke all on function private.set_updated_at() from public, anon, authenticated, service_role;
grant execute on function private.get_config_integer(text, bigint, bigint) to service_role;
grant execute on function private.get_config_text(text) to service_role;
grant execute on function private.get_config_text_array(text) to service_role;
grant execute on function private.has_active_entitlement(uuid, text, timestamptz) to service_role;
grant execute on function private.configuration_error(text) to service_role;
