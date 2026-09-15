create table private.idempotency_operations (
  user_id uuid not null references auth.users (id) on delete cascade,
  action text not null check (length(trim(action)) > 0),
  idempotency_key_fingerprint bytea not null check (octet_length(idempotency_key_fingerprint) > 0),
  request_fingerprint bytea not null check (octet_length(request_fingerprint) > 0),
  attempt_id uuid not null,
  state text not null check (state in ('pending', 'completed')),
  response_status integer,
  response_body jsonb,
  expires_at timestamptz not null,
  created_at timestamptz not null,
  completed_at timestamptz,
  updated_at timestamptz not null,
  primary key (user_id, action, idempotency_key_fingerprint),
  check (
    (
      state = 'pending'
      and response_status is null
      and response_body is null
      and completed_at is null
    )
    or (
      state = 'completed'
      and response_status between 100 and 599
      and jsonb_typeof(response_body) = 'object'
      and completed_at is not null
    )
  )
);

create index idempotency_operations_expires_at_idx on private.idempotency_operations (expires_at);

create table private.api_cache_entries (
  cache_key_fingerprint bytea primary key check (octet_length(cache_key_fingerprint) > 0),
  response_body jsonb not null check (jsonb_typeof(response_body) = 'object'),
  fresh_until timestamptz not null,
  stale_until timestamptz not null check (stale_until > fresh_until),
  created_at timestamptz not null,
  updated_at timestamptz not null
);

create index api_cache_entries_stale_until_idx on private.api_cache_entries (stale_until);

create table private.api_cache_leases (
  cache_key_fingerprint bytea primary key check (octet_length(cache_key_fingerprint) > 0),
  holder_id uuid not null,
  lease_until timestamptz not null,
  created_at timestamptz not null,
  updated_at timestamptz not null
);

create index api_cache_leases_lease_until_idx on private.api_cache_leases (lease_until);

create table private.rate_limit_windows (
  user_id uuid not null references auth.users (id) on delete cascade,
  action text not null check (length(trim(action)) > 0),
  window_started_at timestamptz not null,
  window_ends_at timestamptz not null check (window_ends_at > window_started_at),
  limit_value integer not null check (limit_value > 0),
  window_seconds integer not null check (window_seconds > 0),
  request_count integer not null check (
    request_count >= 0
    and request_count <= limit_value
  ),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  primary key (user_id, action, window_started_at)
);

create index rate_limit_windows_window_ends_at_idx on private.rate_limit_windows (window_ends_at);

alter table private.idempotency_operations enable row level security;

alter table private.idempotency_operations force row level security;

alter table private.api_cache_entries enable row level security;

alter table private.api_cache_entries force row level security;

alter table private.api_cache_leases enable row level security;

alter table private.api_cache_leases force row level security;

alter table private.rate_limit_windows enable row level security;

alter table private.rate_limit_windows force row level security;

revoke all on table private.idempotency_operations,
private.api_cache_entries,
private.api_cache_leases,
private.rate_limit_windows
from
  public,
  anon,
  authenticated,
  service_role;

grant
select
,
  insert,
update,
delete on table private.idempotency_operations,
private.api_cache_entries,
private.api_cache_leases,
private.rate_limit_windows to service_role;

create function private.claim_idempotency_operation (
  p_user_id uuid,
  p_action text,
  p_idempotency_key_fingerprint bytea,
  p_request_fingerprint bytea,
  p_attempt_id uuid,
  p_now timestamptz,
  p_expires_at timestamptz
) returns table (
  decision text,
  response_status integer,
  response_body jsonb
) language plpgsql security invoker
set
  search_path = '' as $$
begin
  if p_expires_at <= p_now then raise exception using errcode = 'P0001'; end if;
  insert into private.idempotency_operations values (p_user_id,p_action,p_idempotency_key_fingerprint,p_request_fingerprint,p_attempt_id,'pending',null,null,p_expires_at,p_now,null,p_now)
  on conflict (user_id,action,idempotency_key_fingerprint) do update set request_fingerprint=excluded.request_fingerprint,attempt_id=excluded.attempt_id,state='pending',response_status=null,response_body=null,expires_at=excluded.expires_at,completed_at=null,updated_at=p_now
  where private.idempotency_operations.expires_at <= p_now
  returning 'claimed'::text,null::integer,null::jsonb into decision,response_status,response_body;
  if found then return next; return; end if;
  select case when request_fingerprint <> p_request_fingerprint then 'conflict' when state = 'completed' then 'replay' else 'in_progress' end,
    case when request_fingerprint = p_request_fingerprint and state = 'completed' then private.idempotency_operations.response_status end,
    case when request_fingerprint = p_request_fingerprint and state = 'completed' then private.idempotency_operations.response_body end
  into decision,response_status,response_body from private.idempotency_operations
  where user_id=p_user_id and action=p_action and idempotency_key_fingerprint=p_idempotency_key_fingerprint;
  return next;
end $$;

create function private.complete_idempotency_operation (
  p_user_id uuid,
  p_action text,
  p_idempotency_key_fingerprint bytea,
  p_request_fingerprint bytea,
  p_attempt_id uuid,
  p_response_status integer,
  p_response_body jsonb,
  p_now timestamptz
) returns boolean language plpgsql security invoker
set
  search_path = '' as $$
begin
  if p_response_status not between 100 and 599 or jsonb_typeof(p_response_body) <> 'object' then raise exception using errcode = 'P0001'; end if;
  update private.idempotency_operations set state='completed',response_status=p_response_status,response_body=p_response_body,completed_at=p_now,updated_at=p_now
  where user_id=p_user_id and action=p_action and idempotency_key_fingerprint=p_idempotency_key_fingerprint and request_fingerprint=p_request_fingerprint and attempt_id=p_attempt_id and state='pending' and expires_at>p_now;
  return found;
end $$;

create function private.read_api_cache (p_cache_key_fingerprint bytea, p_now timestamptz) returns table (
  cache_state text,
  response_body jsonb,
  fresh_until timestamptz,
  stale_until timestamptz
) language plpgsql security invoker
set
  search_path = '' as $$
begin
  return query select case when e.fresh_until > p_now then 'fresh' else 'stale' end,e.response_body,e.fresh_until,e.stale_until from private.api_cache_entries e where e.cache_key_fingerprint=p_cache_key_fingerprint and e.stale_until>p_now;
  if not found then return query select 'miss'::text,null::jsonb,null::timestamptz,null::timestamptz; end if;
end $$;

create function private.write_api_cache (
  p_cache_key_fingerprint bytea,
  p_response_body jsonb,
  p_now timestamptz,
  p_fresh_until timestamptz,
  p_stale_until timestamptz
) returns void language plpgsql security invoker
set
  search_path = '' as $$
begin
  if jsonb_typeof(p_response_body) <> 'object' or p_fresh_until <= p_now or p_stale_until <= p_fresh_until then raise exception using errcode = 'P0001'; end if;
  insert into private.api_cache_entries values (p_cache_key_fingerprint,p_response_body,p_fresh_until,p_stale_until,p_now,p_now)
  on conflict (cache_key_fingerprint) do update set response_body=excluded.response_body,fresh_until=excluded.fresh_until,stale_until=excluded.stale_until,updated_at=p_now;
end $$;

create function private.acquire_api_cache_lease (
  p_cache_key_fingerprint bytea,
  p_holder_id uuid,
  p_now timestamptz,
  p_lease_until timestamptz
) returns boolean language plpgsql security invoker
set
  search_path = '' as $$
begin
  if p_lease_until <= p_now then raise exception using errcode = 'P0001'; end if;
  insert into private.api_cache_leases values (p_cache_key_fingerprint,p_holder_id,p_lease_until,p_now,p_now)
  on conflict (cache_key_fingerprint) do update set holder_id=excluded.holder_id,lease_until=excluded.lease_until,updated_at=p_now
  where private.api_cache_leases.lease_until <= p_now or private.api_cache_leases.holder_id = p_holder_id;
  return found;
end $$;

create function private.release_api_cache_lease (p_cache_key_fingerprint bytea, p_holder_id uuid) returns boolean language plpgsql security invoker
set
  search_path = '' as $$
begin
  delete from private.api_cache_leases where cache_key_fingerprint=p_cache_key_fingerprint and holder_id=p_holder_id;
  return found;
end $$;

create function private.consume_rate_limit (
  p_user_id uuid,
  p_action text,
  p_limit integer,
  p_window_seconds integer,
  p_now timestamptz
) returns table (
  allowed boolean,
  remaining integer,
  reset_at timestamptz
) language plpgsql security invoker
set
  search_path = '' as $$
declare
  v_start timestamptz;
  v_end timestamptz;
  v_count integer;
  v_existing_limit integer;
  v_existing_window integer;
begin
  if p_limit <= 0 or p_window_seconds <= 0 then raise exception using errcode = 'P0001'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_user_id::text || ':' || p_action,0));
  select limit_value,window_seconds into v_existing_limit,v_existing_window from private.rate_limit_windows
  where user_id=p_user_id and action=p_action and window_started_at<=p_now and window_ends_at>p_now order by window_started_at desc limit 1;
  if found and (v_existing_limit<>p_limit or v_existing_window<>p_window_seconds) then raise exception using errcode = 'P0001'; end if;
  v_start=to_timestamp(floor(extract(epoch from p_now)/p_window_seconds)*p_window_seconds);
  v_end=v_start+make_interval(secs=>p_window_seconds);
  insert into private.rate_limit_windows values (p_user_id,p_action,v_start,v_end,p_limit,p_window_seconds,1,p_now,p_now)
  on conflict (user_id,action,window_started_at) do update set request_count=private.rate_limit_windows.request_count+1,updated_at=p_now
  where private.rate_limit_windows.request_count<private.rate_limit_windows.limit_value returning request_count into v_count;
  if not found then
    select request_count into v_count from private.rate_limit_windows where user_id=p_user_id and action=p_action and window_started_at=v_start;
    allowed=false;
  else allowed=true; end if;
  remaining=p_limit-v_count;
  reset_at=v_end;
  return next;
end $$;

create function private.purge_expired_coordination_state (p_now timestamptz, p_batch_size integer) returns table (resource text, deleted_count bigint) language plpgsql security invoker
set
  search_path = '' as $$
begin
  if p_batch_size <= 0 then raise exception using errcode = 'P0001'; end if;
  delete from private.idempotency_operations where ctid in (select ctid from private.idempotency_operations where expires_at<=p_now order by expires_at limit p_batch_size);
  get diagnostics deleted_count=row_count; resource='idempotency_operations'; return next;
  delete from private.api_cache_entries where ctid in (select ctid from private.api_cache_entries where stale_until<=p_now order by stale_until limit p_batch_size);
  get diagnostics deleted_count=row_count; resource='api_cache_entries'; return next;
  delete from private.api_cache_leases where ctid in (select ctid from private.api_cache_leases where lease_until<=p_now order by lease_until limit p_batch_size);
  get diagnostics deleted_count=row_count; resource='api_cache_leases'; return next;
  delete from private.rate_limit_windows where ctid in (select ctid from private.rate_limit_windows where window_ends_at<=p_now order by window_ends_at limit p_batch_size);
  get diagnostics deleted_count=row_count; resource='rate_limit_windows'; return next;
end $$;

revoke all on function private.claim_idempotency_operation (
  uuid,
  text,
  bytea,
  bytea,
  uuid,
  timestamptz,
  timestamptz
),
private.complete_idempotency_operation (
  uuid,
  text,
  bytea,
  bytea,
  uuid,
  integer,
  jsonb,
  timestamptz
),
private.read_api_cache (bytea, timestamptz),
private.write_api_cache (
  bytea,
  jsonb,
  timestamptz,
  timestamptz,
  timestamptz
),
private.acquire_api_cache_lease (bytea, uuid, timestamptz, timestamptz),
private.release_api_cache_lease (bytea, uuid),
private.consume_rate_limit (uuid, text, integer, integer, timestamptz),
private.purge_expired_coordination_state (timestamptz, integer)
from
  public,
  anon,
  authenticated,
  service_role;

grant
execute on function private.claim_idempotency_operation (
  uuid,
  text,
  bytea,
  bytea,
  uuid,
  timestamptz,
  timestamptz
),
private.complete_idempotency_operation (
  uuid,
  text,
  bytea,
  bytea,
  uuid,
  integer,
  jsonb,
  timestamptz
),
private.read_api_cache (bytea, timestamptz),
private.write_api_cache (
  bytea,
  jsonb,
  timestamptz,
  timestamptz,
  timestamptz
),
private.acquire_api_cache_lease (bytea, uuid, timestamptz, timestamptz),
private.release_api_cache_lease (bytea, uuid),
private.consume_rate_limit (uuid, text, integer, integer, timestamptz),
private.purge_expired_coordination_state (timestamptz, integer) to service_role;
