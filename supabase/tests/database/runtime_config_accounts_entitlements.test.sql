begin;

select no_plan();

-- Schema and object contract.
select has_schema('private', 'private schema exists');
select has_table('private', 'product_config', 'private.product_config exists');
select has_table('public', 'user_settings', 'public.user_settings exists');
select has_table('private', 'user_entitlements', 'private.user_entitlements exists');

select ok(
  to_regprocedure('private.get_config_integer(text,bigint,bigint)') is not null,
  'integer configuration reader has the required signature'
);
select ok(
  to_regprocedure('private.get_config_text(text)') is not null,
  'text configuration reader has the required signature'
);
select ok(
  to_regprocedure('private.get_config_text_array(text)') is not null,
  'text array configuration reader has the required signature'
);
select ok(
  to_regprocedure('private.has_active_entitlement(uuid,text,timestamp with time zone)') is not null,
  'entitlement predicate has the required signature'
);
select ok(
  to_regprocedure('private.handle_new_user()') is not null,
  'Auth provisioning trigger function has the required signature'
);

select is(
  (
    select array_agg(column_name::text order by column_name)
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'user_settings'
  ),
  array[
    'created_at',
    'preferences',
    'preferences_schema_version',
    'privacy',
    'privacy_schema_version',
    'updated_at',
    'user_id'
  ]::text[],
  'user_settings contains only owner, versioned documents, and timestamps'
);
select is(
  (
    select array_agg(column_name::text order by column_name)
    from information_schema.columns
    where table_schema = 'private'
      and table_name = 'product_config'
  ),
  array['key', 'updated_at', 'value']::text[],
  'product_config contains only managed key, JSON value, and timestamp'
);
select is(
  (
    select array_agg(column_name::text order by column_name)
    from information_schema.columns
    where table_schema = 'private'
      and table_name = 'user_entitlements'
  ),
  array[
    'created_at',
    'entitlement_key',
    'source_reference',
    'status',
    'updated_at',
    'user_id',
    'valid_from',
    'valid_until'
  ]::text[],
  'user_entitlements contains only owner, entitlement state, validity, opaque source, and timestamps'
);

select ok(
  (
    select relrowsecurity and relforcerowsecurity
    from pg_class
    where oid = 'public.user_settings'::regclass
  ),
  'user_settings has RLS enabled and forced'
);
select ok(
  (
    select relrowsecurity and relforcerowsecurity
    from pg_class
    where oid = 'private.user_entitlements'::regclass
  ),
  'user_entitlements has RLS enabled and forced'
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
        and policy.tablename = 'user_settings'
        and policy.cmd in (required_policy.command, 'ALL')
        and 'authenticated'::name = any (policy.roles)
        and (not required_policy.needs_using or policy.qual is not null)
        and (not required_policy.needs_check or policy.with_check is not null)
    )
  ),
  'user_settings has authenticated owner-policy coverage for every CRUD command'
);
select ok(
  not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'user_settings'
      and roles && array['anon'::name, 'public'::name]
  ),
  'user_settings has no anonymous or public policy'
);
select is(
  (
    select count(*)::integer
    from pg_policies
    where schemaname = 'private'
      and tablename in ('product_config', 'user_entitlements')
  ),
  0,
  'private configuration and entitlements have no client policies'
);

-- Least-privilege grants.
select ok(
  not exists (
    select 1
    from pg_namespace as namespace
    cross join lateral aclexplode(
      coalesce(namespace.nspacl, acldefault('n', namespace.nspowner))
    ) as privilege
    where namespace.nspname = 'private'
      and privilege.grantee = 0
      and privilege.privilege_type = 'USAGE'
  ),
  'PUBLIC has no usage on the private schema'
);
select ok(
  not has_schema_privilege('anon', 'private', 'USAGE')
  and not has_schema_privilege('authenticated', 'private', 'USAGE'),
  'client roles have no usage on the private schema'
);
select ok(
  has_schema_privilege('service_role', 'private', 'USAGE'),
  'service_role has usage on the private schema'
);

select ok(
  not has_table_privilege('anon', 'public.user_settings', 'SELECT')
  and not has_table_privilege('anon', 'public.user_settings', 'INSERT')
  and not has_table_privilege('anon', 'public.user_settings', 'UPDATE')
  and not has_table_privilege('anon', 'public.user_settings', 'DELETE')
  and not has_table_privilege('anon', 'private.product_config', 'SELECT')
  and not has_table_privilege('anon', 'private.product_config', 'INSERT')
  and not has_table_privilege('anon', 'private.product_config', 'UPDATE')
  and not has_table_privilege('anon', 'private.product_config', 'DELETE')
  and not has_table_privilege('anon', 'private.user_entitlements', 'SELECT')
  and not has_table_privilege('anon', 'private.user_entitlements', 'INSERT')
  and not has_table_privilege('anon', 'private.user_entitlements', 'UPDATE')
  and not has_table_privilege('anon', 'private.user_entitlements', 'DELETE'),
  'anon has no product table privileges'
);
select ok(
  has_table_privilege('authenticated', 'public.user_settings', 'SELECT')
  and has_table_privilege('authenticated', 'public.user_settings', 'INSERT')
  and has_table_privilege('authenticated', 'public.user_settings', 'UPDATE')
  and has_table_privilege('authenticated', 'public.user_settings', 'DELETE')
  and not has_table_privilege('authenticated', 'public.user_settings', 'TRUNCATE')
  and not has_table_privilege('authenticated', 'public.user_settings', 'REFERENCES')
  and not has_table_privilege('authenticated', 'public.user_settings', 'TRIGGER'),
  'authenticated receives only CRUD privileges on user_settings'
);
select ok(
  not has_table_privilege('authenticated', 'private.product_config', 'SELECT')
  and not has_table_privilege('authenticated', 'private.product_config', 'INSERT')
  and not has_table_privilege('authenticated', 'private.product_config', 'UPDATE')
  and not has_table_privilege('authenticated', 'private.product_config', 'DELETE')
  and not has_table_privilege('authenticated', 'private.user_entitlements', 'SELECT')
  and not has_table_privilege('authenticated', 'private.user_entitlements', 'INSERT')
  and not has_table_privilege('authenticated', 'private.user_entitlements', 'UPDATE')
  and not has_table_privilege('authenticated', 'private.user_entitlements', 'DELETE'),
  'authenticated has no direct access to private product tables'
);
select ok(
  has_table_privilege('service_role', 'private.product_config', 'SELECT')
  and has_table_privilege('service_role', 'private.user_entitlements', 'SELECT')
  and has_table_privilege('service_role', 'private.user_entitlements', 'INSERT')
  and has_table_privilege('service_role', 'private.user_entitlements', 'UPDATE')
  and has_table_privilege('service_role', 'private.user_entitlements', 'DELETE'),
  'service_role has the required server-side table privileges'
);

select ok(
  not has_function_privilege('anon', 'private.get_config_integer(text,bigint,bigint)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'private.get_config_integer(text,bigint,bigint)', 'EXECUTE')
  and not has_function_privilege('anon', 'private.get_config_text(text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'private.get_config_text(text)', 'EXECUTE')
  and not has_function_privilege('anon', 'private.get_config_text_array(text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'private.get_config_text_array(text)', 'EXECUTE')
  and not has_function_privilege('anon', 'private.has_active_entitlement(uuid,text,timestamp with time zone)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'private.has_active_entitlement(uuid,text,timestamp with time zone)', 'EXECUTE')
  and not has_function_privilege('anon', 'private.handle_new_user()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'private.handle_new_user()', 'EXECUTE'),
  'client roles cannot execute private functions'
);
select ok(
  has_function_privilege('service_role', 'private.get_config_integer(text,bigint,bigint)', 'EXECUTE')
  and has_function_privilege('service_role', 'private.get_config_text(text)', 'EXECUTE')
  and has_function_privilege('service_role', 'private.get_config_text_array(text)', 'EXECUTE')
  and has_function_privilege('service_role', 'private.has_active_entitlement(uuid,text,timestamp with time zone)', 'EXECUTE'),
  'service_role can execute private reader functions'
);

select ok(
  (
    select bool_and(not procedure.prosecdef)
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'private'
      and procedure.proname in (
        'get_config_integer',
        'get_config_text',
        'get_config_text_array',
        'has_active_entitlement'
      )
  ),
  'private reader functions are security invoker'
);
select ok(
  (
    select
      not procedure.prosecdef
      or exists (
        select 1
        from unnest(coalesce(procedure.proconfig, array[]::text[])) as setting
        where setting in ('search_path=', 'search_path=""')
      )
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'private'
      and procedure.proname = 'handle_new_user'
      and procedure.pronargs = 0
  ),
  'a security-definer Auth trigger uses an empty search path'
);

-- Managed configuration is empty until runtime values are supplied.
select is(
  (select count(*)::bigint from private.product_config),
  0::bigint,
  'migrations do not seed business configuration values'
);

insert into private.product_config (key, value, updated_at)
values
  ('test.integer.valid', '5'::jsonb, '2026-01-01 00:00:00+00'),
  ('test.integer.string', '"5"'::jsonb, '2026-01-01 00:00:00+00'),
  ('test.integer.fractional', '5.5'::jsonb, '2026-01-01 00:00:00+00'),
  ('test.integer.low', '-1'::jsonb, '2026-01-01 00:00:00+00'),
  ('test.integer.high', '11'::jsonb, '2026-01-01 00:00:00+00'),
  ('test.text.valid', '"America/Sao_Paulo"'::jsonb, '2026-01-01 00:00:00+00'),
  ('test.text.wrong_type', '{}'::jsonb, '2026-01-01 00:00:00+00'),
  ('test.array.valid', '["image/jpeg", "image/png"]'::jsonb, '2026-01-01 00:00:00+00'),
  ('test.array.wrong_type', '"image/jpeg"'::jsonb, '2026-01-01 00:00:00+00'),
  ('test.array.mixed', '["image/jpeg", 7]'::jsonb, '2026-01-01 00:00:00+00');

select is(
  private.get_config_integer('test.integer.valid', 0, 10),
  5::bigint,
  'integer reader returns an integral value within inclusive bounds'
);
select is(
  private.get_config_text('test.text.valid'),
  'America/Sao_Paulo',
  'text reader returns a JSON string'
);
select is(
  private.get_config_text_array('test.array.valid'),
  array['image/jpeg', 'image/png']::text[],
  'text array reader returns JSON string elements in order'
);

select throws_ok(
  $$select private.get_config_integer('test.integer.missing', 0, 10)$$,
  'P0001',
  'CONFIGURATION_ERROR: test.integer.missing',
  'missing integer configuration fails closed without exposing a value'
);
select throws_ok(
  $$select private.get_config_integer('test.integer.string', 0, 10)$$,
  'P0001',
  'CONFIGURATION_ERROR: test.integer.string',
  'wrong integer JSON type fails closed'
);
select throws_ok(
  $$select private.get_config_integer('test.integer.fractional', 0, 10)$$,
  'P0001',
  'CONFIGURATION_ERROR: test.integer.fractional',
  'non-integral numeric configuration fails closed'
);
select throws_ok(
  $$select private.get_config_integer('test.integer.low', 0, 10)$$,
  'P0001',
  'CONFIGURATION_ERROR: test.integer.low',
  'integer below the lower bound fails closed'
);
select throws_ok(
  $$select private.get_config_integer('test.integer.high', 0, 10)$$,
  'P0001',
  'CONFIGURATION_ERROR: test.integer.high',
  'integer above the upper bound fails closed'
);
select throws_ok(
  $$select private.get_config_text('test.text.missing')$$,
  'P0001',
  'CONFIGURATION_ERROR: test.text.missing',
  'missing text configuration fails closed'
);
select throws_ok(
  $$select private.get_config_text('test.text.wrong_type')$$,
  'P0001',
  'CONFIGURATION_ERROR: test.text.wrong_type',
  'wrong text JSON type fails closed'
);
select throws_ok(
  $$select private.get_config_text_array('test.array.missing')$$,
  'P0001',
  'CONFIGURATION_ERROR: test.array.missing',
  'missing text array configuration fails closed'
);
select throws_ok(
  $$select private.get_config_text_array('test.array.wrong_type')$$,
  'P0001',
  'CONFIGURATION_ERROR: test.array.wrong_type',
  'wrong text array JSON type fails closed'
);
select throws_ok(
  $$select private.get_config_text_array('test.array.mixed')$$,
  'P0001',
  'CONFIGURATION_ERROR: test.array.mixed',
  'a text array with a non-string element fails closed'
);

update private.product_config
set value = '6'::jsonb
where key = 'test.integer.valid';

select cmp_ok(
  (
    select updated_at
    from private.product_config
    where key = 'test.integer.valid'
  ),
  '>',
  '2026-01-01 00:00:00+00'::timestamptz,
  'updating managed configuration advances updated_at'
);

-- Synthetic Auth users exercise provisioning and owner policies.
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
    '10000000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'owner@example.test',
    '',
    '2026-01-01 00:00:00+00',
    '{"provider":"google","authorization":"server-only"}',
    '{"full_name":"Private Owner Name"}',
    '2026-01-01 00:00:00+00',
    '2026-01-01 00:00:00+00'
  ),
  (
    '20000000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'other@example.test',
    '',
    '2026-01-01 00:00:00+00',
    '{"provider":"apple"}',
    '{"full_name":"Private Other Name"}',
    '2026-01-01 00:00:00+00',
    '2026-01-01 00:00:00+00'
  ),
  (
    '30000000-0000-4000-8000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'reassignment-target@example.test',
    '',
    '2026-01-01 00:00:00+00',
    '{}',
    '{}',
    '2026-01-01 00:00:00+00',
    '2026-01-01 00:00:00+00'
  );

select ok(
  exists (
    select 1
    from pg_trigger as trigger
    join pg_proc as procedure on procedure.oid = trigger.tgfoid
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where trigger.tgrelid = 'auth.users'::regclass
      and not trigger.tgisinternal
      and namespace.nspname = 'private'
      and procedure.proname = 'handle_new_user'
  ),
  'auth.users invokes the private provisioning trigger'
);
select is(
  (
    select count(*)::integer
    from public.user_settings
    where user_id in (
      '10000000-0000-4000-8000-000000000001',
      '20000000-0000-4000-8000-000000000002',
      '30000000-0000-4000-8000-000000000003'
    )
  ),
  3,
  'Auth provisioning creates one settings row per new user'
);
select ok(
  (
    select preferences = '{}'::jsonb
      and privacy = '{}'::jsonb
      and preferences_schema_version > 0
      and privacy_schema_version > 0
      and created_at is not null
      and updated_at is not null
    from public.user_settings
    where user_id = '10000000-0000-4000-8000-000000000001'
  ),
  'Auth provisioning stores only empty versioned documents and timestamps'
);
select ok(
  position('owner@example.test' in (
    select to_jsonb(settings)::text
    from public.user_settings as settings
    where user_id = '10000000-0000-4000-8000-000000000001'
  )) = 0
  and position('Private Owner Name' in (
    select to_jsonb(settings)::text
    from public.user_settings as settings
    where user_id = '10000000-0000-4000-8000-000000000001'
  )) = 0,
  'Auth provisioning does not copy email or user metadata'
);

select throws_ok(
  $$insert into public.user_settings (
      user_id, preferences, preferences_schema_version,
      privacy, privacy_schema_version
    ) values (
      '40000000-0000-4000-8000-000000000004', '[]'::jsonb, 1, '{}'::jsonb, 1
    )$$,
  '23514',
  null,
  'settings preferences must be a JSON object'
);
select throws_ok(
  $$insert into public.user_settings (
      user_id, preferences, preferences_schema_version,
      privacy, privacy_schema_version
    ) values (
      '40000000-0000-4000-8000-000000000004', '{}'::jsonb, 0, '{}'::jsonb, 1
    )$$,
  '23514',
  null,
  'settings schema versions must be positive'
);

-- Leave a valid Auth target without a settings row for reassignment testing.
delete from public.user_settings
where user_id = '30000000-0000-4000-8000-000000000003';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

select is(
  (select count(*)::integer from public.user_settings),
  1,
  'an authenticated owner can select only their settings row'
);
select lives_ok(
  $$update public.user_settings
    set preferences = '{"unit_system":"metric"}'::jsonb
    where user_id = '10000000-0000-4000-8000-000000000001'$$,
  'an owner can update their settings'
);
select is(
  (
    select preferences ->> 'unit_system'
    from public.user_settings
    where user_id = '10000000-0000-4000-8000-000000000001'
  ),
  'metric',
  'the owner update is persisted'
);
select lives_ok(
  $$update public.user_settings
    set preferences = '{"unit_system":"imperial"}'::jsonb
    where user_id = '20000000-0000-4000-8000-000000000002'$$,
  'a cross-owner update is safely filtered by RLS'
);
select throws_ok(
  $$update public.user_settings
    set user_id = '30000000-0000-4000-8000-000000000003'
    where user_id = '10000000-0000-4000-8000-000000000001'$$,
  '42501',
  null,
  'an owner cannot reassign their settings row'
);
select lives_ok(
  $$delete from public.user_settings
    where user_id = '20000000-0000-4000-8000-000000000002'$$,
  'a cross-owner delete is safely filtered by RLS'
);
select lives_ok(
  $$delete from public.user_settings
    where user_id = '10000000-0000-4000-8000-000000000001'$$,
  'an owner can delete their settings row'
);
select is(
  (select count(*)::integer from public.user_settings),
  0,
  'the owner delete removes the visible row'
);
select lives_ok(
  $$insert into public.user_settings (
      user_id, preferences, preferences_schema_version,
      privacy, privacy_schema_version, created_at, updated_at
    ) values (
      '10000000-0000-4000-8000-000000000001',
      '{"unit_system":"metric"}'::jsonb,
      1,
      '{"share_history":false}'::jsonb,
      1,
      '2026-01-01 00:00:00+00',
      '2026-01-01 00:00:00+00'
    )$$,
  'an owner can insert their own settings row'
);
select is(
  (select count(*)::integer from public.user_settings),
  1,
  'the owner insert creates exactly one visible row'
);
select lives_ok(
  $$update public.user_settings
    set privacy = '{"share_history":true}'::jsonb
    where user_id = '10000000-0000-4000-8000-000000000001'$$,
  'an owner can update privacy after recreating their settings row'
);
select cmp_ok(
  (
    select updated_at
    from public.user_settings
    where user_id = '10000000-0000-4000-8000-000000000001'
  ),
  '>',
  '2026-01-01 00:00:00+00'::timestamptz,
  'updating user settings advances updated_at'
);
select throws_ok(
  $$insert into public.user_settings (
      user_id, preferences, preferences_schema_version,
      privacy, privacy_schema_version
    ) values (
      '30000000-0000-4000-8000-000000000003', '{}'::jsonb, 1, '{}'::jsonb, 1
    )$$,
  '42501',
  null,
  'an authenticated user cannot insert settings for another user'
);

reset role;

select is(
  (
    select preferences ->> 'unit_system'
    from public.user_settings
    where user_id = '20000000-0000-4000-8000-000000000002'
  ),
  null,
  'cross-owner update did not change the other user settings'
);
select is(
  (
    select count(*)::integer
    from public.user_settings
    where user_id = '20000000-0000-4000-8000-000000000002'
  ),
  1,
  'cross-owner delete did not remove the other user settings'
);

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select throws_ok(
  $$select * from public.user_settings$$,
  '42501',
  null,
  'anonymous users cannot select settings'
);
select throws_ok(
  $$insert into public.user_settings (
      user_id, preferences, preferences_schema_version,
      privacy, privacy_schema_version
    ) values (
      '10000000-0000-4000-8000-000000000001', '{}'::jsonb, 1, '{}'::jsonb, 1
    )$$,
  '42501',
  null,
  'anonymous users cannot insert settings'
);
select throws_ok(
  $$update public.user_settings set privacy = '{}'::jsonb$$,
  '42501',
  null,
  'anonymous users cannot update settings'
);
select throws_ok(
  $$delete from public.user_settings$$,
  '42501',
  null,
  'anonymous users cannot delete settings'
);

reset role;

-- Entitlements are private, constrained, and bounded by [valid_from, valid_until).
insert into private.user_entitlements (
  user_id,
  entitlement_key,
  status,
  valid_from,
  valid_until,
  source_reference,
  created_at,
  updated_at
)
values
  (
    '10000000-0000-4000-8000-000000000001',
    'premium.fixed',
    'active',
    '2026-02-01 00:00:00+00',
    '2026-03-01 00:00:00+00',
    'opaque-fixed-reference',
    '2026-01-01 00:00:00+00',
    '2026-01-01 00:00:00+00'
  ),
  (
    '10000000-0000-4000-8000-000000000001',
    'premium.open',
    'active',
    '2026-02-01 00:00:00+00',
    null,
    null,
    '2026-01-01 00:00:00+00',
    '2026-01-01 00:00:00+00'
  ),
  (
    '10000000-0000-4000-8000-000000000001',
    'premium.inactive',
    'inactive',
    '2026-02-01 00:00:00+00',
    '2026-03-01 00:00:00+00',
    null,
    '2026-01-01 00:00:00+00',
    '2026-01-01 00:00:00+00'
  ),
  (
    '10000000-0000-4000-8000-000000000001',
    'premium.revoked',
    'revoked',
    '2026-02-01 00:00:00+00',
    '2026-03-01 00:00:00+00',
    null,
    '2026-01-01 00:00:00+00',
    '2026-01-01 00:00:00+00'
  );

select ok(
  private.has_active_entitlement(
    '10000000-0000-4000-8000-000000000001',
    'premium.fixed',
    '2026-02-01 00:00:00+00'
  ),
  'an active entitlement includes its start instant'
);
select ok(
  private.has_active_entitlement(
    '10000000-0000-4000-8000-000000000001',
    'premium.fixed',
    '2026-02-28 23:59:59.999999+00'
  ),
  'an active entitlement remains valid immediately before its end'
);
select ok(
  not private.has_active_entitlement(
    '10000000-0000-4000-8000-000000000001',
    'premium.fixed',
    '2026-01-31 23:59:59.999999+00'
  ),
  'an entitlement excludes instants before its start'
);
select ok(
  not private.has_active_entitlement(
    '10000000-0000-4000-8000-000000000001',
    'premium.fixed',
    '2026-03-01 00:00:00+00'
  ),
  'an entitlement excludes its end instant'
);
select ok(
  private.has_active_entitlement(
    '10000000-0000-4000-8000-000000000001',
    'premium.open',
    '2036-02-01 00:00:00+00'
  ),
  'an active entitlement without an end remains valid after its start'
);
select ok(
  not private.has_active_entitlement(
    '10000000-0000-4000-8000-000000000001',
    'premium.inactive',
    '2026-02-15 00:00:00+00'
  ),
  'an inactive entitlement never satisfies the predicate'
);
select ok(
  not private.has_active_entitlement(
    '10000000-0000-4000-8000-000000000001',
    'premium.revoked',
    '2026-02-15 00:00:00+00'
  ),
  'a revoked entitlement never satisfies the predicate'
);
select ok(
  not private.has_active_entitlement(
    '20000000-0000-4000-8000-000000000002',
    'premium.fixed',
    '2026-02-15 00:00:00+00'
  ),
  'an entitlement is scoped to the supplied user UUID'
);
select ok(
  not private.has_active_entitlement(
    '10000000-0000-4000-8000-000000000001',
    'premium.unknown',
    '2026-02-15 00:00:00+00'
  ),
  'an unknown entitlement key fails closed'
);

select throws_ok(
  $$insert into private.user_entitlements (
      user_id, entitlement_key, status, valid_from, valid_until
    ) values (
      '20000000-0000-4000-8000-000000000002',
      'premium.invalid-status',
      'pending',
      '2026-02-01 00:00:00+00',
      '2026-03-01 00:00:00+00'
    )$$,
  '23514',
  null,
  'entitlement status rejects values outside the closed status set'
);
select throws_ok(
  $$insert into private.user_entitlements (
      user_id, entitlement_key, status, valid_from, valid_until
    ) values (
      '20000000-0000-4000-8000-000000000002',
      'premium.invalid-window',
      'active',
      '2026-03-01 00:00:00+00',
      '2026-03-01 00:00:00+00'
    )$$,
  '23514',
  null,
  'an entitlement end must be strictly after its start'
);

update private.user_entitlements
set source_reference = 'opaque-updated-reference'
where user_id = '10000000-0000-4000-8000-000000000001'
  and entitlement_key = 'premium.fixed';

select cmp_ok(
  (
    select updated_at
    from private.user_entitlements
    where user_id = '10000000-0000-4000-8000-000000000001'
      and entitlement_key = 'premium.fixed'
  ),
  '>',
  '2026-01-01 00:00:00+00'::timestamptz,
  'updating an entitlement advances updated_at'
);

select * from finish();

rollback;
