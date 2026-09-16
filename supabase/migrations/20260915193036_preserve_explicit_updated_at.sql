create function private.set_share_snapshot_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.updated_at is not distinct from old.updated_at then
    new.updated_at := now();
  end if;
  return new;
end;
$$;

revoke all on function private.set_share_snapshot_updated_at() from public, anon, authenticated, service_role;

create trigger share_snapshots_set_updated_at
  before update on private.share_snapshots
  for each row execute function private.set_share_snapshot_updated_at();
