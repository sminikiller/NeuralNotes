-- Apply AFTER schema.sql, once, in a transaction. Never rerun the fresh schema on a live project.
begin;
create table public.nn_account_deletions (
 user_id uuid primary key references auth.users(id) on delete cascade,
 requested_at timestamptz not null default now()
);
alter table public.nn_account_deletions enable row level security;
-- No direct client grants: only the self-scoped functions below can change this table.
create function public.nn_account_exists() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.users where id=auth.uid())
$$;
create function public.nn_account_active() returns boolean language sql stable security definer set search_path='' as $$
 select public.nn_account_exists() and not exists(select 1 from public.nn_account_deletions where user_id=auth.uid())
$$;
create function public.nn_require_recent_login() returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from auth.users where id=auth.uid() and last_sign_in_at > now()-interval '5 minutes')
 then raise exception 'reauthentication_required' using errcode='PT401'; end if;
end $$;
create function public.nn_guard_account_write() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is not null then
  -- Same lock as deletion: an upload/write cannot slip past the final empty-storage check.
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,1));
  if not public.nn_account_active() then raise exception 'account_unavailable' using errcode='42501'; end if;
 end if;
 return new;
end $$;
do $$declare name text; begin
 foreach name in array array['nn_profiles','nn_entitlements','nn_ai_usage','nn_hubs','nn_hub_members','nn_resources','nn_reports','nn_blocks','nn_invites','nn_documents','nn_snapshots','nn_uploads'] loop
  execute format('create policy nn_active_account on public.%I as restrictive for all to authenticated using(public.nn_account_active()) with check(public.nn_account_active())',name);
  execute format('create trigger nn_account_write before insert or update on public.%I for each row execute function public.nn_guard_account_write()',name);
 end loop;
end $$;
create trigger nn_storage_account_write before insert or update on storage.objects for each row execute function public.nn_guard_account_write();
-- Issued access JWTs survive deletion until expiry. RLS must reject subjects no longer in Auth.
create policy nn_existing_account on storage.objects as restrictive for all to authenticated
 using(public.nn_account_exists()) with check(public.nn_account_active());
create function public.nn_account_deleting() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.nn_account_deletions where user_id=auth.uid())
$$;
create policy nn_delete_own_pending_files on storage.objects for delete to authenticated
 using(bucket_id='neuralnotes-private' and split_part(name,'/',1)=auth.uid()::text and public.nn_account_deleting());

create function public.nn_begin_account_deletion() returns void language plpgsql security definer set search_path='' as $$
begin
 perform public.nn_require_recent_login();
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,1));
 if exists(select 1 from public.nn_hubs h join public.nn_resources r on r.hub_id=h.id
           where h.owner_id=auth.uid() and r.owner_id<>auth.uid())
 then raise exception 'transfer_shared_hubs_first' using errcode='PT409'; end if;
 insert into public.nn_account_deletions(user_id) values(auth.uid()) on conflict do nothing;
end $$;
create function public.nn_account_deletion_objects() returns setof text language plpgsql security definer set search_path='' as $$
begin
 perform public.nn_require_recent_login();
 if not public.nn_account_deleting() then raise exception 'deletion_not_started' using errcode='42501'; end if;
 return query select name from storage.objects where bucket_id='neuralnotes-private'
 and split_part(name,'/',1)=auth.uid()::text order by name limit 100;
end $$;
create function public.nn_finish_account_deletion() returns void language plpgsql security definer set search_path='' as $$
declare who uuid:=auth.uid();
begin
 perform public.nn_require_recent_login();
 perform pg_advisory_xact_lock(hashtextextended(who::text,1));
 if not public.nn_account_deleting() then raise exception 'deletion_not_started' using errcode='42501'; end if;
 if exists(select 1 from storage.objects where bucket_id='neuralnotes-private' and split_part(name,'/',1)=who::text)
 then raise exception 'storage_cleanup_incomplete' using errcode='PT409'; end if;
 if exists(select 1 from public.nn_hubs h join public.nn_resources r on r.hub_id=h.id where h.owner_id=who and r.owner_id<>who)
 then raise exception 'transfer_shared_hubs_first' using errcode='PT409'; end if;
 delete from public.nn_reports where reporter_id=who or resource_id in (select id from public.nn_resources where owner_id=who);
 delete from public.nn_resources where owner_id=who;
 delete from public.nn_blocks where user_id=who or blocked_user_id=who;
 delete from public.nn_invites where hub_id in (select id from public.nn_hubs where owner_id=who);
 delete from public.nn_hub_members where user_id=who or hub_id in (select id from public.nn_hubs where owner_id=who);
 delete from public.nn_hubs where owner_id=who;
 delete from public.nn_snapshots where owner_id=who;
 delete from public.nn_documents where owner_id=who;
 delete from public.nn_uploads where owner_id=who;
 -- Auth sessions/refresh tokens and self profile/usage/entitlements cascade together.
 delete from auth.users where id=who;
end $$;
create function public.nn_transfer_hub(target uuid, next_owner uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.nn_account_active() or next_owner is null or not exists(select 1 from public.nn_hubs where id=target and owner_id=auth.uid())
 or not exists(select 1 from public.nn_hub_members where hub_id=target and user_id=next_owner)
 then raise exception 'forbidden_transfer' using errcode='42501'; end if;
 update public.nn_hubs set owner_id=next_owner where id=target;
 insert into public.nn_hub_members(hub_id,user_id,role) values(target,auth.uid(),'moderator') on conflict(hub_id,user_id) do update set role='moderator';
end $$;
revoke all on function public.nn_account_exists(),public.nn_account_active(),public.nn_account_deleting(),public.nn_require_recent_login(),public.nn_guard_account_write(),public.nn_begin_account_deletion(),public.nn_account_deletion_objects(),public.nn_finish_account_deletion(),public.nn_transfer_hub(uuid,uuid) from public;
grant execute on function public.nn_account_exists(),public.nn_account_active(),public.nn_account_deleting(),public.nn_begin_account_deletion(),public.nn_account_deletion_objects(),public.nn_finish_account_deletion(),public.nn_transfer_hub(uuid,uuid) to authenticated;
commit;
