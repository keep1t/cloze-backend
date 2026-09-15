begin;

select no_plan();

-- Private bucket and exact persistence contract.
select ok(
  exists (
    select 1
    from storage.buckets
    where id = 'share-snapshots'
      and name = 'share-snapshots'
      and public is false
  ),
  'share-snapshots bucket exists and is private'
);
select is(
  (
    select count(*)::integer
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and roles && array['anon'::name, 'authenticated'::name]
  ),
  0,
  'no client Storage object policies are created'
);
select has_table('private', 'share_snapshots', 'private.share_snapshots exists');
select is(
  (
    select count(*)::integer
    from information_schema.tables
    where table_schema = 'public' and table_name = 'share_snapshots'
  ),
  0,
  'share snapshot persistence is not public'
);
select is(
  (
    select array_agg(column_name::text order by column_name)
    from information_schema.columns
    where table_schema = 'private' and table_name = 'share_snapshots'
  ),
  array[
    'activated_at', 'created_at', 'expires_at', 'revoked_at', 'share_id',
    'status', 'token_hash', 'updated_at', 'upload_expires_at', 'user_id'
  ]::text[],
  'share snapshots contain only opaque identity, owner, state, deadlines, and timestamps'
);
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'private'
      and table_name = 'share_snapshots'
      and column_name in (
        'raw_token', 'token', 'object_name', 'object_path', 'image', 'image_data',
        'embedding', 'sqlite_data', 'email', 'display_name', 'location',
        'latitude', 'longitude'
      )
  ),
  'share snapshots store no raw token, object path, image, embedding, SQLite data, PII, or location'
);
select ok(
  (
    select data_type = 'bytea'
    from information_schema.columns
    where table_schema = 'private'
      and table_name = 'share_snapshots'
      and column_name = 'token_hash'
  ),
  'share tokens are stored only as opaque bytea hashes'
);

select is(
  (
    select array_agg(attribute.attname::text order by key_column.ordinality)
    from pg_constraint as constraint_record
    cross join lateral unnest(constraint_record.conkey)
      with ordinality as key_column(attribute_number, ordinality)
    join pg_attribute as attribute
      on attribute.attrelid = constraint_record.conrelid
      and attribute.attnum = key_column.attribute_number
    where constraint_record.conrelid = 'private.share_snapshots'::regclass
      and constraint_record.contype = 'p'
  ),
  array['share_id']::text[],
  'share_id is the primary key'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'private.share_snapshots'::regclass
      and contype = 'u'
      and pg_get_constraintdef(oid) = 'UNIQUE (token_hash)'
  ),
  'token hashes are unique'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'private.share_snapshots'::regclass
      and confrelid = 'auth.users'::regclass
      and contype = 'f'
  ),
  'share owners reference Auth users'
);
select ok(
  not exists (
    select 1
    from (values ('user_id'::text), ('expires_at')) as required_index(column_name)
    where not exists (
      select 1
      from pg_index as index_record
      where index_record.indrelid = 'private.share_snapshots'::regclass
        and index_record.indisvalid
        and index_record.indisready
        and pg_get_indexdef(index_record.indexrelid, 1, true) = required_index.column_name
    )
  ),
  'share snapshots have valid owner and expiry indexes'
);

-- RLS and least privilege.
select ok(
  (
    select relrowsecurity and relforcerowsecurity
    from pg_class
    where oid = 'private.share_snapshots'::regclass
  ),
  'share_snapshots has RLS enabled and forced'
);
select is(
  (
    select count(*)::integer
    from pg_policies
    where schemaname = 'private' and tablename = 'share_snapshots'
  ),
  0,
  'share_snapshots has no client RLS policies'
);
select ok(
  has_table_privilege('service_role', 'private.share_snapshots', 'SELECT')
  and has_table_privilege('service_role', 'private.share_snapshots', 'INSERT')
  and has_table_privilege('service_role', 'private.share_snapshots', 'UPDATE')
  and has_table_privilege('service_role', 'private.share_snapshots', 'DELETE')
  and not has_table_privilege('service_role', 'private.share_snapshots', 'TRUNCATE')
  and not has_table_privilege('service_role', 'private.share_snapshots', 'REFERENCES')
  and not has_table_privilege('service_role', 'private.share_snapshots', 'TRIGGER'),
  'service_role receives only share snapshot CRUD privileges'
);
select ok(
  not has_table_privilege('anon', 'private.share_snapshots', 'SELECT')
  and not has_table_privilege('anon', 'private.share_snapshots', 'INSERT')
  and not has_table_privilege('anon', 'private.share_snapshots', 'UPDATE')
  and not has_table_privilege('anon', 'private.share_snapshots', 'DELETE')
  and not has_table_privilege('authenticated', 'private.share_snapshots', 'SELECT')
  and not has_table_privilege('authenticated', 'private.share_snapshots', 'INSERT')
  and not has_table_privilege('authenticated', 'private.share_snapshots', 'UPDATE')
  and not has_table_privilege('authenticated', 'private.share_snapshots', 'DELETE'),
  'client roles have no share snapshot table access'
);

-- Exact service-only, security-invoker function API.
select ok(
  to_regprocedure('private.create_share_snapshot(uuid,uuid,bytea,timestamp with time zone,timestamp with time zone,timestamp with time zone)') is not null
  and to_regprocedure('private.activate_share_snapshot(uuid,uuid,timestamp with time zone)') is not null
  and to_regprocedure('private.resolve_share_snapshot(bytea,timestamp with time zone)') is not null
  and to_regprocedure('private.revoke_share_snapshot(uuid,uuid,timestamp with time zone)') is not null,
  'share lifecycle functions have their exact required signatures'
);
select ok(
  (
    select bool_and(
      not procedure.prosecdef
      and exists (
        select 1
        from unnest(coalesce(procedure.proconfig, array[]::text[])) as setting
        where setting in ('search_path=', 'search_path=""')
      )
    )
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'private'
      and procedure.proname in (
        'create_share_snapshot', 'activate_share_snapshot',
        'resolve_share_snapshot', 'revoke_share_snapshot'
      )
  ),
  'share lifecycle functions are security invoker with empty search paths'
);
select ok(
  not exists (
    select 1
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'private'
      and procedure.proname in (
        'create_share_snapshot', 'activate_share_snapshot',
        'resolve_share_snapshot', 'revoke_share_snapshot'
      )
      and (
        has_function_privilege('anon', procedure.oid, 'EXECUTE')
        or has_function_privilege('authenticated', procedure.oid, 'EXECUTE')
      )
  ),
  'client roles cannot execute share lifecycle functions'
);
select ok(
  (
    select bool_and(has_function_privilege('service_role', procedure.oid, 'EXECUTE'))
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'private'
      and procedure.proname in (
        'create_share_snapshot', 'activate_share_snapshot',
        'resolve_share_snapshot', 'revoke_share_snapshot'
      )
  ),
  'service_role can execute share lifecycle functions'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  (
    'a1000000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'share-owner@example.test', '',
    '2026-01-01 00:00:00+00', '{}', '{}',
    '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00'
  ),
  (
    'a2000000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'other-share-owner@example.test', '',
    '2026-01-01 00:00:00+00', '{}', '{}',
    '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00'
  );

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

-- Creation derives the only canonical private object path.
select results_eq(
  $$select bucket, object_name from private.create_share_snapshot(
    'b1000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000001', decode('aa01','hex'),
    '2026-01-01 01:00:00+00', '2026-01-02 00:00:00+00',
    '2026-01-01 00:00:00+00')$$,
  $$values (
    'share-snapshots'::text,
    'shares/b1000000-0000-4000-8000-000000000001/snapshot'::text)$$,
  'create returns the fixed private bucket and canonical derived object name'
);
select ok(
  (
    select status = 'pending'
      and activated_at is null
      and revoked_at is null
      and created_at = '2026-01-01 00:00:00+00'
      and updated_at = '2026-01-01 00:00:00+00'
    from private.share_snapshots
    where share_id = 'b1000000-0000-4000-8000-000000000001'
  ),
  'create persists a pending record using the supplied decision time'
);

select throws_ok(
  $$select * from private.create_share_snapshot(
    'b1000000-0000-4000-8000-000000000010',
    'a1000000-0000-4000-8000-000000000001', ''::bytea,
    '2026-01-01 01:00:00+00', '2026-01-02 00:00:00+00',
    '2026-01-01 00:00:00+00')$$,
  'P0001', null,
  'create rejects an empty token hash'
);
select throws_ok(
  $$select * from private.create_share_snapshot(
    'b1000000-0000-4000-8000-000000000011',
    'a1000000-0000-4000-8000-000000000001', decode('aa11','hex'),
    '2026-01-01 00:00:00+00', '2026-01-02 00:00:00+00',
    '2026-01-01 00:00:00+00')$$,
  'P0001', null,
  'create requires upload expiry after the supplied current time'
);
select throws_ok(
  $$select * from private.create_share_snapshot(
    'b1000000-0000-4000-8000-000000000012',
    'a1000000-0000-4000-8000-000000000001', decode('aa12','hex'),
    '2026-01-01 02:00:00+00', '2026-01-01 01:00:00+00',
    '2026-01-01 00:00:00+00')$$,
  'P0001', null,
  'create rejects a share expiry before its upload expiry'
);
select throws_ok(
  $$select * from private.create_share_snapshot(
    'b1000000-0000-4000-8000-000000000013',
    'a1000000-0000-4000-8000-000000000001', decode('aa01','hex'),
    '2026-01-01 01:00:00+00', '2026-01-02 00:00:00+00',
    '2026-01-01 00:00:00+00')$$,
  '23505',
  null,
  'a duplicate token hash is rejected'
);

-- Activation requires the canonical object and both deadlines.
select is(
  private.activate_share_snapshot(
    'b1000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000001',
    '2026-01-01 00:10:00+00'),
  false,
  'activation fails while the canonical object is absent'
);
insert into storage.objects (bucket_id, name)
values (
  'share-snapshots',
  'shares/b1000000-0000-4000-8000-000000000001/not-the-snapshot'
);
select is(
  private.activate_share_snapshot(
    'b1000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000001',
    '2026-01-01 00:15:00+00'),
  false,
  'a non-canonical object name cannot activate a share'
);
insert into storage.objects (bucket_id, name)
values (
  'share-snapshots',
  'shares/b1000000-0000-4000-8000-000000000001/snapshot'
);
select is(
  private.activate_share_snapshot(
    'b1000000-0000-4000-8000-000000000001',
    'a2000000-0000-4000-8000-000000000002',
    '2026-01-01 00:20:00+00'),
  false,
  'a different owner cannot activate a share'
);
select is(
  private.activate_share_snapshot(
    'b1000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000001',
    '2026-01-01 00:30:00+00'),
  true,
  'the owner can activate a pending share with its canonical object before deadlines'
);
select ok(
  (
    select status = 'active'
      and activated_at = '2026-01-01 00:30:00+00'
      and revoked_at is null
      and updated_at = '2026-01-01 00:30:00+00'
    from private.share_snapshots
    where share_id = 'b1000000-0000-4000-8000-000000000001'
  ),
  'activation records state and timestamps from the supplied current time'
);
select is(
  private.activate_share_snapshot(
    'b1000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000001',
    '2026-01-01 00:40:00+00'),
  false,
  'an active share cannot be activated again'
);

select results_eq(
  $$select share_id, bucket, object_name, expires_at
    from private.resolve_share_snapshot(
      decode('aa01','hex'), '2026-01-01 12:00:00+00')$$,
  $$values (
    'b1000000-0000-4000-8000-000000000001'::uuid,
    'share-snapshots'::text,
    'shares/b1000000-0000-4000-8000-000000000001/snapshot'::text,
    '2026-01-02 00:00:00+00'::timestamptz)$$,
  'an active unexpired token hash resolves only the canonical object identity'
);
select results_eq(
  $$select share_id, bucket, object_name, expires_at
    from private.resolve_share_snapshot(
      decode('aa01','hex'), '2026-01-02 00:00:00+00')$$,
  $$select null::uuid, null::text, null::text, null::timestamptz where false$$,
  'logical expiry stops resolution at the exact expiry boundary'
);
select results_eq(
  $$select share_id, bucket, object_name, expires_at
    from private.resolve_share_snapshot(
      decode('ffff','hex'), '2026-01-01 12:00:00+00')$$,
  $$select null::uuid, null::text, null::text, null::timestamptz where false$$,
  'an unknown token hash does not resolve'
);

-- Deadline and pending-revocation fixtures.
select * from private.create_share_snapshot(
  'b2000000-0000-4000-8000-000000000002',
  'a1000000-0000-4000-8000-000000000001', decode('aa02','hex'),
  '2026-01-01 01:00:00+00', '2026-01-02 00:00:00+00',
  '2026-01-01 00:00:00+00');
insert into storage.objects (bucket_id, name)
values (
  'share-snapshots',
  'shares/b2000000-0000-4000-8000-000000000002/snapshot'
);
select is(
  private.activate_share_snapshot(
    'b2000000-0000-4000-8000-000000000002',
    'a1000000-0000-4000-8000-000000000001',
    '2026-01-01 01:00:00+00'),
  false,
  'activation fails at the exact upload expiry boundary'
);
select results_eq(
  $$select share_id, bucket, object_name, expires_at
    from private.resolve_share_snapshot(
      decode('aa02','hex'), '2026-01-01 00:30:00+00')$$,
  $$select null::uuid, null::text, null::text, null::timestamptz where false$$,
  'a pending token hash never resolves'
);

select * from private.create_share_snapshot(
  'b3000000-0000-4000-8000-000000000003',
  'a1000000-0000-4000-8000-000000000001', decode('aa03','hex'),
  '2026-01-01 01:00:00+00', '2026-01-02 00:00:00+00',
  '2026-01-01 00:00:00+00');
select is(
  private.revoke_share_snapshot(
    'b3000000-0000-4000-8000-000000000003',
    'a2000000-0000-4000-8000-000000000002',
    '2026-01-01 00:20:00+00'),
  false,
  'a different owner cannot revoke a pending share'
);
select is(
  private.revoke_share_snapshot(
    'b3000000-0000-4000-8000-000000000003',
    'a1000000-0000-4000-8000-000000000001',
    '2026-01-01 00:20:00+00'),
  true,
  'the owner can revoke a pending share'
);
select ok(
  (
    select status = 'revoked'
      and activated_at is null
      and revoked_at = '2026-01-01 00:20:00+00'
      and updated_at = '2026-01-01 00:20:00+00'
    from private.share_snapshots
    where share_id = 'b3000000-0000-4000-8000-000000000003'
  ),
  'pending revocation records the supplied time without activation'
);
select is(
  private.revoke_share_snapshot(
    'b3000000-0000-4000-8000-000000000003',
    'a1000000-0000-4000-8000-000000000001',
    '2026-01-01 00:21:00+00'),
  false,
  'a revoked share cannot be revoked again'
);

select is(
  private.revoke_share_snapshot(
    'b1000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000001',
    '2026-01-01 13:00:00+00'),
  true,
  'the owner can revoke an active share'
);
select results_eq(
  $$select share_id, bucket, object_name, expires_at
    from private.resolve_share_snapshot(
      decode('aa01','hex'), '2026-01-01 13:01:00+00')$$,
  $$select null::uuid, null::text, null::text, null::timestamptz where false$$,
  'a revoked token hash never resolves'
);

-- Invalid direct states are rejected by table constraints.
select throws_ok(
  $$insert into private.share_snapshots (
    share_id, user_id, token_hash, status, upload_expires_at, expires_at
  ) values (
    'b4000000-0000-4000-8000-000000000004',
    'a1000000-0000-4000-8000-000000000001', decode('aa04','hex'),
    'active', '2026-01-01 01:00:00+00', '2026-01-02 00:00:00+00')$$,
  '23514', null,
  'an active share requires an activation timestamp'
);
select throws_ok(
  $$insert into private.share_snapshots (
    share_id, user_id, token_hash, status, upload_expires_at, expires_at
  ) values (
    'b4000000-0000-4000-8000-000000000005',
    'a1000000-0000-4000-8000-000000000001', decode('aa05','hex'),
    'revoked', '2026-01-01 01:00:00+00', '2026-01-02 00:00:00+00')$$,
  '23514', null,
  'a revoked share requires a revocation timestamp'
);

reset role;
select set_config('request.jwt.claims', '{}', true);

-- Clients cannot read or invoke private share lifecycle operations.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select throws_ok(
  $$select * from private.share_snapshots$$,
  '42501', null,
  'authenticated clients cannot read share snapshot state'
);
select throws_ok(
  $$select * from private.resolve_share_snapshot(decode('aa01','hex'), '2026-01-01')$$,
  '42501', null,
  'authenticated clients cannot invoke share lifecycle functions'
);
reset role;
select set_config('request.jwt.claims', '{}', true);

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select throws_ok(
  $$select * from private.share_snapshots$$,
  '42501', null,
  'anonymous clients cannot read share snapshot state'
);
select throws_ok(
  $$select * from private.resolve_share_snapshot(decode('aa01','hex'), '2026-01-01')$$,
  '42501', null,
  'anonymous clients cannot invoke share lifecycle functions'
);
reset role;
select set_config('request.jwt.claims', '{}', true);

select * from finish();

rollback;
