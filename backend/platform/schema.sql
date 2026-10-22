-- Fresh Supabase project migration. Apply through SQL migrations, not the app.
create table if not exists public.nn_profiles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null check(length(display_name) between 1 and 80)
);
create table if not exists public.nn_entitlements (
 user_id uuid primary key references auth.users(id) on delete cascade,
 plan text not null default 'free' check(plan in ('free','study','pro','team')),
 monthly_ai_limit integer not null default 100 check(monthly_ai_limit between 0 and 10000000),
 daily_ai_limit integer not null default 10 check(daily_ai_limit between 0 and 100000),
 storage_limit bigint not null default 268435456 check(storage_limit >= 0)
);
create table if not exists public.nn_ai_usage (
 user_id uuid not null references auth.users(id) on delete cascade, day date not null, used integer not null default 0,
 primary key(user_id,day)
);
create table if not exists public.nn_hubs (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id),
 slug text not null unique check(slug ~ '^[a-z0-9][a-z0-9-]{2,79}$'), title text not null check(length(title) between 1 and 120),
 visibility text not null default 'private' check(visibility in ('public','private')), created_at timestamptz not null default now()
);
create table if not exists public.nn_hub_members (
 hub_id uuid not null references public.nn_hubs(id) on delete cascade, user_id uuid not null references auth.users(id),
 role text not null default 'viewer' check(role in ('viewer','contributor','moderator')), primary key(hub_id,user_id)
);
create table if not exists public.nn_resources (
 id uuid primary key default gen_random_uuid(), hub_id uuid not null references public.nn_hubs(id),
 owner_id uuid not null references auth.users(id), title text not null check(length(title) between 1 and 160),
 description text not null default '' check(length(description)<=4000),
 object_path text not null check(length(object_path)<512 and object_path like owner_id::text || '/community/%'),
 tags text[] not null default '{}' check(cardinality(tags)<=12),
 status text not null default 'pending' check(status in ('draft','pending','published','hidden')),
 created_at timestamptz not null default now()
);
create table if not exists public.nn_reports (
 id uuid primary key default gen_random_uuid(), resource_id uuid not null references public.nn_resources(id),
 reporter_id uuid not null references auth.users(id), reason text not null check(length(reason) between 1 and 1000),
 status text not null default 'open' check(status in ('open','resolved')), created_at timestamptz not null default now()
);
create table if not exists public.nn_blocks (
 user_id uuid not null references auth.users(id), blocked_user_id uuid not null references auth.users(id),
 primary key(user_id,blocked_user_id), check(user_id<>blocked_user_id)
);
create table if not exists public.nn_invites (
 digest text primary key check(digest ~ '^[a-f0-9]{64}$'), hub_id uuid not null references public.nn_hubs(id),
 expires_at timestamptz not null, max_uses integer not null check(max_uses between 1 and 100), used integer not null default 0
);
create table if not exists public.nn_documents (
 id uuid primary key, owner_id uuid not null references auth.users(id), revision integer not null default 0,
 title text not null default '' check(length(title)<=160), object_path text,
 checksum text, byte_size bigint not null default 0, deleted boolean not null default false, updated_at timestamptz not null default now()
);
create table if not exists public.nn_snapshots (
 document_id uuid not null references public.nn_documents(id), revision integer not null,
 owner_id uuid not null references auth.users(id), object_path text not null unique,
 checksum text not null check(checksum ~ '^[a-f0-9]{64}$'), byte_size bigint not null check(byte_size between 1 and 104857600),
 created_at timestamptz not null default now(), primary key(document_id,revision)
);
create index if not exists nn_resources_hub_status on public.nn_resources(hub_id,status,created_at desc);
create index if not exists nn_documents_owner on public.nn_documents(owner_id,updated_at desc);

create or replace function public.nn_can_read_hub(target uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.nn_hubs h where h.id=target and
 (h.visibility='public' or h.owner_id=auth.uid() or exists(select 1 from public.nn_hub_members m where m.hub_id=h.id and m.user_id=auth.uid())))
$$;
create or replace function public.nn_can_write_hub(target uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.nn_hubs h where h.id=target and
 (h.owner_id=auth.uid() or exists(select 1 from public.nn_hub_members m where m.hub_id=h.id and m.user_id=auth.uid() and m.role in ('contributor','moderator'))))
$$;
create or replace function public.nn_is_hub_admin(target uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.nn_hubs h where h.id=target and
 (h.owner_id=auth.uid() or exists(select 1 from public.nn_hub_members m where m.hub_id=h.id and m.user_id=auth.uid() and m.role='moderator')))
$$;

alter table public.nn_profiles enable row level security;
alter table public.nn_entitlements enable row level security;
alter table public.nn_ai_usage enable row level security;
alter table public.nn_hubs enable row level security;
alter table public.nn_hub_members enable row level security;
alter table public.nn_resources enable row level security;
alter table public.nn_reports enable row level security;
alter table public.nn_blocks enable row level security;
alter table public.nn_invites enable row level security;
alter table public.nn_documents enable row level security;
alter table public.nn_snapshots enable row level security;
create policy nn_profile_self on public.nn_profiles for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy nn_entitlements_self on public.nn_entitlements for select to authenticated using(user_id=auth.uid());
create policy nn_usage_self on public.nn_ai_usage for select to authenticated using(user_id=auth.uid());
create policy nn_hubs_read on public.nn_hubs for select to authenticated using(public.nn_can_read_hub(id));
create policy nn_hubs_create on public.nn_hubs for insert to authenticated with check(owner_id=auth.uid());
create policy nn_hubs_update on public.nn_hubs for update to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
create policy nn_members_read on public.nn_hub_members for select to authenticated using(user_id=auth.uid() or public.nn_is_hub_admin(hub_id));
create policy nn_resources_read on public.nn_resources for select to authenticated using(
 (owner_id=auth.uid() or public.nn_is_hub_admin(hub_id) or (status='published' and public.nn_can_read_hub(hub_id)))
 and not exists(select 1 from public.nn_blocks b where b.user_id=auth.uid() and b.blocked_user_id=owner_id));
create policy nn_resources_create on public.nn_resources for insert to authenticated with check(owner_id=auth.uid() and status in ('draft','pending') and public.nn_can_write_hub(hub_id));
create policy nn_reports_create on public.nn_reports for insert to authenticated with check(reporter_id=auth.uid() and status='open' and exists(select 1 from public.nn_resources r where r.id=resource_id));
create policy nn_reports_read on public.nn_reports for select to authenticated using(reporter_id=auth.uid() or exists(select 1 from public.nn_resources r where r.id=resource_id and public.nn_is_hub_admin(r.hub_id)));
create policy nn_blocks_self on public.nn_blocks for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy nn_invites_admin on public.nn_invites for select to authenticated using(public.nn_is_hub_admin(hub_id));
create policy nn_documents_self on public.nn_documents for select to authenticated using(owner_id=auth.uid());
create policy nn_snapshots_self on public.nn_snapshots for select to authenticated using(owner_id=auth.uid());

grant select,insert,update,delete on public.nn_profiles,public.nn_blocks to authenticated;
grant select,insert,update on public.nn_hubs to authenticated;
grant select,insert on public.nn_resources,public.nn_reports to authenticated;
grant select on public.nn_entitlements,public.nn_ai_usage,public.nn_hub_members,public.nn_invites,public.nn_documents,public.nn_snapshots to authenticated;

create or replace function public.nn_consume_ai(credits integer default 1) returns boolean language plpgsql security definer set search_path='' as $$
declare who uuid:=auth.uid(); cap integer; monthly_cap integer; monthly_used integer; accepted integer;
begin
 if who is null then raise exception 'unauthorized' using errcode='42501'; end if;
 if credits is null or credits<1 or credits>20 then raise exception 'invalid_credits' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(who::text,1));
 select daily_ai_limit,monthly_ai_limit into cap,monthly_cap from public.nn_entitlements where user_id=who; cap:=coalesce(cap,10); monthly_cap:=coalesce(monthly_cap,100);
 select coalesce(sum(used),0) into monthly_used from public.nn_ai_usage where user_id=who and day>=date_trunc('month',now() at time zone 'UTC')::date;
 if monthly_used+credits>monthly_cap then return false; end if;
 if cap<credits then return false; end if;
 insert into public.nn_ai_usage(user_id,day,used) values(who,(now() at time zone 'UTC')::date,credits)
 on conflict(user_id,day) do update set used=nn_ai_usage.used+credits where nn_ai_usage.used+credits<=cap returning used into accepted;
 return accepted is not null;
end $$;
create or replace function public.nn_moderate_resource(target uuid, next_status text) returns void language plpgsql security definer set search_path='' as $$
declare entry public.nn_resources;
begin
 select * into entry from public.nn_resources where id=target for update;
 if not found or auth.uid() is null or not (public.nn_is_hub_admin(entry.hub_id) or (entry.owner_id=auth.uid() and next_status='hidden')) then raise exception 'forbidden' using errcode='42501'; end if;
 if next_status not in ('published','hidden') then raise exception 'invalid_status' using errcode='22023'; end if;
 update public.nn_resources set status=next_status where id=target;
end $$;
create or replace function public.nn_create_invite(target uuid, token_digest text, expires timestamptz, uses integer) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.nn_is_hub_admin(target) then raise exception 'forbidden' using errcode='42501'; end if;
 if expires<=now() or expires>now()+interval '7 days' then raise exception 'invalid_expiry' using errcode='22023'; end if;
 insert into public.nn_invites(digest,hub_id,expires_at,max_uses) values(token_digest,target,expires,uses);
end $$;
create or replace function public.nn_join_invite(token_digest text) returns uuid language plpgsql security definer set search_path='' as $$
declare entry public.nn_invites; who uuid:=auth.uid();
begin
 if who is null then raise exception 'unauthorized' using errcode='42501'; end if;
 select * into entry from public.nn_invites where digest=token_digest for update;
 if not found or entry.expires_at<=now() then raise exception 'invalid_invite' using errcode='22023'; end if;
 if exists(select 1 from public.nn_hub_members where hub_id=entry.hub_id and user_id=who) then return entry.hub_id; end if;
 if entry.used>=entry.max_uses then raise exception 'exhausted_invite' using errcode='22023'; end if;
 insert into public.nn_hub_members(hub_id,user_id,role) values(entry.hub_id,who,'contributor');
 update public.nn_invites set used=used+1 where digest=token_digest;
 return entry.hub_id;
end $$;
create or replace function public.nn_commit_document(target uuid, expected_revision integer, next_title text, next_object text, next_checksum text, next_bytes bigint, tombstone boolean default false)
 returns public.nn_documents language plpgsql security definer set search_path='' as $$
declare who uuid:=auth.uid(); entry public.nn_documents; cap bigint; used_bytes bigint;
begin
 if who is null then raise exception 'unauthorized' using errcode='42501'; end if;
 if target is null or expected_revision is null or next_bytes is null or next_checksum is null or next_object is null or next_title is null or tombstone is null or expected_revision<0 or next_bytes<1 or next_bytes>104857600 or next_checksum !~ '^[a-f0-9]{64}$'
 or next_object !~ ('^'||who::text||'/cloud/'||target::text||'/[a-f0-9-]{36}\.nnbackup$') then raise exception 'invalid_snapshot' using errcode='22023'; end if;
 if not exists(select 1 from storage.objects where bucket_id='neuralnotes-private' and name=next_object and (metadata->>'size')::bigint=next_bytes) then raise exception 'upload_not_ready' using errcode='22023'; end if;
 -- Per-account lock serializes quota checks across different documents.
 perform pg_advisory_xact_lock(hashtextextended(who::text,0));
 insert into public.nn_documents(id,owner_id) values(target,who) on conflict(id) do nothing;
 select * into entry from public.nn_documents where id=target for update;
 if entry.owner_id<>who then raise exception 'forbidden' using errcode='42501'; end if;
 if entry.revision<>expected_revision then raise exception 'revision_conflict' using errcode='40001'; end if;
 select storage_limit into cap from public.nn_entitlements where user_id=who; cap:=coalesce(cap,268435456);
 select coalesce(sum(byte_size),0) into used_bytes from public.nn_snapshots where owner_id=who;
 if used_bytes+next_bytes>cap then raise exception 'storage_quota' using errcode='P0001'; end if;
 insert into public.nn_snapshots(document_id,revision,owner_id,object_path,checksum,byte_size) values(target,entry.revision+1,who,next_object,next_checksum,next_bytes);
 update public.nn_documents set revision=entry.revision+1,title=next_title,object_path=next_object,checksum=next_checksum,byte_size=next_bytes,deleted=tombstone,updated_at=now() where id=target returning * into entry;
 return entry;
end $$;
-- PUBLIC execute is revoked: authentication is required even through direct RPC.
revoke all on function public.nn_consume_ai(integer),public.nn_moderate_resource(uuid,text),public.nn_create_invite(uuid,text,timestamptz,integer),public.nn_join_invite(text),public.nn_commit_document(uuid,integer,text,text,text,bigint,boolean),public.nn_can_read_hub(uuid),public.nn_can_write_hub(uuid),public.nn_is_hub_admin(uuid) from public;
grant execute on function public.nn_consume_ai(integer),public.nn_moderate_resource(uuid,text),public.nn_create_invite(uuid,text,timestamptz,integer),public.nn_join_invite(text),public.nn_commit_document(uuid,integer,text,text,text,bigint,boolean),public.nn_can_read_hub(uuid),public.nn_can_write_hub(uuid),public.nn_is_hub_admin(uuid) to authenticated;


create table public.nn_uploads (
 object_path text primary key, owner_id uuid not null references auth.users(id), byte_size bigint not null check(byte_size between 1 and 104857600), expires_at timestamptz not null
);
alter table public.nn_uploads enable row level security;
create policy nn_uploads_self on public.nn_uploads for select to authenticated using(owner_id=auth.uid());
grant select on public.nn_uploads to authenticated;
create or replace function public.nn_reserve_upload(kind text, entity uuid, extension text, expected_bytes bigint) returns text language plpgsql security definer set search_path='' as $$
declare who uuid:=auth.uid(); cap bigint; occupied bigint; reserved bigint; object_name text;
begin
 if who is null then raise exception 'unauthorized' using errcode='42501'; end if;
 if entity is null or kind is null or extension is null or expected_bytes is null or expected_bytes<1 or expected_bytes>104857600 or kind not in ('cloud','community') or extension not in ('nnbackup','pdf','png','jpeg') then raise exception 'invalid_upload' using errcode='22023'; end if;
 if kind='community' and not public.nn_can_write_hub(entity) then raise exception 'forbidden' using errcode='42501'; end if;
 if kind='cloud' and (extension<>'nnbackup' or exists(select 1 from public.nn_documents where id=entity and owner_id<>who)) then raise exception 'forbidden' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(who::text,0));
 delete from public.nn_uploads u where owner_id=who and expires_at<=now() and not exists(select 1 from storage.objects o where o.bucket_id='neuralnotes-private' and o.name=u.object_path);
 if (select count(*) from public.nn_uploads u where owner_id=who and expires_at>now() and not exists(select 1 from storage.objects o where o.bucket_id='neuralnotes-private' and o.name=u.object_path))>=32 then raise exception 'storage_quota' using errcode='P0001'; end if;
 select storage_limit into cap from public.nn_entitlements where user_id=who; cap:=coalesce(cap,268435456);
 select coalesce(sum((metadata->>'size')::bigint),0) into occupied from storage.objects where bucket_id='neuralnotes-private' and split_part(name,'/',1)=who::text;
 select coalesce(sum(byte_size),0) into reserved from public.nn_uploads u where owner_id=who and expires_at>now() and not exists(select 1 from storage.objects o where o.bucket_id='neuralnotes-private' and o.name=u.object_path);
 if occupied+reserved+expected_bytes>cap then raise exception 'storage_quota' using errcode='P0001'; end if;
 object_name:=who::text||'/'||kind||'/'||entity::text||'/'||gen_random_uuid()::text||'.'||extension;
 insert into public.nn_uploads values(object_name,who,expected_bytes,now()+interval '1 hour');
 return object_name;
end $$;
create or replace function public.nn_can_upload(object_name text, actual_bytes bigint) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.nn_uploads u where u.object_path=object_name and u.owner_id=auth.uid() and u.expires_at>now() and (actual_bytes is null or actual_bytes=u.byte_size))
$$;
revoke all on function public.nn_reserve_upload(text,uuid,text,bigint),public.nn_can_upload(text,bigint) from public;
grant execute on function public.nn_reserve_upload(text,uuid,text,bigint),public.nn_can_upload(text,bigint) to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('neuralnotes-private','neuralnotes-private',false,104857600,array['application/pdf','application/octet-stream','image/png','image/jpeg']) on conflict(id) do nothing;
create policy nn_files_create on storage.objects for insert to authenticated with check(bucket_id='neuralnotes-private' and public.nn_can_upload(name,(metadata->>'size')::bigint));
create policy nn_files_read on storage.objects for select to authenticated using(bucket_id='neuralnotes-private' and
 (split_part(name,'/',1)=auth.uid()::text or exists(select 1 from public.nn_resources r where r.object_path=name and r.status='published' and public.nn_can_read_hub(r.hub_id))));
-- No client UPDATE of objects: snapshot names are immutable. GC is an admin job.

create or replace function public.nn_validate_resource_upload() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.object_path not like new.owner_id::text||'/community/'||new.hub_id::text||'/%'
 or exists(select 1 from unnest(new.tags) t where length(t)>40)
 or not exists(select 1 from storage.objects o join public.nn_uploads u on u.object_path=o.name where o.bucket_id='neuralnotes-private' and o.name=new.object_path and u.owner_id=new.owner_id and (o.metadata->>'size')::bigint=u.byte_size)
 then raise exception 'upload_not_ready' using errcode='22023'; end if;
 return new;
end $$;
revoke all on function public.nn_validate_resource_upload() from public;
create trigger nn_resource_uploaded before insert on public.nn_resources for each row execute function public.nn_validate_resource_upload();
