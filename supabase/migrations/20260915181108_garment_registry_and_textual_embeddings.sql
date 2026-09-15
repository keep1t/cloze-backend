-- Local-first garment identity and private, model-versioned textual embeddings.
create extension if not exists vector with schema extensions;

create table public.garment_registry (
  garment_id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  status text not null default 'active' check (status in ('active', 'archived')),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint garment_registry_archive_state check (
    (status = 'active' and archived_at is null)
    or (status = 'archived' and archived_at is not null)
  )
);

create table private.garment_text_embeddings (
  garment_id uuid not null references public.garment_registry (garment_id) on delete cascade,
  embedding_model text not null check (length(embedding_model) > 0),
  embedding_revision integer not null check (embedding_revision > 0),
  attributes_schema_version integer not null check (attributes_schema_version > 0),
  attributes jsonb not null check (jsonb_typeof(attributes) = 'object'),
  embedding extensions.vector not null,
  created_at timestamptz not null default now(),
  primary key (garment_id, embedding_model, embedding_revision)
);

create index garment_registry_user_id_status_idx
  on public.garment_registry (user_id, status);

alter table public.garment_registry enable row level security;
alter table public.garment_registry force row level security;
alter table private.garment_text_embeddings enable row level security;
alter table private.garment_text_embeddings force row level security;

revoke all on table public.garment_registry from public, anon, authenticated, service_role;
revoke all on table private.garment_text_embeddings from public, anon, authenticated, service_role;
grant select, insert, update, delete on table public.garment_registry to authenticated;
grant select, insert, update, delete on table private.garment_text_embeddings to service_role;

create policy garment_registry_select_own
  on public.garment_registry for select to authenticated
  using ((select auth.uid()) = user_id);
create policy garment_registry_insert_own
  on public.garment_registry for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy garment_registry_update_own
  on public.garment_registry for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy garment_registry_delete_own
  on public.garment_registry for delete to authenticated
  using ((select auth.uid()) = user_id);

create function private.enforce_active_garment_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit bigint;
  v_entitlement_key text;
  v_active_count bigint;
begin
  if (select auth.uid()) is distinct from new.user_id then
    raise exception using errcode = '42501', message = 'GARMENT_OWNER_REQUIRED';
  end if;

  if new.status <> 'active'
     or new.archived_at is not null
     or (tg_op = 'UPDATE' and old.status = 'active' and old.user_id = new.user_id) then
    return new;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.user_id::text, 0)
  );

  v_entitlement_key := private.get_config_text('entitlements.premium.key');
  if length(trim(v_entitlement_key)) = 0 then
    perform private.configuration_error('entitlements.premium.key');
  end if;

  v_limit := private.get_config_integer('limits.free.active_garments', 1, 1000000);
  if private.has_active_entitlement(new.user_id, v_entitlement_key, now()) then
    return new;
  end if;

  select count(*) into v_active_count
  from public.garment_registry as garment
  where garment.user_id = new.user_id
    and garment.status = 'active'
    and garment.garment_id <> new.garment_id;

  if v_active_count >= v_limit then
    raise exception using
      errcode = 'P0001',
      message = 'ACTIVE_GARMENT_LIMIT_EXCEEDED';
  end if;

  return new;
end;
$$;

create trigger garment_registry_enforce_active_limit
  before insert or update on public.garment_registry
  for each row execute function private.enforce_active_garment_limit();

create trigger garment_registry_set_updated_at
  before update on public.garment_registry
  for each row execute function private.set_updated_at();

revoke all on function private.enforce_active_garment_limit() from public, anon, authenticated, service_role;
