begin;

select no_plan();

-- The T06 persistence surface is limited to these three private tables.
select is(
  (
    select array_agg(table_name::text order by table_name)
    from information_schema.tables
    where table_schema = 'private'
      and table_name in (
        'share_operations', 'share_snapshot_affiliate_links',
        'share_snapshot_cleanup'
      )
  ),
  array[
    'share_operations', 'share_snapshot_affiliate_links',
    'share_snapshot_cleanup'
  ]::text[],
  'T06 creates exactly its three private persistence tables'
);
select is(
  (
    select count(*)::integer
    from information_schema.tables
    where table_schema = 'public'
      and table_name in (
        'share_operations', 'share_snapshot_affiliate_links',
        'share_snapshot_cleanup'
      )
  ),
  0,
  'T06 creates no public persistence tables'
);
select is(
  (
    select array_agg(column_name::text order by column_name)
    from information_schema.columns
    where table_schema = 'private' and table_name = 'share_operations'
  ),
  array['created_at', 'operation_id', 'owner_id', 'share_id', 'token_key_version']::text[],
  'share operations have the exact minimal columns'
);
select is(
  (
    select array_agg(column_name::text order by column_name)
    from information_schema.columns
    where table_schema = 'private' and table_name = 'share_snapshot_affiliate_links'
  ),
  array['garment_ref', 'position', 'share_id', 'url']::text[],
  'affiliate links have the exact canonical columns'
);
select is(
  (
    select array_agg(column_name::text order by column_name)
    from information_schema.columns
    where table_schema = 'private' and table_name = 'share_snapshot_cleanup'
  ),
  array[
    'attempt_count', 'claim_token', 'claimed_at', 'last_error_code',
    'object_deleted_at', 'share_id'
  ]::text[],
  'cleanup state has the exact minimal columns'
);
select is(
  (
    select array_agg(column_name || ':' || data_type || ':' || is_nullable order by column_name)
    from information_schema.columns
    where table_schema = 'private' and table_name = 'share_operations'
  ),
  array[
    'created_at:timestamp with time zone:NO', 'operation_id:uuid:NO',
    'owner_id:uuid:NO', 'share_id:uuid:NO', 'token_key_version:text:NO'
  ]::text[],
  'share operation columns have their exact types and nullability'
);
select is(
  (
    select array_agg(column_name || ':' || data_type || ':' || is_nullable order by column_name)
    from information_schema.columns
    where table_schema = 'private' and table_name = 'share_snapshot_affiliate_links'
  ),
  array[
    'garment_ref:text:NO', 'position:integer:NO', 'share_id:uuid:NO', 'url:text:NO'
  ]::text[],
  'affiliate link columns have their exact types and nullability'
);
select is(
  (
    select array_agg(column_name || ':' || data_type || ':' || is_nullable order by column_name)
    from information_schema.columns
    where table_schema = 'private' and table_name = 'share_snapshot_cleanup'
  ),
  array[
    'attempt_count:integer:NO', 'claim_token:uuid:YES', 'claimed_at:timestamp with time zone:YES',
    'last_error_code:text:YES', 'object_deleted_at:timestamp with time zone:YES', 'share_id:uuid:NO'
  ]::text[],
  'cleanup columns have their exact types and nullability'
);
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'private'
      and table_name in (
        'share_operations', 'share_snapshot_affiliate_links',
        'share_snapshot_cleanup'
      )
      and column_name in (
        'raw_token', 'token', 'token_value', 'landing_url', 'object_name',
        'object_path', 'image', 'image_data', 'embedding', 'outfit_id',
        'garment_id', 'garment_image', 'email', 'display_name', 'provider_body',
        'provider_payload', 'request_body', 'device_id', 'location', 'latitude',
        'longitude'
      )
  ),
  'T06 persists no raw token, landing URL, object path, image, cloud garment or outfit, PII, or provider body'
);

-- Keys, foreign keys, and structural checks are part of the database contract.
select is(
  (
    select array_agg(attribute.attname::text order by key_column.ordinality)
    from pg_constraint as constraint_record
    cross join lateral unnest(constraint_record.conkey)
      with ordinality as key_column(attribute_number, ordinality)
    join pg_attribute as attribute
      on attribute.attrelid = constraint_record.conrelid
      and attribute.attnum = key_column.attribute_number
    where constraint_record.conrelid = 'private.share_operations'::regclass
      and constraint_record.contype = 'p'
  ),
  array['owner_id', 'operation_id']::text[],
  'owner and operation are the share operation primary key'
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
    where constraint_record.conrelid = 'private.share_snapshot_affiliate_links'::regclass
      and constraint_record.contype = 'p'
  ),
  array['share_id', 'position']::text[],
  'share and ordinal position are the affiliate primary key'
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
    where constraint_record.conrelid = 'private.share_snapshot_cleanup'::regclass
      and constraint_record.contype = 'p'
  ),
  array['share_id']::text[],
  'share is the cleanup primary key'
);
select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'private.share_operations'::regclass
      and contype = 'u' and pg_get_constraintdef(oid) = 'UNIQUE (share_id)'
  )
  and exists (
    select 1 from pg_constraint
    where conrelid = 'private.share_snapshot_affiliate_links'::regclass
      and contype = 'u' and pg_get_constraintdef(oid) = 'UNIQUE (share_id, garment_ref)'
  ),
  'share identity and per-share garment references are unique'
);
select ok(
  (select count(*) from pg_constraint
   where conrelid = 'private.share_operations'::regclass and contype = 'f'
     and pg_get_constraintdef(oid) in (
       'FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE',
       'FOREIGN KEY (share_id) REFERENCES private.share_snapshots(share_id) ON DELETE CASCADE'
     )) = 2
  and (select count(*) from pg_constraint
       where conrelid = 'private.share_snapshot_affiliate_links'::regclass
         and contype = 'f'
         and pg_get_constraintdef(oid) = 'FOREIGN KEY (share_id) REFERENCES private.share_snapshots(share_id) ON DELETE CASCADE') = 1
  and (select count(*) from pg_constraint
       where conrelid = 'private.share_snapshot_cleanup'::regclass
         and contype = 'f'
         and pg_get_constraintdef(oid) = 'FOREIGN KEY (share_id) REFERENCES private.share_snapshots(share_id) ON DELETE CASCADE') = 1,
  'all T06 foreign keys reference their required parent with delete cascades'
);

-- Every table is service-only even if a future schema default changes grants.
select ok(
  (
    select bool_and(class.relrowsecurity and class.relforcerowsecurity)
    from pg_class as class
    join pg_namespace as namespace on namespace.oid = class.relnamespace
    where namespace.nspname = 'private'
      and class.relname in (
        'share_operations', 'share_snapshot_affiliate_links',
        'share_snapshot_cleanup'
      )
  ),
  'all T06 tables have RLS enabled and forced'
);
select is(
  (select count(*)::integer from pg_policies
   where schemaname = 'private'
     and tablename in ('share_operations', 'share_snapshot_affiliate_links', 'share_snapshot_cleanup')),
  0,
  'T06 tables have no RLS policies'
);
select ok(
  not exists (
    select 1
    from pg_class as class
    join pg_namespace as namespace on namespace.oid = class.relnamespace
    cross join lateral aclexplode(coalesce(class.relacl, acldefault('r', class.relowner))) as acl
    where namespace.nspname = 'private'
      and class.relname in ('share_operations', 'share_snapshot_affiliate_links', 'share_snapshot_cleanup')
      and acl.grantee = 0
      and acl.privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER')
  )
  and not exists (
    select 1
    from (values ('anon'::text), ('authenticated')) as role_name(name)
    cross join (values ('share_operations'::text), ('share_snapshot_affiliate_links'), ('share_snapshot_cleanup')) as table_name(name)
    cross join (values ('SELECT'::text), ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE'), ('REFERENCES'), ('TRIGGER')) as privilege(name)
    where has_table_privilege(role_name.name, format('private.%I', table_name.name), privilege.name)
  )
  and not exists (
    select 1
    from (values ('share_operations'::text), ('share_snapshot_affiliate_links'), ('share_snapshot_cleanup')) as table_name(name)
    cross join (values ('TRUNCATE'::text), ('REFERENCES'), ('TRIGGER')) as privilege(name)
    where has_table_privilege('service_role', format('private.%I', table_name.name), privilege.name)
  ),
  'PUBLIC and client roles have no table privileges and service_role has no extra privileges'
);
select ok(
  not exists (
    select 1
    from pg_class as class
    join pg_namespace as namespace on namespace.oid = class.relnamespace
    cross join lateral aclexplode(coalesce(class.relacl, acldefault('r', class.relowner))) as acl
    where namespace.nspname = 'private'
      and class.relname in ('share_operations', 'share_snapshot_affiliate_links', 'share_snapshot_cleanup')
      and (acl.grantee <> 'service_role'::regrole or acl.privilege_type not in ('SELECT', 'INSERT', 'UPDATE', 'DELETE'))
  )
  and not exists (
    select 1
    from (values ('share_operations'::text), ('share_snapshot_affiliate_links'), ('share_snapshot_cleanup')) as table_name(name)
    cross join (values ('SELECT'::text), ('INSERT'), ('UPDATE'), ('DELETE')) as privilege(name)
    where not exists (
      select 1
      from pg_class as class
      join pg_namespace as namespace on namespace.oid = class.relnamespace
      cross join lateral aclexplode(coalesce(class.relacl, acldefault('r', class.relowner))) as acl
      where namespace.nspname = 'private'
        and class.relname = table_name.name
        and acl.grantee = 'service_role'::regrole
        and acl.privilege_type = privilege.name
    )
  ),
  'service_role receives the only explicit CRUD grants on every T06 table'
);

select ok(
  to_regprocedure('private.create_share_operation(uuid,uuid,uuid,bytea,text,timestamp with time zone,timestamp with time zone,jsonb,timestamp with time zone)') is not null,
  'create_share_operation has the exact required signature'
);
select ok(
  (
    select not procedure.prosecdef
      and exists (
        select 1 from unnest(coalesce(procedure.proconfig, array[]::text[])) as setting
        where setting in ('search_path=', 'search_path=""')
      )
    from pg_proc as procedure
    where procedure.oid = 'private.create_share_operation(uuid,uuid,uuid,bytea,text,timestamp with time zone,timestamp with time zone,jsonb,timestamp with time zone)'::regprocedure
  )
  and not exists (
    select 1
    from pg_proc as procedure
    cross join lateral aclexplode(coalesce(procedure.proacl, acldefault('f', procedure.proowner))) as acl
    where procedure.oid = 'private.create_share_operation(uuid,uuid,uuid,bytea,text,timestamp with time zone,timestamp with time zone,jsonb,timestamp with time zone)'::regprocedure
      and acl.grantee = 0
      and acl.privilege_type = 'EXECUTE'
  )
  and not has_function_privilege('anon', 'private.create_share_operation(uuid,uuid,uuid,bytea,text,timestamp with time zone,timestamp with time zone,jsonb,timestamp with time zone)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'private.create_share_operation(uuid,uuid,uuid,bytea,text,timestamp with time zone,timestamp with time zone,jsonb,timestamp with time zone)', 'EXECUTE')
  and has_function_privilege('service_role', 'private.create_share_operation(uuid,uuid,uuid,bytea,text,timestamp with time zone,timestamp with time zone,jsonb,timestamp with time zone)', 'EXECUTE'),
  'create_share_operation is security invoker, has an empty search path, and is service-only'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('c6100000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't06-owner@example.test', '', '2026-01-01', '{}', '{}', '2026-01-01', '2026-01-01'),
  ('c6200000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't06-other-owner@example.test', '', '2026-01-01', '{}', '{}', '2026-01-01', '2026-01-01');

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

-- First creation atomically establishes the snapshot, operation, ordered links, and cleanup state.
select results_eq(
  $$select * from private.create_share_operation(
    'c6100000-0000-4000-8000-000000000001', 'd6100000-0000-4000-8000-000000000001',
    'e6100000-0000-4000-8000-000000000001', decode('6101','hex'), 'v1',
    '2026-01-01 01:00:00+00', '2026-01-02 00:00:00+00',
    '[{"garment_ref":"garment-a","url":"https://affiliate.example/a"},{"garment_ref":"garment-b","url":"https://affiliate.example/b"}]'::jsonb,
    '2026-01-01 00:00:00+00')$$,
  $$values ('created'::text, 'e6100000-0000-4000-8000-000000000001'::uuid)$$,
  'a valid operation creates and returns its pending share'
);
select ok(
  (select user_id = 'c6100000-0000-4000-8000-000000000001'::uuid and token_hash = decode('6101','hex') and status = 'pending' and upload_expires_at = '2026-01-01 01:00:00+00'::timestamptz and expires_at = '2026-01-02 00:00:00+00'::timestamptz and created_at = '2026-01-01 00:00:00+00'::timestamptz from private.share_snapshots where share_id = 'e6100000-0000-4000-8000-000000000001')
  and (select created_at = '2026-01-01 00:00:00+00'::timestamptz and token_key_version = 'v1' from private.share_operations where owner_id = 'c6100000-0000-4000-8000-000000000001' and operation_id = 'd6100000-0000-4000-8000-000000000001')
  and (select array_agg(position || ':' || garment_ref || ':' || url order by position) from private.share_snapshot_affiliate_links where share_id = 'e6100000-0000-4000-8000-000000000001') = array['1:garment-a:https://affiliate.example/a', '2:garment-b:https://affiliate.example/b']::text[]
  and (select object_deleted_at is null and claimed_at is null and claim_token is null and attempt_count = 0 and last_error_code is null from private.share_snapshot_cleanup where share_id = 'e6100000-0000-4000-8000-000000000001'),
  'creation persists canonical affiliates and exactly default cleanup state'
);
select results_eq(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6100000-0000-4000-8000-000000000001','e6100000-0000-4000-8000-000000000001',decode('6101','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[{"garment_ref":"garment-a","url":"https://affiliate.example/a"},{"garment_ref":"garment-b","url":"https://affiliate.example/b"}]'::jsonb,'2026-01-01 00:30:00+00')$$,
  $$values ('replay'::text, 'e6100000-0000-4000-8000-000000000001'::uuid)$$,
  'an exact immutable request replays without a duplicate operation'
);
select is((select count(*)::integer from private.share_operations where owner_id = 'c6100000-0000-4000-8000-000000000001' and operation_id = 'd6100000-0000-4000-8000-000000000001'), 1, 'replay leaves one operation row');

select throws_ok(
  $$insert into private.share_snapshot_affiliate_links values ('e6100000-0000-4000-8000-000000000001', 0, 'invalid-position', 'https://affiliate.example/invalid')$$,
  '23514', null, 'affiliate positions must be positive'
);
select throws_ok(
  $$insert into private.share_snapshot_affiliate_links values ('e6100000-0000-4000-8000-000000000001', 3, ' ', 'https://affiliate.example/invalid')$$,
  '23514', null, 'affiliate garment references must be trimmed and nonempty'
);
select throws_ok(
  $$update private.share_snapshot_cleanup set claimed_at = '2026-01-01 00:00:00+00' where share_id = 'e6100000-0000-4000-8000-000000000001'$$,
  '23514', null, 'cleanup claims require both timestamp and token'
);
select throws_ok(
  $$update private.share_snapshot_cleanup set claim_token = 'f6100000-0000-4000-8000-000000000001' where share_id = 'e6100000-0000-4000-8000-000000000001'$$,
  '23514', null, 'cleanup claim tokens require a claim timestamp'
);
select throws_ok(
  $$update private.share_snapshot_cleanup set claimed_at = '2026-01-01 00:00:00+00', claim_token = 'f6100000-0000-4000-8000-000000000001', object_deleted_at = '2026-01-01 00:01:00+00' where share_id = 'e6100000-0000-4000-8000-000000000001'$$,
  '23514', null, 'a deleted object cannot retain a cleanup claim'
);
select throws_ok(
  $$update private.share_snapshot_cleanup set attempt_count = -1 where share_id = 'e6100000-0000-4000-8000-000000000001'$$,
  '23514', null, 'cleanup attempts cannot be negative'
);
select throws_ok(
  $$update private.share_snapshot_cleanup set last_error_code = ' ' where share_id = 'e6100000-0000-4000-8000-000000000001'$$,
  '23514', null, 'cleanup error codes must be nonblank when present'
);

-- Every immutable difference is a non-disclosing conflict.
select is(
  (select count(*)::integer from (
    select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6100000-0000-4000-8000-000000000001','e6110000-0000-4000-8000-000000000001',decode('6101','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[{"garment_ref":"garment-a","url":"https://affiliate.example/a"},{"garment_ref":"garment-b","url":"https://affiliate.example/b"}]'::jsonb,'2026-01-01')
    union all select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6100000-0000-4000-8000-000000000001','e6100000-0000-4000-8000-000000000001',decode('61ff','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[{"garment_ref":"garment-a","url":"https://affiliate.example/a"},{"garment_ref":"garment-b","url":"https://affiliate.example/b"}]'::jsonb,'2026-01-01')
    union all select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6100000-0000-4000-8000-000000000001','e6100000-0000-4000-8000-000000000001',decode('6101','hex'),'v2','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[{"garment_ref":"garment-a","url":"https://affiliate.example/a"},{"garment_ref":"garment-b","url":"https://affiliate.example/b"}]'::jsonb,'2026-01-01')
    union all select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6100000-0000-4000-8000-000000000001','e6100000-0000-4000-8000-000000000001',decode('6101','hex'),'v1','2026-01-01 01:01:00+00','2026-01-02 00:00:00+00','[{"garment_ref":"garment-a","url":"https://affiliate.example/a"},{"garment_ref":"garment-b","url":"https://affiliate.example/b"}]'::jsonb,'2026-01-01')
    union all select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6100000-0000-4000-8000-000000000001','e6100000-0000-4000-8000-000000000001',decode('6101','hex'),'v1','2026-01-01 01:00:00+00','2026-01-03 00:00:00+00','[{"garment_ref":"garment-a","url":"https://affiliate.example/a"},{"garment_ref":"garment-b","url":"https://affiliate.example/b"}]'::jsonb,'2026-01-01')
    union all select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6100000-0000-4000-8000-000000000001','e6100000-0000-4000-8000-000000000001',decode('6101','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[{"garment_ref":"garment-a","url":"https://affiliate.example/changed"},{"garment_ref":"garment-b","url":"https://affiliate.example/b"}]'::jsonb,'2026-01-01')
    union all select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6100000-0000-4000-8000-000000000001','e6100000-0000-4000-8000-000000000001',decode('6101','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[{"garment_ref":"garment-b","url":"https://affiliate.example/b"},{"garment_ref":"garment-a","url":"https://affiliate.example/a"}]'::jsonb,'2026-01-01')
  ) as conflicts where decision = 'conflict' and share_id is null),
  7,
  'every immutable share, token, version, deadline, affiliate value, and order mismatch conflicts without disclosure'
);

-- Owner identity scopes replay; globally colliding share IDs and token hashes disclose nothing.
select results_eq(
  $$select * from private.create_share_operation('c6200000-0000-4000-8000-000000000002','d6100000-0000-4000-8000-000000000001','e6200000-0000-4000-8000-000000000002',decode('6201','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[]'::jsonb,'2026-01-01')$$,
  $$values ('created'::text, 'e6200000-0000-4000-8000-000000000002'::uuid)$$,
  'the same operation ID for another owner is isolated and creates that owner share'
);
select results_eq(
  $$select * from private.create_share_operation('c6200000-0000-4000-8000-000000000002','d6200000-0000-4000-8000-000000000002','e6100000-0000-4000-8000-000000000001',decode('62ff','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[]'::jsonb,'2026-01-01')$$,
  $$values ('conflict'::text, null::uuid)$$,
  'an unrelated existing share ID collision is non-disclosing'
);
select results_eq(
  $$select * from private.create_share_operation('c6200000-0000-4000-8000-000000000002','d6200000-0000-4000-8000-000000000003','e6210000-0000-4000-8000-000000000003',decode('6101','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[]'::jsonb,'2026-01-01')$$,
  $$values ('conflict'::text, null::uuid)$$,
  'an unrelated existing token hash collision is non-disclosing'
);
select is((select count(*)::integer from private.share_operations), 2, 'conflicts create no operation rows');

-- Structural failures are P0001 and leave every resource absent; an empty array is valid.
select throws_ok(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6300000-0000-4000-8000-000000000001','e6300000-0000-4000-8000-000000000001',decode('6301','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[{"garment_ref":"duplicate","url":"https://affiliate.example/a"},{"garment_ref":"duplicate","url":"https://affiliate.example/b"}]'::jsonb,'2026-01-01')$$,
  'P0001', null, 'duplicate affiliate garment references are invalid'
);
select throws_ok(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6300000-0000-4000-8000-000000000010','e6300000-0000-4000-8000-000000000010',decode('6310','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00',null::jsonb,'2026-01-01')$$,
  'P0001', null, 'affiliate links are required'
);
select throws_ok(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6300000-0000-4000-8000-000000000011','e6300000-0000-4000-8000-000000000011',decode('6311','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[{"garment_ref":1,"url":"https://affiliate.example/a"}]'::jsonb,'2026-01-01')$$,
  'P0001', null, 'affiliate garment references must be strings'
);
select throws_ok(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6300000-0000-4000-8000-000000000012','e6300000-0000-4000-8000-000000000012',decode('6312','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[{"garment_ref":true,"url":"https://affiliate.example/a"}]'::jsonb,'2026-01-01')$$,
  'P0001', null, 'affiliate garment references cannot be booleans'
);
select throws_ok(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6300000-0000-4000-8000-000000000013','e6300000-0000-4000-8000-000000000013',decode('6313','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[{"garment_ref":"garment","url":1}]'::jsonb,'2026-01-01')$$,
  'P0001', null, 'affiliate URLs must be strings'
);
select throws_ok(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6300000-0000-4000-8000-000000000014','e6300000-0000-4000-8000-000000000014',decode('6314','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[{"garment_ref":"garment","url":false}]'::jsonb,'2026-01-01')$$,
  'P0001', null, 'affiliate URLs cannot be booleans'
);
select throws_ok(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6300000-0000-4000-8000-000000000002','e6300000-0000-4000-8000-000000000002',decode('6302','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[{"garment_ref":" ","url":"https://affiliate.example/a","extra":"no"}]'::jsonb,'2026-01-01')$$,
  'P0001', null, 'blank or extra affiliate fields are invalid'
);
select throws_ok(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6300000-0000-4000-8000-000000000003','e6300000-0000-4000-8000-000000000003',decode('6303','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','{"garment_ref":"garment","url":"https://affiliate.example/a"}'::jsonb,'2026-01-01')$$,
  'P0001', null, 'affiliate input must be an array'
);
select throws_ok(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6300000-0000-4000-8000-000000000004','e6300000-0000-4000-8000-000000000004',decode('6304','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[{"garment_ref":"garment"}]'::jsonb,'2026-01-01')$$,
  'P0001', null, 'affiliate objects require both exact string fields'
);
select throws_ok(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6300000-0000-4000-8000-000000000020','e6300000-0000-4000-8000-000000000020',decode('6320','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[{"garment_ref":"synthetic-garment","other":"synthetic-value"}]'::jsonb,'2026-01-01')$$,
  'P0001', null, 'affiliate objects missing a URL are invalid even with exactly two keys'
);
select throws_ok(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6300000-0000-4000-8000-000000000021','e6300000-0000-4000-8000-000000000021',decode('6321','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[{"url":"https://affiliate.example/synthetic","other":"synthetic-value"}]'::jsonb,'2026-01-01')$$,
  'P0001', null, 'affiliate objects missing a garment reference are invalid even with exactly two keys'
);
select is(
  (select count(*)::integer from private.share_snapshots where share_id in ('e6300000-0000-4000-8000-000000000020', 'e6300000-0000-4000-8000-000000000021'))
  + (select count(*)::integer from private.share_operations where owner_id = 'c6100000-0000-4000-8000-000000000001' and operation_id in ('d6300000-0000-4000-8000-000000000020', 'd6300000-0000-4000-8000-000000000021'))
  + (select count(*)::integer from private.share_snapshot_affiliate_links where share_id in ('e6300000-0000-4000-8000-000000000020', 'e6300000-0000-4000-8000-000000000021'))
  + (select count(*)::integer from private.share_snapshot_cleanup where share_id in ('e6300000-0000-4000-8000-000000000020', 'e6300000-0000-4000-8000-000000000021')),
  0,
  'missing required affiliate fields leave no snapshot, operation, affiliate, or cleanup rows'
);
select throws_ok(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6300000-0000-4000-8000-000000000005','e6300000-0000-4000-8000-000000000005',''::bytea,'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[]'::jsonb,'2026-01-01')$$,
  'P0001', null, 'an empty token hash is invalid'
);
select throws_ok(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6300000-0000-4000-8000-000000000006','e6300000-0000-4000-8000-000000000006',decode('6306','hex'),' ','2026-01-01 00:00:00+00','2026-01-02 00:00:00+00','[]'::jsonb,'2026-01-01')$$,
  'P0001', null, 'a blank token key version and non-future upload deadline are invalid'
);
select throws_ok(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6300000-0000-4000-8000-000000000007','e6300000-0000-4000-8000-000000000007',decode('6307','hex'),' v1 ','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[]'::jsonb,'2026-01-01')$$,
  'P0001', null, 'a token key version must already be trimmed'
);
select throws_ok(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6300000-0000-4000-8000-000000000008','e6300000-0000-4000-8000-000000000008',decode('6308','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[{"garment_ref":" garment-trimmed ","url":"https://affiliate.example/a"}]'::jsonb,'2026-01-01')$$,
  'P0001', null, 'an affiliate garment reference must already be trimmed'
);
select throws_ok(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6300000-0000-4000-8000-000000000009','e6300000-0000-4000-8000-000000000009',decode('6309','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[{"garment_ref":"garment-trimmed","url":" https://affiliate.example/a "}]'::jsonb,'2026-01-01')$$,
  'P0001', null, 'an affiliate URL must already be trimmed'
);
select throws_ok(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6300000-0000-4000-8000-000000000015','e6300000-0000-4000-8000-000000000015',null::bytea,'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[]'::jsonb,'2026-01-01')$$,
  'P0001', null, 'a token hash is required'
);
select throws_ok(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6300000-0000-4000-8000-000000000016','e6300000-0000-4000-8000-000000000016',decode('6316','hex'),null::text,'2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[]'::jsonb,'2026-01-01')$$,
  'P0001', null, 'a token key version is required'
);
select throws_ok(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6300000-0000-4000-8000-000000000017','e6300000-0000-4000-8000-000000000017',decode('6317','hex'),'v1',null::timestamptz,'2026-01-02 00:00:00+00','[]'::jsonb,'2026-01-01')$$,
  'P0001', null, 'an upload deadline is required'
);
select throws_ok(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6300000-0000-4000-8000-000000000018','e6300000-0000-4000-8000-000000000018',decode('6318','hex'),'v1','2026-01-01 01:00:00+00',null::timestamptz,'[]'::jsonb,'2026-01-01')$$,
  'P0001', null, 'an expiry deadline is required'
);
select throws_ok(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6300000-0000-4000-8000-000000000019','e6300000-0000-4000-8000-000000000019',decode('6319','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[]'::jsonb,null::timestamptz)$$,
  'P0001', null, 'the request time is required'
);
select is(
  (select count(*)::integer from private.share_snapshots where share_id in ('e6300000-0000-4000-8000-000000000001', 'e6300000-0000-4000-8000-000000000002', 'e6300000-0000-4000-8000-000000000003', 'e6300000-0000-4000-8000-000000000004', 'e6300000-0000-4000-8000-000000000005', 'e6300000-0000-4000-8000-000000000006', 'e6300000-0000-4000-8000-000000000007', 'e6300000-0000-4000-8000-000000000008', 'e6300000-0000-4000-8000-000000000009', 'e6300000-0000-4000-8000-000000000010', 'e6300000-0000-4000-8000-000000000011', 'e6300000-0000-4000-8000-000000000012', 'e6300000-0000-4000-8000-000000000013', 'e6300000-0000-4000-8000-000000000014', 'e6300000-0000-4000-8000-000000000015', 'e6300000-0000-4000-8000-000000000016', 'e6300000-0000-4000-8000-000000000017', 'e6300000-0000-4000-8000-000000000018', 'e6300000-0000-4000-8000-000000000019')),
  0,
  'structural failures roll back snapshots and all dependent resources'
);
select results_eq(
  $$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6400000-0000-4000-8000-000000000001','e6400000-0000-4000-8000-000000000001',decode('6401','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[]'::jsonb,'2026-01-01')$$,
  $$values ('created'::text, 'e6400000-0000-4000-8000-000000000001'::uuid)$$,
  'an empty affiliate array is a valid creation request'
);
select is((select count(*)::integer from private.share_snapshot_affiliate_links where share_id = 'e6400000-0000-4000-8000-000000000001'), 0, 'empty affiliates persist no link rows');

-- The T06 cleanup row follows the snapshot lifecycle through all dependent tables.
delete from private.share_snapshots where share_id = 'e6400000-0000-4000-8000-000000000001';
select is(
  (select count(*)::integer from private.share_operations where share_id = 'e6400000-0000-4000-8000-000000000001')
  + (select count(*)::integer from private.share_snapshot_affiliate_links where share_id = 'e6400000-0000-4000-8000-000000000001')
  + (select count(*)::integer from private.share_snapshot_cleanup where share_id = 'e6400000-0000-4000-8000-000000000001'),
  0,
  'deleting a snapshot cascades its operation, affiliates, and cleanup bookkeeping'
);

reset role;
select set_config('request.jwt.claims', '{}', true);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"c6100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select throws_ok($$select * from private.share_operations$$, '42501', null, 'authenticated clients cannot read share operations');
select throws_ok($$select * from private.create_share_operation('c6100000-0000-4000-8000-000000000001','d6500000-0000-4000-8000-000000000001','e6500000-0000-4000-8000-000000000001',decode('6501','hex'),'v1','2026-01-01 01:00:00+00','2026-01-02 00:00:00+00','[]'::jsonb,'2026-01-01')$$, '42501', null, 'authenticated clients cannot invoke share creation');
reset role;

select * from finish();

rollback;
