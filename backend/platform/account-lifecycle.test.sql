\set ON_ERROR_STOP on
reset role;
select set_config('request.jwt.claim.sub','',false);
insert into auth.users(id,last_sign_in_at) values('44444444-4444-4444-8444-444444444444',now()-interval '1 hour'),('55555555-5555-4555-8555-555555555555',now());
insert into public.nn_profiles values('44444444-4444-4444-8444-444444444444','Da cancellare'),('55555555-5555-4555-8555-555555555555','Da conservare');
insert into storage.objects(bucket_id,name,metadata) values('neuralnotes-private','44444444-4444-4444-8444-444444444444/cloud/old/file.nnbackup','{"size":10}'),('neuralnotes-private','55555555-5555-4555-8555-555555555555/cloud/old/file.nnbackup','{"size":10}');
set role authenticated;
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
do $$begin
 begin perform public.nn_begin_account_deletion(); raise exception 'old login accepted'; exception when sqlstate 'PT401' then null; end;
 if not public.nn_account_active() then raise exception 'old login changed account'; end if;
end$$;
reset role;
update auth.users set last_sign_in_at=now() where id='44444444-4444-4444-8444-444444444444';
set role authenticated;
select public.nn_begin_account_deletion();
select public.nn_begin_account_deletion(); -- idempotent interrupted-cleanup recovery

do $$begin
 if public.nn_account_active() then raise exception 'deleting account still active'; end if;
 if (select count(*) from public.nn_account_deletion_objects())<>1 then raise exception 'objects not isolated'; end if;
 begin perform public.nn_finish_account_deletion(); raise exception 'deleted before storage cleanup'; exception when sqlstate 'PT409' then null; end;
 begin insert into public.nn_profiles values(auth.uid(),'Bypass') on conflict(user_id) do update set display_name='Bypass'; raise exception 'write allowed during deletion'; exception when insufficient_privilege then null; end;
 begin perform public.nn_reserve_upload('cloud','cccccccc-cccc-4ccc-8ccc-cccccccccccc','nnbackup',10); raise exception 'pending upload allowed'; exception when insufficient_privilege then null; end;
 delete from storage.objects where name like '55555555%';
 if found then raise exception 'deleted other account files'; end if;
end$$;
delete from storage.objects where bucket_id='neuralnotes-private' and name like '44444444%';
select public.nn_finish_account_deletion();
-- A still-issued JWT cannot read public hubs, write through definer RPCs, or access storage.
do $$begin
 if public.nn_account_exists() then raise exception 'Auth user survived deletion'; end if;
 if (select count(*) from public.nn_hubs)<>0 or (select count(*) from storage.objects)<>0 then raise exception 'deleted JWT still sees data'; end if;
 begin perform public.nn_consume_ai(); raise exception 'deleted JWT still writes'; exception when insufficient_privilege then null; end;
end$$;
reset role;
select set_config('request.jwt.claim.sub','',false);
do $$begin
 if exists(select 1 from auth.users where id='44444444-4444-4444-8444-444444444444') or exists(select 1 from public.nn_account_deletions where user_id='44444444-4444-4444-8444-444444444444') then raise exception 'cleanup did not cascade'; end if;
 if not exists(select 1 from public.nn_profiles where user_id='55555555-5555-4555-8555-555555555555') or not exists(select 1 from storage.objects where name like '55555555%') then raise exception 'other account damaged'; end if;
end$$;
-- A publisher cannot remove someone else's resources by deleting the group owner.
insert into public.nn_hub_members(hub_id,user_id,role) values('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','11111111-1111-4111-8111-111111111111','contributor');
update public.nn_hubs set owner_id='55555555-5555-4555-8555-555555555555' where id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
set role authenticated;
select set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',false);
do $$begin
 begin perform public.nn_begin_account_deletion(); raise exception 'foreign material would be deleted'; exception when sqlstate 'PT409' then null; end;
 if not public.nn_account_active() then raise exception 'refused deletion changed account'; end if;
 begin perform public.nn_transfer_hub('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','33333333-3333-4333-8333-333333333333'); raise exception 'transfer to nonmember accepted'; exception when insufficient_privilege then null; end;
end$$;
select public.nn_transfer_hub('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','11111111-1111-4111-8111-111111111111');
reset role;
do $$begin
 if not exists(select 1 from public.nn_hubs where id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' and owner_id='11111111-1111-4111-8111-111111111111') or not exists(select 1 from public.nn_resources where hub_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') then raise exception 'transfer lost content'; end if;
end$$;
select 'ACCOUNT_SQL_PASS: recent OTP, resumable cleanup, pending-write lockout, storage isolation, JWT revocation by RLS, other account retained';
