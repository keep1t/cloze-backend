insert into storage.buckets (id, name, public)
values ('share-snapshots', 'share-snapshots', false);

create table private.share_snapshots (
  share_id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  token_hash bytea not null unique check (octet_length(token_hash) > 0),
  status text not null check (status in ('pending', 'active', 'revoked')),
  upload_expires_at timestamptz not null,
  expires_at timestamptz not null,
  activated_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (created_at < upload_expires_at and upload_expires_at <= expires_at),
  check ((status='pending' and activated_at is null and revoked_at is null) or (status='active' and activated_at is not null and revoked_at is null) or (status='revoked' and revoked_at is not null))
);
create index share_snapshots_user_id_idx on private.share_snapshots (user_id);
create index share_snapshots_expires_at_idx on private.share_snapshots (expires_at);
alter table private.share_snapshots enable row level security;
alter table private.share_snapshots force row level security;
revoke all on table private.share_snapshots from public, anon, authenticated, service_role;
grant select, insert, update, delete on table private.share_snapshots to service_role;

create function private.create_share_snapshot(p_share_id uuid,p_user_id uuid,p_token_hash bytea,p_upload_expires_at timestamptz,p_expires_at timestamptz,p_now timestamptz)
returns table(bucket text, object_name text) language plpgsql security invoker set search_path='' as $$
begin
  if octet_length(p_token_hash)=0 or p_upload_expires_at<=p_now or p_expires_at<p_upload_expires_at then raise exception using errcode='P0001'; end if;
  insert into private.share_snapshots values(p_share_id,p_user_id,p_token_hash,'pending',p_upload_expires_at,p_expires_at,null,null,p_now,p_now);
  return query select 'share-snapshots'::text, 'shares/' || p_share_id::text || '/snapshot';
end $$;
create function private.activate_share_snapshot(p_share_id uuid,p_user_id uuid,p_now timestamptz)
returns boolean language plpgsql security invoker set search_path='' as $$
begin
  update private.share_snapshots as share set status='active',activated_at=p_now,updated_at=p_now
  where share.share_id=p_share_id and share.user_id=p_user_id and share.status='pending' and p_now<share.upload_expires_at and p_now<share.expires_at
  and exists(select 1 from storage.objects as object where object.bucket_id='share-snapshots' and object.name='shares/' || p_share_id::text || '/snapshot');
  return found;
end $$;
create function private.resolve_share_snapshot(p_token_hash bytea,p_now timestamptz)
returns table(share_id uuid,bucket text,object_name text,expires_at timestamptz) language sql security invoker set search_path='' as $$
  select share.share_id,'share-snapshots'::text,'shares/' || share.share_id::text || '/snapshot',share.expires_at
  from private.share_snapshots as share where share.token_hash=p_token_hash and share.status='active' and p_now<share.expires_at;
$$;
create function private.revoke_share_snapshot(p_share_id uuid,p_user_id uuid,p_now timestamptz)
returns boolean language plpgsql security invoker set search_path='' as $$
begin
  update private.share_snapshots set status='revoked',revoked_at=p_now,updated_at=p_now where share_id=p_share_id and user_id=p_user_id and status in ('pending','active');
  return found;
end $$;
revoke all on function private.create_share_snapshot(uuid,uuid,bytea,timestamptz,timestamptz,timestamptz),private.activate_share_snapshot(uuid,uuid,timestamptz),private.resolve_share_snapshot(bytea,timestamptz),private.revoke_share_snapshot(uuid,uuid,timestamptz) from public,anon,authenticated,service_role;
grant execute on function private.create_share_snapshot(uuid,uuid,bytea,timestamptz,timestamptz,timestamptz),private.activate_share_snapshot(uuid,uuid,timestamptz),private.resolve_share_snapshot(bytea,timestamptz),private.revoke_share_snapshot(uuid,uuid,timestamptz) to service_role;
