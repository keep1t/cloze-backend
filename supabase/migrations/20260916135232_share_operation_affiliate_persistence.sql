-- T06: Persist replayable share operations, canonical affiliate associations,
-- and initial cleanup state for the sharing lifecycle.

-- ──────────────────────────────────────────────────────────────────────────────
-- Tables
-- ──────────────────────────────────────────────────────────────────────────────

create table private.share_operations (
  owner_id uuid not null references auth.users (id) on delete cascade,
  operation_id uuid not null,
  share_id uuid not null unique references private.share_snapshots (share_id) on delete cascade,
  token_key_version text not null
    check (token_key_version = trim(token_key_version) and length(token_key_version) > 0),
  created_at timestamptz not null,
  primary key (owner_id, operation_id)
);

create table private.share_snapshot_affiliate_links (
  share_id uuid not null references private.share_snapshots (share_id) on delete cascade,
  position integer not null check (position > 0),
  garment_ref text not null
    check (garment_ref = trim(garment_ref) and length(garment_ref) > 0),
  url text not null
    check (url = trim(url) and length(url) > 0),
  primary key (share_id, position)
);

alter table private.share_snapshot_affiliate_links
  add constraint share_snapshot_affiliate_links_share_id_garment_ref_key
  unique (share_id, garment_ref);

create table private.share_snapshot_cleanup (
  share_id uuid primary key references private.share_snapshots (share_id) on delete cascade,
  object_deleted_at timestamptz,
  claimed_at timestamptz,
  claim_token uuid,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_error_code text check (last_error_code is null or length(trim(last_error_code)) > 0)
);

-- Claim timestamp and token must be both null or both non-null.
alter table private.share_snapshot_cleanup
  add constraint share_snapshot_cleanup_claim_pair_check
  check ((claimed_at is null) = (claim_token is null));

-- A deleted object cannot retain a cleanup claim.
alter table private.share_snapshot_cleanup
  add constraint share_snapshot_cleanup_no_claim_after_delete_check
  check (object_deleted_at is null or claimed_at is null);

-- ──────────────────────────────────────────────────────────────────────────────
-- RLS and grants (private, service-only)
-- ──────────────────────────────────────────────────────────────────────────────

alter table private.share_operations enable row level security;
alter table private.share_operations force row level security;

alter table private.share_snapshot_affiliate_links enable row level security;
alter table private.share_snapshot_affiliate_links force row level security;

alter table private.share_snapshot_cleanup enable row level security;
alter table private.share_snapshot_cleanup force row level security;

revoke all on table private.share_operations,
private.share_snapshot_affiliate_links,
private.share_snapshot_cleanup
from
  public,
  anon,
  authenticated,
  service_role;

-- The migration role created these tables, so it is their owner and still
-- holds the default full-owner ACL entries (including TRUNCATE, REFERENCES,
-- TRIGGER, and MAINTAIN). Remove those so the private tables expose no
-- privileges beyond the explicit service-only CRUD grants.
revoke all on table private.share_operations,
private.share_snapshot_affiliate_links,
private.share_snapshot_cleanup
from current_user;

grant
  select,
  insert,
  update,
  delete on table private.share_operations,
private.share_snapshot_affiliate_links,
private.share_snapshot_cleanup to service_role;

-- ──────────────────────────────────────────────────────────────────────────────
-- Atomic service function
-- ──────────────────────────────────────────────────────────────────────────────

create function private.create_share_operation (
  p_owner_id uuid,
  p_operation_id uuid,
  p_share_id uuid,
  p_token_hash bytea,
  p_token_key_version text,
  p_upload_expires_at timestamptz,
  p_expires_at timestamptz,
  p_affiliate_links jsonb,
  p_now timestamptz
) returns table (decision text, share_id uuid)
language plpgsql
security invoker
set
  search_path = '' as $$
declare
  v_existing record;
  v_link jsonb;
begin
  -- Structural validation: reject NULL for every required parameter. The
  -- contract treats NULL as invalid for all inputs including UUIDs.
  if p_owner_id is null
    or p_operation_id is null
    or p_share_id is null
    or p_token_hash is null
    or p_token_key_version is null
    or p_upload_expires_at is null
    or p_expires_at is null
    or p_affiliate_links is null
    or p_now is null
  then
    raise exception using errcode = 'P0001';
  end if;

  -- Nonempty token hash, already-trimmed nonempty key version, and deadline
  -- ordering. Input is persisted exactly; padded values are rejected, never
  -- silently trimmed.
  if octet_length(p_token_hash) = 0
    or length(trim(p_token_key_version)) = 0
    or p_token_key_version <> trim(p_token_key_version)
    or p_upload_expires_at <= p_now
    or p_expires_at < p_upload_expires_at
  then
    raise exception using errcode = 'P0001';
  end if;

  -- Affiliate array validation: must be a JSON array (empty is valid).
  -- Each element must be an object with exactly "garment_ref" and "url",
  -- both JSON strings that are already-trimmed and nonempty. No duplicate
  -- garment_ref values.
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
    then
      raise exception using errcode = 'P0001';
    end if;
  end loop;

  -- Duplicate garment references within the array are invalid.
  if exists (
    select 1
    from (
      select elem.value->>'garment_ref' as garment_ref
      from jsonb_array_elements(p_affiliate_links)
        with ordinality as elem(value, ord)
      group by elem.value->>'garment_ref'
      having count(*) > 1
    ) as duplicates
  ) then
    raise exception using errcode = 'P0001';
  end if;

  -- Serialize concurrent calls for the same owner and operation.
  perform pg_advisory_xact_lock(
    hashtextextended(p_owner_id::text || ':' || p_operation_id::text, 0)
  );

  -- Check for an existing operation (replay or immutable conflict).
  select
    so.share_id,
    so.token_key_version,
    so.created_at,
    ss.token_hash,
    ss.upload_expires_at,
    ss.expires_at,
    coalesce(
      (select jsonb_agg(
        jsonb_build_object('garment_ref', sal.garment_ref, 'url', sal.url)
        order by sal.position
      ) from private.share_snapshot_affiliate_links sal
        where sal.share_id = so.share_id),
      '[]'::jsonb
    ) as affiliates
  into v_existing
  from private.share_operations so
  join private.share_snapshots ss on ss.share_id = so.share_id
  where so.owner_id = p_owner_id
    and so.operation_id = p_operation_id;

  if found then
    -- Compare every immutable request value for replay equality.
    if v_existing.share_id = p_share_id
      and v_existing.token_hash = p_token_hash
      and v_existing.token_key_version = p_token_key_version
      and v_existing.upload_expires_at = p_upload_expires_at
      and v_existing.expires_at = p_expires_at
      and jsonb_array_length(v_existing.affiliates) = coalesce(jsonb_array_length(p_affiliate_links), 0)
      and (
        jsonb_array_length(v_existing.affiliates) = 0
        or v_existing.affiliates = p_affiliate_links
      )
    then
      decision := 'replay';
      share_id := v_existing.share_id;
      return next;
      return;
    end if;

    decision := 'conflict';
    share_id := null;
    return next;
    return;
  end if;

  -- Detect unrelated share_id or token_hash uniqueness collisions before
  -- attempting inserts. Return non-disclosing conflict without creating rows.
  -- Table columns are fully qualified here because the output variable
  -- "share_id" would otherwise shadow/ambiguate the snapshot column.
  if exists (
    select 1 from private.share_snapshots ss
    where ss.share_id = p_share_id
  ) or exists (
    select 1 from private.share_snapshots ss
    where ss.token_hash = p_token_hash
  ) then
    decision := 'conflict';
    share_id := null;
    return next;
    return;
  end if;

  -- First creation: atomically create the pending snapshot, operation row,
  -- ordered affiliate rows, and default cleanup state.
  insert into private.share_snapshots (
    share_id, user_id, token_hash, status, upload_expires_at,
    expires_at, activated_at, revoked_at, created_at, updated_at
  ) values (
    p_share_id, p_owner_id, p_token_hash, 'pending',
    p_upload_expires_at, p_expires_at, null, null, p_now, p_now
  );

  insert into private.share_operations (
    owner_id, operation_id, share_id, token_key_version, created_at
  ) values (
    p_owner_id, p_operation_id, p_share_id, p_token_key_version, p_now
  );

  -- Persist ordered affiliate rows (ordinal position from array index).
  insert into private.share_snapshot_affiliate_links (
    share_id, position, garment_ref, url
  )
  select p_share_id, elem.ord, elem.value->>'garment_ref', elem.value->>'url'
  from jsonb_array_elements(p_affiliate_links)
    with ordinality as elem(value, ord);

  -- Default cleanup state: no deletion, no claim, zero attempts, no error.
  insert into private.share_snapshot_cleanup (share_id)
  values (p_share_id);

  decision := 'created';
  share_id := p_share_id;
  return next;
exception
  when unique_violation then
    -- Unrelated share_id or token_hash collision raced a concurrent call;
    -- remain non-disclosing and create no rows.
    decision := 'conflict';
    share_id := null;
    return next;
end $$;

revoke all on function private.create_share_operation (
  uuid,
  uuid,
  uuid,
  bytea,
  text,
  timestamptz,
  timestamptz,
  jsonb,
  timestamptz
) from public, anon, authenticated, service_role;

grant execute on function private.create_share_operation (
  uuid,
  uuid,
  uuid,
  bytea,
  text,
  timestamptz,
  timestamptz,
  jsonb,
  timestamptz
) to service_role;
