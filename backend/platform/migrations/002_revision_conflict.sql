-- Semantic CAS conflicts must not use 40001: PostgREST retries serialization failures.
begin;
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
 if entry.revision<>expected_revision then raise exception 'revision_conflict' using errcode='PT409'; end if;
 select storage_limit into cap from public.nn_entitlements where user_id=who; cap:=coalesce(cap,268435456);
 select coalesce(sum(byte_size),0) into used_bytes from public.nn_snapshots where owner_id=who;
 if used_bytes+next_bytes>cap then raise exception 'storage_quota' using errcode='P0001'; end if;
 insert into public.nn_snapshots(document_id,revision,owner_id,object_path,checksum,byte_size) values(target,entry.revision+1,who,next_object,next_checksum,next_bytes);
 update public.nn_documents set revision=entry.revision+1,title=next_title,object_path=next_object,checksum=next_checksum,byte_size=next_bytes,deleted=tombstone,updated_at=now() where id=target returning * into entry;
 return entry;
end $$;
commit;
