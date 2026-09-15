begin;

select no_plan();

-- Exact private persistence contract and privacy absences.
select is(
  (
    select array_agg(table_name::text order by table_name)
    from information_schema.tables
    where table_schema = 'private'
      and table_name in (
        'idempotency_operations', 'api_cache_entries',
        'api_cache_leases', 'rate_limit_windows'
      )
  ),
  array[
    'api_cache_entries', 'api_cache_leases',
    'idempotency_operations', 'rate_limit_windows'
  ]::text[],
  'all coordination tables exist only in the private schema'
);
select is(
  (
    select count(*)::integer
    from information_schema.tables
    where table_schema = 'public'
      and table_name in (
        'idempotency_operations', 'api_cache_entries',
        'api_cache_leases', 'rate_limit_windows'
      )
  ),
  0,
  'coordination primitives create no public tables'
);
select is(
  (
    select array_agg(column_name::text order by column_name)
    from information_schema.columns
    where table_schema = 'private' and table_name = 'idempotency_operations'
  ),
  array[
    'action', 'attempt_id', 'completed_at', 'created_at', 'expires_at',
    'idempotency_key_fingerprint', 'request_fingerprint', 'response_body',
    'response_status', 'state', 'updated_at', 'user_id'
  ]::text[],
  'idempotency storage has the exact minimal columns'
);
select is(
  (
    select array_agg(column_name::text order by column_name)
    from information_schema.columns
    where table_schema = 'private' and table_name = 'api_cache_entries'
  ),
  array[
    'cache_key_fingerprint', 'created_at', 'fresh_until', 'response_body',
    'stale_until', 'updated_at'
  ]::text[],
  'cache entry storage has the exact minimal columns'
);
select is(
  (
    select array_agg(column_name::text order by column_name)
    from information_schema.columns
    where table_schema = 'private' and table_name = 'api_cache_leases'
  ),
  array[
    'cache_key_fingerprint', 'created_at', 'holder_id', 'lease_until', 'updated_at'
  ]::text[],
  'cache lease storage has the exact minimal columns'
);
select is(
  (
    select array_agg(column_name::text order by column_name)
    from information_schema.columns
    where table_schema = 'private' and table_name = 'rate_limit_windows'
  ),
  array[
    'action', 'created_at', 'limit_value', 'request_count', 'updated_at',
    'user_id', 'window_ends_at', 'window_seconds', 'window_started_at'
  ]::text[],
  'rate limit storage has the exact minimal columns'
);
select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'private'
      and table_name in (
        'idempotency_operations', 'api_cache_entries',
        'api_cache_leases', 'rate_limit_windows'
      )
      and column_name in (
        'raw_key', 'idempotency_key', 'cache_key', 'canonical_request',
        'request_body', 'headers', 'provider_payload', 'email', 'display_name',
        'device_id', 'location', 'latitude', 'longitude'
      )
  ),
  'coordination storage contains no raw keys, provider data, location, device ID, or PII'
);
select ok(
  (
    select bool_and(data_type = 'bytea')
    from information_schema.columns
    where table_schema = 'private'
      and column_name in (
        'idempotency_key_fingerprint', 'request_fingerprint',
        'cache_key_fingerprint'
      )
  ),
  'all persisted request and cache identities are opaque bytea fingerprints'
);

-- Primary keys and cleanup indexes.
select is(
  (
    select array_agg(attribute.attname::text order by key_column.ordinality)
    from pg_constraint as constraint_record
    cross join lateral unnest(constraint_record.conkey)
      with ordinality as key_column(attribute_number, ordinality)
    join pg_attribute as attribute
      on attribute.attrelid = constraint_record.conrelid
      and attribute.attnum = key_column.attribute_number
    where constraint_record.conrelid = 'private.idempotency_operations'::regclass
      and constraint_record.contype = 'p'
  ),
  array['user_id', 'action', 'idempotency_key_fingerprint']::text[],
  'idempotency identity is unique per user, action, and opaque key fingerprint'
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
    where constraint_record.conrelid = 'private.rate_limit_windows'::regclass
      and constraint_record.contype = 'p'
  ),
  array['user_id', 'action', 'window_started_at']::text[],
  'rate buckets are unique per user, action, and fixed window start'
);
select ok(
  not exists (
    select 1
    from (
      values
        ('idempotency_operations'::text, 'expires_at'::text),
        ('api_cache_entries', 'stale_until'),
        ('api_cache_leases', 'lease_until'),
        ('rate_limit_windows', 'window_ends_at')
    ) as required_index(table_name, leading_column)
    where not exists (
      select 1
      from pg_index as index_record
      join pg_class as table_relation on table_relation.oid = index_record.indrelid
      join pg_namespace as namespace on namespace.oid = table_relation.relnamespace
      where namespace.nspname = 'private'
        and table_relation.relname = required_index.table_name
        and index_record.indisvalid
        and index_record.indisready
        and pg_get_indexdef(index_record.indexrelid, 1, true) = required_index.leading_column
    )
  ),
  'every coordination resource has a valid cleanup-deadline index'
);

-- RLS, grants, and function hardening.
select ok(
  (
    select bool_and(class.relrowsecurity and class.relforcerowsecurity)
    from pg_class as class
    join pg_namespace as namespace on namespace.oid = class.relnamespace
    where namespace.nspname = 'private'
      and class.relname in (
        'idempotency_operations', 'api_cache_entries',
        'api_cache_leases', 'rate_limit_windows'
      )
  ),
  'all coordination tables have RLS enabled and forced'
);
select is(
  (
    select count(*)::integer
    from pg_policies
    where schemaname = 'private'
      and tablename in (
        'idempotency_operations', 'api_cache_entries',
        'api_cache_leases', 'rate_limit_windows'
      )
  ),
  0,
  'coordination tables have no client RLS policies'
);
select ok(
  not exists (
    select 1
    from (
      values
        ('idempotency_operations'::text), ('api_cache_entries'),
        ('api_cache_leases'), ('rate_limit_windows')
    ) as private_table(table_name)
    cross join (
      values ('SELECT'::text), ('INSERT'), ('UPDATE'), ('DELETE')
    ) as required_privilege(privilege_name)
    where not has_table_privilege(
      'service_role',
      format('private.%I', private_table.table_name),
      required_privilege.privilege_name
    )
  ),
  'service_role has CRUD on every private coordination table'
);
select ok(
  not exists (
    select 1
    from (
      values
        ('idempotency_operations'::text), ('api_cache_entries'),
        ('api_cache_leases'), ('rate_limit_windows')
    ) as private_table(table_name)
    cross join (values ('anon'::text), ('authenticated')) as client(role_name)
    cross join (
      values ('SELECT'::text), ('INSERT'), ('UPDATE'), ('DELETE')
    ) as privilege(privilege_name)
    where has_table_privilege(
      client.role_name,
      format('private.%I', private_table.table_name),
      privilege.privilege_name
    )
  ),
  'anon and authenticated have no coordination table access'
);

select ok(
  to_regprocedure('private.claim_idempotency_operation(uuid,text,bytea,bytea,uuid,timestamp with time zone,timestamp with time zone)') is not null
  and to_regprocedure('private.complete_idempotency_operation(uuid,text,bytea,bytea,uuid,integer,jsonb,timestamp with time zone)') is not null
  and to_regprocedure('private.read_api_cache(bytea,timestamp with time zone)') is not null
  and to_regprocedure('private.write_api_cache(bytea,jsonb,timestamp with time zone,timestamp with time zone,timestamp with time zone)') is not null
  and to_regprocedure('private.acquire_api_cache_lease(bytea,uuid,timestamp with time zone,timestamp with time zone)') is not null
  and to_regprocedure('private.release_api_cache_lease(bytea,uuid)') is not null
  and to_regprocedure('private.consume_rate_limit(uuid,text,integer,integer,timestamp with time zone)') is not null
  and to_regprocedure('private.purge_expired_coordination_state(timestamp with time zone,integer)') is not null,
  'all coordination functions have their exact required signatures'
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
        'claim_idempotency_operation', 'complete_idempotency_operation',
        'read_api_cache', 'write_api_cache', 'acquire_api_cache_lease',
        'release_api_cache_lease', 'consume_rate_limit',
        'purge_expired_coordination_state'
      )
  ),
  'coordination functions are security invoker with empty search paths'
);
select ok(
  not exists (
    select 1
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'private'
      and procedure.proname in (
        'claim_idempotency_operation', 'complete_idempotency_operation',
        'read_api_cache', 'write_api_cache', 'acquire_api_cache_lease',
        'release_api_cache_lease', 'consume_rate_limit',
        'purge_expired_coordination_state'
      )
      and (
        has_function_privilege('anon', procedure.oid, 'EXECUTE')
        or has_function_privilege('authenticated', procedure.oid, 'EXECUTE')
      )
  ),
  'client roles cannot execute coordination functions'
);
select ok(
  regexp_replace(
    pg_get_functiondef(
      'private.acquire_api_cache_lease(bytea,uuid,timestamp with time zone,timestamp with time zone)'::regprocedure
    ),
    E'\\s+',
    ' ',
    'g'
  ) ilike '%insert%on conflict%do update%where%',
  'lease acquisition is one conditional INSERT ON CONFLICT statement'
);
select ok(
  pg_get_functiondef(
    'private.consume_rate_limit(uuid,text,integer,integer,timestamp with time zone)'::regprocedure
  ) ilike '%pg_advisory_xact_lock%',
  'rate policy selection is serialized with a transaction-scoped advisory lock'
);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values (
  '61000000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'coordination-user@example.test', '',
  '2026-01-01 00:00:00+00', '{}', '{}',
  '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00'
);

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

-- Idempotency claim, coalescing, conflict, completion, replay, and reclaim.
select results_eq(
  $$select decision, response_status, response_body
    from private.claim_idempotency_operation(
      '61000000-0000-4000-8000-000000000001', 'synthetic.action',
      decode('a101', 'hex'), decode('b101', 'hex'),
      '71000000-0000-4000-8000-000000000001',
      '2026-01-01 00:00:00+00', '2026-01-01 01:00:00+00'
    )$$,
  $$values ('claimed'::text, null::integer, null::jsonb)$$,
  'the first idempotency attempt is claimed'
);
select results_eq(
  $$select decision, response_status, response_body
    from private.claim_idempotency_operation(
      '61000000-0000-4000-8000-000000000001', 'synthetic.action',
      decode('a101', 'hex'), decode('b101', 'hex'),
      '71000000-0000-4000-8000-000000000002',
      '2026-01-01 00:30:00+00', '2026-01-01 01:30:00+00'
    )$$,
  $$values ('in_progress'::text, null::integer, null::jsonb)$$,
  'a matching unexpired pending request is coalesced'
);
select is(
  private.complete_idempotency_operation(
    '61000000-0000-4000-8000-000000000001', 'synthetic.action',
    decode('a101', 'hex'), decode('b101', 'hex'),
    '71000000-0000-4000-8000-000000000001', 200,
    '{"result":"synthetic"}'::jsonb, '2026-01-01 00:40:00+00'
  ),
  true,
  'the current attempt can complete with an object response'
);
select results_eq(
  $$select decision, response_status, response_body
    from private.claim_idempotency_operation(
      '61000000-0000-4000-8000-000000000001', 'synthetic.action',
      decode('a101', 'hex'), decode('b101', 'hex'),
      '71000000-0000-4000-8000-000000000003',
      '2026-01-01 00:45:00+00', '2026-01-01 01:45:00+00'
    )$$,
  $$values ('replay'::text, 200, '{"result":"synthetic"}'::jsonb)$$,
  'a matching completed request replays the stored response'
);
select results_eq(
  $$select decision, response_status, response_body
    from private.claim_idempotency_operation(
      '61000000-0000-4000-8000-000000000001', 'synthetic.action',
      decode('a101', 'hex'), decode('ffff', 'hex'),
      '71000000-0000-4000-8000-000000000004',
      '2026-01-01 00:45:00+00', '2026-01-01 01:45:00+00'
    )$$,
  $$values ('conflict'::text, null::integer, null::jsonb)$$,
  'reuse of an idempotency key for a different request conflicts'
);
select results_eq(
  $$select decision, response_status, response_body
    from private.claim_idempotency_operation(
      '61000000-0000-4000-8000-000000000001', 'synthetic.reclaim',
      decode('a102', 'hex'), decode('b102', 'hex'),
      '71000000-0000-4000-8000-000000000001',
      '2026-01-01 00:00:00+00', '2026-01-01 00:10:00+00'
    )$$,
  $$values ('claimed'::text, null::integer, null::jsonb)$$,
  'a reclaim fixture is initially claimed'
);
select results_eq(
  $$select decision, response_status, response_body
    from private.claim_idempotency_operation(
      '61000000-0000-4000-8000-000000000001', 'synthetic.reclaim',
      decode('a102', 'hex'), decode('b102', 'hex'),
      '71000000-0000-4000-8000-000000000002',
      '2026-01-01 00:10:00+00', '2026-01-01 01:10:00+00'
    )$$,
  $$values ('claimed'::text, null::integer, null::jsonb)$$,
  'an expired pending operation can be reclaimed at its expiry boundary'
);
select is(
  private.complete_idempotency_operation(
    '61000000-0000-4000-8000-000000000001', 'synthetic.reclaim',
    decode('a102', 'hex'), decode('b102', 'hex'),
    '71000000-0000-4000-8000-000000000001', 200, '{}'::jsonb,
    '2026-01-01 00:11:00+00'
  ),
  false,
  'a superseded attempt cannot complete a reclaimed operation'
);
select throws_ok(
  $$select * from private.claim_idempotency_operation(
    '61000000-0000-4000-8000-000000000001', 'synthetic.invalid',
    decode('a103', 'hex'), decode('b103', 'hex'),
    '71000000-0000-4000-8000-000000000001',
    '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00')$$,
  'P0001', null,
  'idempotency expiry must be after the supplied current time'
);
select throws_ok(
  $$select private.complete_idempotency_operation(
    '61000000-0000-4000-8000-000000000001', 'synthetic.reclaim',
    decode('a102', 'hex'), decode('b102', 'hex'),
    '71000000-0000-4000-8000-000000000002', 99, '{}'::jsonb,
    '2026-01-01 00:12:00+00')$$,
  'P0001', null,
  'completion rejects an invalid response status'
);
select throws_ok(
  $$select private.complete_idempotency_operation(
    '61000000-0000-4000-8000-000000000001', 'synthetic.reclaim',
    decode('a102', 'hex'), decode('b102', 'hex'),
    '71000000-0000-4000-8000-000000000002', 200, '[]'::jsonb,
    '2026-01-01 00:12:00+00')$$,
  'P0001', null,
  'completion rejects a non-object response body'
);

-- Cache fresh, stale, and miss boundaries plus validation.
select lives_ok(
  $$select private.write_api_cache(
    decode('ca01', 'hex'), '{"forecast":"synthetic"}'::jsonb,
    '2026-01-01 00:00:00+00', '2026-01-01 00:10:00+00',
    '2026-01-01 00:20:00+00')$$,
  'a valid object response can be cached'
);
select results_eq(
  $$select cache_state, response_body, fresh_until, stale_until
    from private.read_api_cache(decode('ca01', 'hex'), '2026-01-01 00:09:59+00')$$,
  $$values (
    'fresh'::text, '{"forecast":"synthetic"}'::jsonb,
    '2026-01-01 00:10:00+00'::timestamptz,
    '2026-01-01 00:20:00+00'::timestamptz)$$,
  'cache content is fresh strictly before fresh_until'
);
select results_eq(
  $$select cache_state, response_body, fresh_until, stale_until
    from private.read_api_cache(decode('ca01', 'hex'), '2026-01-01 00:10:00+00')$$,
  $$values (
    'stale'::text, '{"forecast":"synthetic"}'::jsonb,
    '2026-01-01 00:10:00+00'::timestamptz,
    '2026-01-01 00:20:00+00'::timestamptz)$$,
  'cache content becomes stale at fresh_until'
);
select results_eq(
  $$select cache_state, response_body, fresh_until, stale_until
    from private.read_api_cache(decode('ca01', 'hex'), '2026-01-01 00:20:00+00')$$,
  $$values ('miss'::text, null::jsonb, null::timestamptz, null::timestamptz)$$,
  'cache content is a miss at stale_until'
);
select throws_ok(
  $$select private.write_api_cache(
    decode('ca02', 'hex'), '[]'::jsonb, '2026-01-01 00:00:00+00',
    '2026-01-01 00:10:00+00', '2026-01-01 00:20:00+00')$$,
  'P0001', null,
  'cache writes reject non-object response bodies'
);
select throws_ok(
  $$select private.write_api_cache(
    decode('ca02', 'hex'), '{}'::jsonb, '2026-01-01 00:00:00+00',
    '2026-01-01 00:20:00+00', '2026-01-01 00:10:00+00')$$,
  'P0001', null,
  'cache writes reject inverted freshness and stale deadlines'
);

-- Lease exclusion, renewal, takeover, and holder-only release.
select is(private.acquire_api_cache_lease(
  decode('1e01', 'hex'), '81000000-0000-4000-8000-000000000001',
  '2026-01-01 00:00:00+00', '2026-01-01 00:10:00+00'), true,
  'the first lease holder acquires the cache key');
select is(private.acquire_api_cache_lease(
  decode('1e01', 'hex'), '81000000-0000-4000-8000-000000000002',
  '2026-01-01 00:05:00+00', '2026-01-01 00:15:00+00'), false,
  'a different holder cannot acquire an unexpired lease');
select is(private.acquire_api_cache_lease(
  decode('1e01', 'hex'), '81000000-0000-4000-8000-000000000001',
  '2026-01-01 00:05:00+00', '2026-01-01 00:20:00+00'), true,
  'the current holder can renew its lease');
select is(private.acquire_api_cache_lease(
  decode('1e01', 'hex'), '81000000-0000-4000-8000-000000000002',
  '2026-01-01 00:20:00+00', '2026-01-01 00:30:00+00'), true,
  'a new holder can take over exactly at lease expiry');
select is(private.release_api_cache_lease(
  decode('1e01', 'hex'), '81000000-0000-4000-8000-000000000001'), false,
  'a former holder cannot release another holder lease');
select is(private.release_api_cache_lease(
  decode('1e01', 'hex'), '81000000-0000-4000-8000-000000000002'), true,
  'the current holder can release its lease');
select throws_ok(
  $$select private.acquire_api_cache_lease(
    decode('1e02', 'hex'), '81000000-0000-4000-8000-000000000001',
    '2026-01-01 00:00:00+00', '2026-01-01 00:00:00+00')$$,
  'P0001', null,
  'a lease deadline must be after the supplied current time'
);

-- Atomic fixed-window rate consumption and policy drift rejection.
select results_eq(
  $$select allowed, remaining, reset_at from private.consume_rate_limit(
    '61000000-0000-4000-8000-000000000001', 'synthetic.rate', 2, 60,
    '2026-01-01 00:00:10+00')$$,
  $$values (true, 1, '2026-01-01 00:01:00+00'::timestamptz)$$,
  'the first request consumes one fixed-window allowance'
);
select results_eq(
  $$select allowed, remaining, reset_at from private.consume_rate_limit(
    '61000000-0000-4000-8000-000000000001', 'synthetic.rate', 2, 60,
    '2026-01-01 00:00:20+00')$$,
  $$values (true, 0, '2026-01-01 00:01:00+00'::timestamptz)$$,
  'the final available request is allowed with zero remaining'
);
select results_eq(
  $$select allowed, remaining, reset_at from private.consume_rate_limit(
    '61000000-0000-4000-8000-000000000001', 'synthetic.rate', 2, 60,
    '2026-01-01 00:00:30+00')$$,
  $$values (false, 0, '2026-01-01 00:01:00+00'::timestamptz)$$,
  'requests above the fixed-window limit fail closed without incrementing'
);
select results_eq(
  $$select allowed, remaining, reset_at from private.consume_rate_limit(
    '61000000-0000-4000-8000-000000000001', 'synthetic.rate', 2, 60,
    '2026-01-01 00:01:00+00')$$,
  $$values (true, 1, '2026-01-01 00:02:00+00'::timestamptz)$$,
  'the exact reset boundary begins a new fixed window'
);
select throws_ok(
  $$select * from private.consume_rate_limit(
    '61000000-0000-4000-8000-000000000001', 'synthetic.rate', 3, 60,
    '2026-01-01 00:01:10+00')$$,
  'P0001', null,
  'changing the limit within an existing bucket fails closed'
);
select throws_ok(
  $$select * from private.consume_rate_limit(
    '61000000-0000-4000-8000-000000000001', 'synthetic.rate', 2, 120,
    '2026-01-01 00:00:30+00')$$,
  'P0001', null,
  'changing the window policy for an existing bucket fails closed'
);
select throws_ok(
  $$select * from private.consume_rate_limit(
    '61000000-0000-4000-8000-000000000001', 'synthetic.rate', 2, 120,
    '2026-01-01 00:01:30+00')$$,
  'P0001', null,
  'an overlapping changed-duration window fails closed even when its computed start differs'
);
select throws_ok(
  $$select * from private.consume_rate_limit(
    '61000000-0000-4000-8000-000000000001', 'synthetic.invalid-rate', 0, 60,
    '2026-01-01 00:00:00+00')$$,
  'P0001', null,
  'rate limits require a positive limit'
);

-- Bounded deterministic cleanup returns one result per resource.
insert into private.idempotency_operations (
  user_id, action, idempotency_key_fingerprint, request_fingerprint,
  attempt_id, state, expires_at, created_at, updated_at
)
values
  ('61000000-0000-4000-8000-000000000001', 'purge.one', decode('d101','hex'), decode('e101','hex'), '91000000-0000-4000-8000-000000000001', 'pending', '2026-01-01', '2025-01-01', '2025-01-01'),
  ('61000000-0000-4000-8000-000000000001', 'purge.two', decode('d102','hex'), decode('e102','hex'), '91000000-0000-4000-8000-000000000002', 'pending', '2026-01-01', '2025-01-01', '2025-01-01');
insert into private.api_cache_entries values
  (decode('cc01','hex'), '{}'::jsonb, '2025-01-01', '2026-01-01', '2025-01-01', '2025-01-01'),
  (decode('cc02','hex'), '{}'::jsonb, '2025-01-01', '2026-01-01', '2025-01-01', '2025-01-01');
insert into private.api_cache_leases values
  (decode('dd01','hex'), '91000000-0000-4000-8000-000000000001', '2026-01-01', '2025-01-01', '2025-01-01'),
  (decode('dd02','hex'), '91000000-0000-4000-8000-000000000002', '2026-01-01', '2025-01-01', '2025-01-01');

select is(
  (
    select array_agg(resource order by resource)
    from private.purge_expired_coordination_state('2027-01-01', 1)
    where deleted_count = 1
  ),
  array[
    'api_cache_entries', 'api_cache_leases',
    'idempotency_operations', 'rate_limit_windows'
  ]::text[],
  'bounded cleanup deletes at most one expired row from each resource'
);
select ok(
  (select count(*) from private.idempotency_operations where expires_at <= '2027-01-01') >= 1
  and (select count(*) from private.api_cache_entries where stale_until <= '2027-01-01') >= 1
  and (select count(*) from private.api_cache_leases where lease_until <= '2027-01-01') >= 1,
  'a batch size of one leaves additional expired rows for later cleanup'
);
select throws_ok(
  $$select * from private.purge_expired_coordination_state('2027-01-01', 0)$$,
  'P0001', null,
  'cleanup requires a positive batch size'
);

reset role;
select set_config('request.jwt.claims', '{}', true);

-- Direct client calls and table reads are denied.
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"61000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
select throws_ok(
  $$select * from private.idempotency_operations$$,
  '42501', null,
  'authenticated clients cannot read coordination state'
);
select throws_ok(
  $$select * from private.read_api_cache(decode('ca01','hex'), '2026-01-01')$$,
  '42501', null,
  'authenticated clients cannot invoke coordination functions'
);
reset role;
select set_config('request.jwt.claims', '{}', true);

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select throws_ok(
  $$select * from private.rate_limit_windows$$,
  '42501', null,
  'anonymous clients cannot read coordination state'
);
select throws_ok(
  $$select * from private.consume_rate_limit(
    '61000000-0000-4000-8000-000000000001', 'synthetic.rate', 2, 60,
    '2026-01-01')$$,
  '42501', null,
  'anonymous clients cannot invoke coordination functions'
);
reset role;
select set_config('request.jwt.claims', '{}', true);

select * from finish();

rollback;
