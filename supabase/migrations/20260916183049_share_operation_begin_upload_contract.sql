-- T013: Add immutable upload metadata and an owner/operation replay contract.

create table private.share_snapshot_upload_contract (
  share_id uuid primary key references private.share_snapshots (share_id) on delete cascade,
  expected_content_type text not null check (
    expected_content_type = btrim(expected_content_type)
    and length(expected_content_type) > 0
  ),
  expected_byte_length bigint not null check (expected_byte_length > 0)
);

alter table private.share_snapshot_upload_contract enable row level security;
alter table private.share_snapshot_upload_contract force row level security;

revoke all on table private.share_snapshot_upload_contract
from public, anon, authenticated, service_role;
revoke all on table private.share_snapshot_upload_contract from current_user;
grant select, insert, update, delete on table private.share_snapshot_upload_contract to service_role;

create function private.begin_share_operation (
  p_owner_id uuid,
  p_operation_id uuid,
  p_share_id uuid,
  p_token_hash bytea,
  p_token_key_version text,
  p_upload_expires_at timestamptz,
  p_expires_at timestamptz,
  p_expected_content_type text,
  p_expected_byte_length bigint,
  p_affiliate_links jsonb,
  p_now timestamptz
) returns table (
  decision text,
  share_id uuid,
  token_key_version text,
  status text,
  upload_expires_at timestamptz,
  expires_at timestamptz,
  expected_content_type text,
  expected_byte_length bigint
)
language plpgsql
security invoker
set search_path = '' as $$
declare
  v_link jsonb;
  v_existing record;
  v_creation record;
begin
  if p_owner_id is null or p_operation_id is null or p_share_id is null
    or p_token_hash is null or p_token_key_version is null
    or p_upload_expires_at is null or p_expires_at is null
    or p_expected_content_type is null or p_expected_byte_length is null
    or p_affiliate_links is null or p_now is null
  then raise exception using errcode = 'P0001'; end if;

  if octet_length(p_token_hash) = 0
    or length(trim(p_token_key_version)) = 0
    or p_token_key_version <> trim(p_token_key_version)
    or length(trim(p_expected_content_type)) = 0
    or p_expected_content_type <> btrim(p_expected_content_type)
    or p_expected_byte_length <= 0
    or p_upload_expires_at <= p_now
    or p_expires_at < p_upload_expires_at
  then raise exception using errcode = 'P0001'; end if;

  if jsonb_typeof(p_affiliate_links) <> 'array' then
    raise exception using errcode = 'P0001';
  end if;
  for v_link in select value from jsonb_array_elements(p_affiliate_links)
  loop
    if jsonb_typeof(v_link) <> 'object'
      or (select count(*)::integer from jsonb_object_keys(v_link)) <> 2
      or jsonb_typeof(v_link->'garment_ref') is distinct from 'string'
      or jsonb_typeof(v_link->'url') is distinct from 'string'
      or length(trim(v_link->>'garment_ref')) = 0
      or v_link->>'garment_ref' <> trim(v_link->>'garment_ref')
      or length(trim(v_link->>'url')) = 0
      or v_link->>'url' <> trim(v_link->>'url')
    then raise exception using errcode = 'P0001'; end if;
  end loop;
  if exists (
    select 1 from (
      select value->>'garment_ref' as garment_ref
      from jsonb_array_elements(p_affiliate_links)
      group by value->>'garment_ref' having count(*) > 1
    ) duplicates
  ) then raise exception using errcode = 'P0001'; end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_owner_id::text || ':' || p_operation_id::text, 0)
  );

  select so.share_id, so.token_key_version, ss.status, ss.upload_expires_at,
    ss.expires_at, ss.user_id, uc.expected_content_type, uc.expected_byte_length,
    coalesce((select jsonb_agg(jsonb_build_object('garment_ref', sal.garment_ref, 'url', sal.url) order by sal.position)
      from private.share_snapshot_affiliate_links sal where sal.share_id = so.share_id), '[]'::jsonb) as affiliates
  into v_existing
  from private.share_operations so
  join private.share_snapshots ss on ss.share_id = so.share_id
  left join private.share_snapshot_upload_contract uc on uc.share_id = so.share_id
  where so.owner_id = p_owner_id and so.operation_id = p_operation_id;

  if found then
    if v_existing.expected_content_type is null then
      decision := 'unavailable'; return next; return;
    end if;
    if v_existing.expected_content_type <> p_expected_content_type
      or v_existing.expected_byte_length <> p_expected_byte_length
      or v_existing.affiliates <> p_affiliate_links
    then decision := 'conflict'; return next; return; end if;

    decision := case
      when v_existing.status = 'pending' and p_now < v_existing.upload_expires_at then 'pending_replay'
      when v_existing.status = 'pending' then 'upload_window_expired'
      when v_existing.status = 'active' and p_now < v_existing.expires_at then 'active_replay'
      when v_existing.status = 'active' then 'share_expired'
      when v_existing.status = 'revoked' then 'share_revoked'
      else null
    end;
    if decision is null then raise exception using errcode = 'P0001'; end if;
    if decision in ('pending_replay', 'active_replay') then
      share_id := v_existing.share_id; token_key_version := v_existing.token_key_version;
      status := v_existing.status; upload_expires_at := v_existing.upload_expires_at;
      expires_at := v_existing.expires_at; expected_content_type := v_existing.expected_content_type;
      expected_byte_length := v_existing.expected_byte_length;
    end if;
    return next; return;
  end if;

  if exists (select 1 from private.share_snapshots ss2 where ss2.share_id = p_share_id)
    or exists (select 1 from private.share_snapshots ss2 where ss2.token_hash = p_token_hash)
  then decision := 'conflict'; return next; return; end if;

  select * into v_creation from private.create_share_operation(
    p_owner_id, p_operation_id, p_share_id, p_token_hash, p_token_key_version,
    p_upload_expires_at, p_expires_at, p_affiliate_links, p_now
  );
  if v_creation.decision <> 'created' then decision := v_creation.decision; return next; return; end if;

  insert into private.share_snapshot_upload_contract (share_id, expected_content_type, expected_byte_length)
  values (p_share_id, p_expected_content_type, p_expected_byte_length);
  decision := 'created'; share_id := p_share_id; token_key_version := p_token_key_version;
  status := 'pending'; upload_expires_at := p_upload_expires_at; expires_at := p_expires_at;
  expected_content_type := p_expected_content_type; expected_byte_length := p_expected_byte_length;
  return next;
exception when unique_violation then
  decision := 'conflict'; share_id := null; return next;
end $$;

revoke all on function private.begin_share_operation(
  uuid, uuid, uuid, bytea, text, timestamptz, timestamptz, text, bigint, jsonb, timestamptz
) from public, anon, authenticated, service_role;
grant execute on function private.begin_share_operation(
  uuid, uuid, uuid, bytea, text, timestamptz, timestamptz, text, bigint, jsonb, timestamptz
) to service_role;
