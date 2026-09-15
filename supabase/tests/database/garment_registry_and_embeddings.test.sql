begin;

select no_plan();

-- Schema, keys, privacy, and vector representation.
select has_extension('vector', 'pgvector is installed');
select has_table('public', 'garment_registry', 'public.garment_registry exists');
select has_table(
  'private',
  'garment_text_embeddings',
  'private.garment_text_embeddings exists'
);
select ok(
  to_regprocedure('private.enforce_active_garment_limit()') is not null,
  'active garment limit trigger function has the required signature'
);

select is(
  (
    select array_agg(column_name::text order by column_name)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'garment_registry'
  ),
  array[
    'archived_at',
    'created_at',
    'garment_id',
    'status',
    'updated_at',
    'user_id'
  ]::text[],
  'garment_registry stores only opaque identity, owner, lifecycle, and timestamps'
);
select is(
  (
    select array_agg(column_name::text order by column_name)
    from information_schema.columns
    where table_schema = 'private'
      and table_name = 'garment_text_embeddings'
  ),
  array[
    'attributes',
    'attributes_schema_version',
    'created_at',
    'embedding',
    'embedding_model',
    'embedding_revision',
    'garment_id'
  ]::text[],
  'embedding storage contains only versioned textual attributes and a vector'
);
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema in ('public', 'private')
      and table_name in ('garment_registry', 'garment_text_embeddings')
      and column_name in (
        'image', 'image_url', 'image_data', 'blob', 'caption', 'display_name',
        'email', 'gps', 'latitude', 'longitude', 'location', 'local_database'
      )
  ),
  'garment tables contain no image, caption, local database, GPS, or PII columns'
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
    where constraint_record.conrelid = 'public.garment_registry'::regclass
      and constraint_record.contype = 'p'
  ),
  array['garment_id']::text[],
  'garment UUID is the registry primary key'
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
    where constraint_record.conrelid = 'private.garment_text_embeddings'::regclass
      and constraint_record.contype = 'p'
  ),
  array['garment_id', 'embedding_model', 'embedding_revision']::text[],
  'embedding model and revision version each garment vector'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.garment_registry'::regclass
      and confrelid = 'auth.users'::regclass
      and contype = 'f'
  ),
  'garment registry owners reference Auth users'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'private.garment_text_embeddings'::regclass
      and confrelid = 'public.garment_registry'::regclass
      and contype = 'f'
  ),
  'embeddings reference the garment registry'
);
select ok(
  (
    select attribute.atttypid = 'extensions.vector'::regtype
      and attribute.atttypmod = -1
    from pg_attribute as attribute
    where attribute.attrelid = 'private.garment_text_embeddings'::regclass
      and attribute.attname = 'embedding'
      and not attribute.attisdropped
  ),
  'embedding uses an unconstrained extensions.vector type'
);
select ok(
  not exists (
    select 1
    from pg_indexes
    where schemaname = 'private'
      and tablename = 'garment_text_embeddings'
      and (
        indexdef ilike '% using hnsw %'
        or indexdef ilike '% using ivfflat %'
      )
  ),
  'embedding storage has no vector ANN index'
);
select ok(
  exists (
    select 1
    from pg_index as index_record
    join pg_class as index_relation
      on index_relation.oid = index_record.indexrelid
    join pg_am as access_method
      on access_method.oid = index_relation.relam
    where index_record.indrelid = 'public.garment_registry'::regclass
      and index_record.indisvalid
      and index_record.indisready
      and index_record.indnkeyatts >= 2
      and access_method.amname = 'btree'
      and pg_get_indexdef(index_record.indexrelid, 1, true) = 'user_id'
      and pg_get_indexdef(index_record.indexrelid, 2, true) = 'status'
  ),
  'garment_registry has a valid btree index led by user_id and status'
);

-- RLS and least-privilege access.
select ok(
  (
    select relrowsecurity and relforcerowsecurity
    from pg_class
    where oid = 'public.garment_registry'::regclass
  ),
  'garment_registry has RLS enabled and forced'
);
select ok(
  (
    select relrowsecurity and relforcerowsecurity
    from pg_class
    where oid = 'private.garment_text_embeddings'::regclass
  ),
  'garment_text_embeddings has RLS enabled and forced'
);
select ok(
  not exists (
    select 1
    from (
      values
        ('SELECT'::text, true, false),
        ('INSERT'::text, false, true),
        ('UPDATE'::text, true, true),
        ('DELETE'::text, true, false)
    ) as required_policy(command, needs_using, needs_check)
    where not exists (
      select 1
      from pg_policies as policy
      where policy.schemaname = 'public'
        and policy.tablename = 'garment_registry'
        and policy.cmd in (required_policy.command, 'ALL')
        and 'authenticated'::name = any (policy.roles)
        and (not required_policy.needs_using or policy.qual is not null)
        and (not required_policy.needs_check or policy.with_check is not null)
    )
  ),
  'garment_registry has authenticated owner-policy coverage for every CRUD command'
);
select is(
  (
    select count(*)::integer
    from pg_policies
    where schemaname = 'private'
      and tablename = 'garment_text_embeddings'
  ),
  0,
  'private embeddings have no client policies'
);
select ok(
  has_table_privilege('authenticated', 'public.garment_registry', 'SELECT')
  and has_table_privilege('authenticated', 'public.garment_registry', 'INSERT')
  and has_table_privilege('authenticated', 'public.garment_registry', 'UPDATE')
  and has_table_privilege('authenticated', 'public.garment_registry', 'DELETE')
  and not has_table_privilege('authenticated', 'public.garment_registry', 'TRUNCATE')
  and not has_table_privilege('authenticated', 'public.garment_registry', 'REFERENCES')
  and not has_table_privilege('authenticated', 'public.garment_registry', 'TRIGGER'),
  'authenticated receives only CRUD privileges on garment_registry'
);
select ok(
  not has_table_privilege('anon', 'public.garment_registry', 'SELECT')
  and not has_table_privilege('anon', 'public.garment_registry', 'INSERT')
  and not has_table_privilege('anon', 'public.garment_registry', 'UPDATE')
  and not has_table_privilege('anon', 'public.garment_registry', 'DELETE'),
  'anon has no garment_registry privileges'
);
select ok(
  not has_table_privilege('anon', 'private.garment_text_embeddings', 'SELECT')
  and not has_table_privilege('authenticated', 'private.garment_text_embeddings', 'SELECT')
  and not has_table_privilege('anon', 'private.garment_text_embeddings', 'INSERT')
  and not has_table_privilege('authenticated', 'private.garment_text_embeddings', 'INSERT')
  and not has_table_privilege('anon', 'private.garment_text_embeddings', 'UPDATE')
  and not has_table_privilege('authenticated', 'private.garment_text_embeddings', 'UPDATE')
  and not has_table_privilege('anon', 'private.garment_text_embeddings', 'DELETE')
  and not has_table_privilege('authenticated', 'private.garment_text_embeddings', 'DELETE'),
  'client roles have no private embedding privileges'
);
select ok(
  has_table_privilege('service_role', 'private.garment_text_embeddings', 'SELECT')
  and has_table_privilege('service_role', 'private.garment_text_embeddings', 'INSERT')
  and has_table_privilege('service_role', 'private.garment_text_embeddings', 'UPDATE')
  and has_table_privilege('service_role', 'private.garment_text_embeddings', 'DELETE')
  and not has_table_privilege('service_role', 'private.garment_text_embeddings', 'TRUNCATE')
  and not has_table_privilege('service_role', 'private.garment_text_embeddings', 'REFERENCES')
  and not has_table_privilege('service_role', 'private.garment_text_embeddings', 'TRIGGER'),
  'service_role receives only private embedding CRUD privileges'
);

-- The privileged trigger is callable only through the table lifecycle.
select ok(
  (
    select procedure.prosecdef
      and exists (
        select 1
        from unnest(coalesce(procedure.proconfig, array[]::text[])) as setting
        where setting in ('search_path=', 'search_path=""')
      )
    from pg_proc as procedure
    where procedure.oid = 'private.enforce_active_garment_limit()'::regprocedure
  ),
  'active garment limit trigger is security definer with an empty search path'
);
select ok(
  not has_function_privilege('anon', 'private.enforce_active_garment_limit()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'private.enforce_active_garment_limit()', 'EXECUTE')
  and not has_function_privilege('service_role', 'private.enforce_active_garment_limit()', 'EXECUTE'),
  'no API role can directly execute the active garment limit trigger'
);
select ok(
  pg_get_functiondef('private.enforce_active_garment_limit()'::regprocedure)
    ilike '%pg_advisory_xact_lock%',
  'active garment quota checks use a transaction-scoped advisory lock'
);
select ok(
  exists (
    select 1
    from pg_trigger as trigger
    where trigger.tgrelid = 'public.garment_registry'::regclass
      and trigger.tgfoid = 'private.enforce_active_garment_limit()'::regprocedure
      and not trigger.tgisinternal
      and (trigger.tgtype & 4) = 4
  ),
  'garment_registry inserts invoke the active garment limit trigger'
);
select ok(
  exists (
    select 1
    from pg_trigger as trigger
    where trigger.tgrelid = 'public.garment_registry'::regclass
      and trigger.tgfoid = 'private.enforce_active_garment_limit()'::regprocedure
      and not trigger.tgisinternal
      and (trigger.tgtype & 16) = 16
  ),
  'garment_registry updates invoke the active garment limit trigger'
);

-- Synthetic users and external managed configuration.
insert into auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (
    '41000000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'garment-owner@example.test',
    '',
    '2026-01-01 00:00:00+00',
    '{}',
    '{}',
    '2026-01-01 00:00:00+00',
    '2026-01-01 00:00:00+00'
  ),
  (
    '42000000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'other-garment-owner@example.test',
    '',
    '2026-01-01 00:00:00+00',
    '{}',
    '{}',
    '2026-01-01 00:00:00+00',
    '2026-01-01 00:00:00+00'
  );

insert into private.product_config (key, value, updated_at)
values
  ('limits.free.active_garments', '2'::jsonb, '2026-01-01 00:00:00+00'),
  ('entitlements.premium.key', '"premium.synthetic"'::jsonb, '2026-01-01 00:00:00+00');

-- Owner CRUD, archive invariants, quota, and reactivation.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"41000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

select lives_ok(
  $$insert into public.garment_registry (
      garment_id, user_id, status, archived_at, created_at, updated_at
    ) values (
      '51000000-0000-4000-8000-000000000001',
      '41000000-0000-4000-8000-000000000001',
      'active', null,
      '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00'
    )$$,
  'an owner can insert their first active garment'
);
select lives_ok(
  $$insert into public.garment_registry (garment_id, user_id, status)
    values (
      '51000000-0000-4000-8000-000000000002',
      '41000000-0000-4000-8000-000000000001',
      'active'
    )$$,
  'an owner can insert active garments up to the configured free limit'
);
select throws_ok(
  $$insert into public.garment_registry (garment_id, user_id, status)
    values (
      '51000000-0000-4000-8000-000000000003',
      '41000000-0000-4000-8000-000000000001',
      'active'
    )$$,
  'P0001',
  null,
  'an active garment above the configured free limit is rejected'
);
select lives_ok(
  $$update public.garment_registry
    set status = 'archived', archived_at = '2026-02-01 00:00:00+00'
    where garment_id = '51000000-0000-4000-8000-000000000001'$$,
  'an owner can archive a garment without changing its identity'
);
select cmp_ok(
  (
    select updated_at
    from public.garment_registry
    where garment_id = '51000000-0000-4000-8000-000000000001'
  ),
  '>',
  '2026-01-01 00:00:00+00'::timestamptz,
  'updating a garment lifecycle advances updated_at'
);
select is(
  (
    select garment_id
    from public.garment_registry
    where garment_id = '51000000-0000-4000-8000-000000000001'
      and status = 'archived'
      and archived_at = '2026-02-01 00:00:00+00'
  ),
  '51000000-0000-4000-8000-000000000001'::uuid,
  'archiving preserves the garment UUID and records the archive timestamp'
);
select lives_ok(
  $$insert into public.garment_registry (garment_id, user_id, status)
    values (
      '51000000-0000-4000-8000-000000000003',
      '41000000-0000-4000-8000-000000000001',
      'active'
    )$$,
  'an archived garment does not consume an active quota slot'
);
select throws_ok(
  $$update public.garment_registry
    set status = 'active', archived_at = null
    where garment_id = '51000000-0000-4000-8000-000000000001'$$,
  'P0001',
  null,
  'reactivation is rejected when the configured active quota is full'
);
select lives_ok(
  $$update public.garment_registry
    set status = 'archived', archived_at = '2026-02-02 00:00:00+00'
    where garment_id = '51000000-0000-4000-8000-000000000003'$$,
  'archiving frees an active quota slot'
);
select lives_ok(
  $$update public.garment_registry
    set status = 'active', archived_at = null
    where garment_id = '51000000-0000-4000-8000-000000000001'$$,
  'reactivation succeeds after an active quota slot is freed'
);
select throws_ok(
  $$insert into public.garment_registry (garment_id, user_id, status, archived_at)
    values (
      '51000000-0000-4000-8000-000000000004',
      '41000000-0000-4000-8000-000000000001',
      'active', '2026-02-01 00:00:00+00'
    )$$,
  '23514',
  null,
  'an active garment cannot have an archive timestamp'
);
select throws_ok(
  $$insert into public.garment_registry (garment_id, user_id, status, archived_at)
    values (
      '51000000-0000-4000-8000-000000000004',
      '41000000-0000-4000-8000-000000000001',
      'archived', null
    )$$,
  '23514',
  null,
  'an archived garment requires an archive timestamp'
);
select throws_ok(
  $$insert into public.garment_registry (garment_id, user_id, status, archived_at)
    values (
      '51000000-0000-4000-8000-000000000004',
      '41000000-0000-4000-8000-000000000001',
      'pending', null
    )$$,
  '23514',
  null,
  'garment status rejects values outside active and archived'
);
select lives_ok(
  $$insert into public.garment_registry (garment_id, user_id, status, archived_at)
    values (
      '51000000-0000-4000-8000-000000000005',
      '41000000-0000-4000-8000-000000000001',
      'archived', '2026-02-01 00:00:00+00'
    )$$,
  'an owner can insert an archived garment without consuming quota'
);
select lives_ok(
  $$delete from public.garment_registry
    where garment_id = '51000000-0000-4000-8000-000000000005'$$,
  'an owner can delete their garment registry row'
);
select throws_ok(
  $$update public.garment_registry
    set user_id = '42000000-0000-4000-8000-000000000002'
    where garment_id = '51000000-0000-4000-8000-000000000002'$$,
  '42501',
  null,
  'an owner cannot reassign a garment to another user'
);
select throws_ok(
  $$insert into public.garment_registry (garment_id, user_id, status)
    values (
      '51000000-0000-4000-8000-000000000006',
      '42000000-0000-4000-8000-000000000002',
      'active'
    )$$,
  '42501',
  null,
  'an authenticated user cannot insert a garment for another user'
);

reset role;
select set_config('request.jwt.claims', '{}', true);

-- The second owner creates a row used to prove cross-owner isolation.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"42000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
insert into public.garment_registry (garment_id, user_id, status)
values (
  '52000000-0000-4000-8000-000000000001',
  '42000000-0000-4000-8000-000000000002',
  'active'
);
insert into public.garment_registry (garment_id, user_id, status)
values (
  '52000000-0000-4000-8000-000000000009',
  '42000000-0000-4000-8000-000000000002',
  'active'
);

reset role;
select set_config('request.jwt.claims', '{}', true);
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"41000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select is(
  (select count(*)::integer from public.garment_registry),
  3,
  'an owner can select only their registry rows'
);
select lives_ok(
  $$update public.garment_registry
    set status = 'archived', archived_at = '2026-02-03 00:00:00+00'
    where garment_id = '52000000-0000-4000-8000-000000000001'$$,
  'a cross-owner update is filtered by RLS'
);
select lives_ok(
  $$delete from public.garment_registry
    where garment_id = '52000000-0000-4000-8000-000000000001'$$,
  'a cross-owner delete is filtered by RLS'
);
select throws_ok(
  $$insert into public.garment_registry (garment_id, user_id, status)
    values (
      '52000000-0000-4000-8000-000000000010',
      '42000000-0000-4000-8000-000000000002',
      'active'
    )$$,
  '42501', null,
  'ownership denial precedes quota evaluation for another owner at their limit'
);

reset role;
select set_config('request.jwt.claims', '{}', true);
select is(
  (
    select status
    from public.garment_registry
    where garment_id = '52000000-0000-4000-8000-000000000001'
  ),
  'active',
  'cross-owner update did not change the other owner row'
);
select is(
  (
    select count(*)::integer
    from public.garment_registry
    where garment_id = '52000000-0000-4000-8000-000000000001'
  ),
  1,
  'cross-owner delete did not remove the other owner row'
);

-- Anonymous callers cannot use the registry.
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select throws_ok(
  $$select * from public.garment_registry$$,
  '42501', null,
  'anonymous users cannot select registry rows'
);
select throws_ok(
  $$insert into public.garment_registry (garment_id, user_id, status)
    values (
      '53000000-0000-4000-8000-000000000001',
      '41000000-0000-4000-8000-000000000001',
      'active'
    )$$,
  '42501', null,
  'anonymous users cannot insert registry rows'
);
select throws_ok(
  $$update public.garment_registry set status = 'active'$$,
  '42501', null,
  'anonymous users cannot update registry rows'
);
select throws_ok(
  $$delete from public.garment_registry$$,
  '42501', null,
  'anonymous users cannot delete registry rows'
);
reset role;
select set_config('request.jwt.claims', '{}', true);

-- Premium bypass applies only while the configured entitlement is active.
insert into private.user_entitlements (
  user_id, entitlement_key, status, valid_from, valid_until
)
values (
  '41000000-0000-4000-8000-000000000001',
  'premium.synthetic',
  'active',
  '-infinity',
  null
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"41000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select lives_ok(
  $$insert into public.garment_registry (garment_id, user_id, status)
    values (
      '51000000-0000-4000-8000-000000000007',
      '41000000-0000-4000-8000-000000000001',
      'active'
    )$$,
  'an active premium entitlement bypasses the free active-garment count'
);
reset role;
select set_config('request.jwt.claims', '{}', true);

update private.user_entitlements
set status = 'inactive'
where user_id = '41000000-0000-4000-8000-000000000001'
  and entitlement_key = 'premium.synthetic';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"41000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select throws_ok(
  $$insert into public.garment_registry (garment_id, user_id, status)
    values (
      '51000000-0000-4000-8000-000000000008',
      '41000000-0000-4000-8000-000000000001',
      'active'
    )$$,
  'P0001', null,
  'an inactive premium entitlement does not bypass the free limit'
);
reset role;
select set_config('request.jwt.claims', '{}', true);

-- Missing or invalid required managed configuration fails closed.
delete from private.product_config where key = 'entitlements.premium.key';
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"42000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select throws_ok(
  $$insert into public.garment_registry (garment_id, user_id, status)
    values (
      '51000000-0000-4000-8000-000000000009',
      '41000000-0000-4000-8000-000000000001',
      'active'
    )$$,
  '42501', null,
  'ownership denial precedes lookup of missing managed configuration'
);
select throws_ok(
  $$insert into public.garment_registry (garment_id, user_id, status)
    values (
      '52000000-0000-4000-8000-000000000002',
      '42000000-0000-4000-8000-000000000002',
      'active'
    )$$,
  'P0001',
  'CONFIGURATION_ERROR: entitlements.premium.key',
  'a missing premium entitlement key fails closed'
);
reset role;
select set_config('request.jwt.claims', '{}', true);

insert into private.product_config (key, value)
values ('entitlements.premium.key', '""'::jsonb);
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"42000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select throws_ok(
  $$insert into public.garment_registry (garment_id, user_id, status)
    values (
      '51000000-0000-4000-8000-000000000010',
      '41000000-0000-4000-8000-000000000001',
      'active'
    )$$,
  '42501', null,
  'ownership denial precedes validation of invalid managed configuration'
);
select throws_ok(
  $$insert into public.garment_registry (garment_id, user_id, status)
    values (
      '52000000-0000-4000-8000-000000000002',
      '42000000-0000-4000-8000-000000000002',
      'active'
    )$$,
  'P0001',
  'CONFIGURATION_ERROR: entitlements.premium.key',
  'an empty premium entitlement key fails closed'
);
reset role;
select set_config('request.jwt.claims', '{}', true);

update private.product_config
set value = '"premium.synthetic"'::jsonb
where key = 'entitlements.premium.key';
delete from private.product_config where key = 'limits.free.active_garments';
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"42000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select throws_ok(
  $$insert into public.garment_registry (garment_id, user_id, status)
    values (
      '52000000-0000-4000-8000-000000000002',
      '42000000-0000-4000-8000-000000000002',
      'active'
    )$$,
  'P0001',
  'CONFIGURATION_ERROR: limits.free.active_garments',
  'a missing free active-garment limit fails closed'
);
reset role;
select set_config('request.jwt.claims', '{}', true);

insert into private.product_config (key, value)
values ('limits.free.active_garments', '0'::jsonb);
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"42000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select throws_ok(
  $$insert into public.garment_registry (garment_id, user_id, status)
    values (
      '52000000-0000-4000-8000-000000000002',
      '42000000-0000-4000-8000-000000000002',
      'active'
    )$$,
  'P0001',
  'CONFIGURATION_ERROR: limits.free.active_garments',
  'a non-positive free active-garment limit fails closed'
);
reset role;
select set_config('request.jwt.claims', '{}', true);

select is(
  (
    select count(*)::integer
    from public.garment_registry
    where garment_id = '52000000-0000-4000-8000-000000000002'
  ),
  0,
  'failed configuration checks leave no registry row behind'
);

-- Private embeddings accept generic JSON and independently dimensioned vectors.
update private.product_config
set value = '2'::jsonb
where key = 'limits.free.active_garments';

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select lives_ok(
  $$insert into private.garment_text_embeddings (
      garment_id, embedding_model, embedding_revision,
      attributes_schema_version, attributes, embedding, created_at
    ) values (
      '51000000-0000-4000-8000-000000000002',
      'synthetic-model-a', 1, 1,
      '{"freeform_descriptor":"woven"}'::jsonb,
      '[0.1,0.2,0.3]'::extensions.vector,
      '2026-01-01 00:00:00+00'
    )$$,
  'service_role can store a versioned textual embedding'
);
select lives_ok(
  $$insert into private.garment_text_embeddings (
      garment_id, embedding_model, embedding_revision,
      attributes_schema_version, attributes, embedding, created_at
    ) values (
      '51000000-0000-4000-8000-000000000002',
      'synthetic-model-b', 1, 2,
      '{"new_provider_attribute":{"nested":true}}'::jsonb,
      '[0.4,0.5]'::extensions.vector,
      '2026-01-02 00:00:00+00'
    )$$,
  'unconstrained vectors allow different model dimensions and generic attributes'
);
select is(
  (
    select count(*)::integer
    from private.garment_text_embeddings
    where garment_id = '51000000-0000-4000-8000-000000000002'
  ),
  2,
  'distinct model versions coexist for one garment UUID'
);
select lives_ok(
  $$update private.garment_text_embeddings
    set attributes = '{"freeform_descriptor":"knitted"}'::jsonb
    where garment_id = '51000000-0000-4000-8000-000000000002'
      and embedding_model = 'synthetic-model-a'
      and embedding_revision = 1$$,
  'service_role can update private embedding attributes'
);
select throws_ok(
  $$insert into private.garment_text_embeddings (
      garment_id, embedding_model, embedding_revision,
      attributes_schema_version, attributes, embedding
    ) values (
      '51000000-0000-4000-8000-000000000002',
      'synthetic-model-a', 1, 1, '{}'::jsonb,
      '[0.1,0.2,0.3]'::extensions.vector
    )$$,
  '23505', null,
  'duplicate garment model revisions are rejected'
);
select throws_ok(
  $$insert into private.garment_text_embeddings (
      garment_id, embedding_model, embedding_revision,
      attributes_schema_version, attributes, embedding
    ) values (
      '51000000-0000-4000-8000-000000000002',
      '', 2, 1, '{}'::jsonb, '[0.1]'::extensions.vector
    )$$,
  '23514', null,
  'embedding model must be non-empty'
);
select throws_ok(
  $$insert into private.garment_text_embeddings (
      garment_id, embedding_model, embedding_revision,
      attributes_schema_version, attributes, embedding
    ) values (
      '51000000-0000-4000-8000-000000000002',
      'synthetic-model-a', 0, 1, '{}'::jsonb,
      '[0.1]'::extensions.vector
    )$$,
  '23514', null,
  'embedding revision must be positive'
);
select throws_ok(
  $$insert into private.garment_text_embeddings (
      garment_id, embedding_model, embedding_revision,
      attributes_schema_version, attributes, embedding
    ) values (
      '51000000-0000-4000-8000-000000000002',
      'synthetic-model-a', 2, 0, '{}'::jsonb,
      '[0.1]'::extensions.vector
    )$$,
  '23514', null,
  'attributes schema version must be positive'
);
select throws_ok(
  $$insert into private.garment_text_embeddings (
      garment_id, embedding_model, embedding_revision,
      attributes_schema_version, attributes, embedding
    ) values (
      '51000000-0000-4000-8000-000000000002',
      'synthetic-model-a', 2, 1, '[]'::jsonb,
      '[0.1]'::extensions.vector
    )$$,
  '23514', null,
  'embedding attributes must be a JSON object'
);
select lives_ok(
  $$delete from private.garment_text_embeddings
    where garment_id = '51000000-0000-4000-8000-000000000002'
      and embedding_model = 'synthetic-model-b'
      and embedding_revision = 1$$,
  'service_role can delete a private embedding version'
);
reset role;
select set_config('request.jwt.claims', '{}', true);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"41000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select throws_ok(
  $$select * from private.garment_text_embeddings$$,
  '42501', null,
  'authenticated clients cannot read private embeddings'
);
reset role;
select set_config('request.jwt.claims', '{}', true);

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select throws_ok(
  $$select * from private.garment_text_embeddings$$,
  '42501', null,
  'anonymous clients cannot read private embeddings'
);
reset role;
select set_config('request.jwt.claims', '{}', true);

select * from finish();

rollback;
