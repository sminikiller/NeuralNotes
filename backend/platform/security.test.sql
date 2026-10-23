\set ON_ERROR_STOP on
insert into auth.users(id) values('11111111-1111-4111-8111-111111111111'),('22222222-2222-4222-8222-222222222222'),('33333333-3333-4333-8333-333333333333');
insert into public.nn_entitlements(user_id,daily_ai_limit,storage_limit) values('11111111-1111-4111-8111-111111111111',2,1000),('22222222-2222-4222-8222-222222222222',1,20);
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
insert into public.nn_profiles values(auth.uid(),'Autore A');
insert into public.nn_hubs(id,owner_id,slug,title,visibility) values('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',auth.uid(),'infermieri-privati','Infermieristica privata','private'),('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',auth.uid(),'infermieristica','Infermieristica','public');
do $$begin
 if not public.nn_consume_ai() or not public.nn_consume_ai() or public.nn_consume_ai() then raise exception 'daily quota failed'; end if;
 begin update public.nn_entitlements set daily_ai_limit=999 where user_id=auth.uid(); if found then raise exception 'client changed plan'; end if; exception when insufficient_privilege then null; end;
end$$;
select public.nn_reserve_upload('cloud','cccccccc-cccc-4ccc-8ccc-cccccccccccc','nnbackup',10) as cloud_path \gset
insert into storage.objects(bucket_id,name,metadata) values('neuralnotes-private',:'cloud_path','{"size":10}');
select (public.nn_commit_document('cccccccc-cccc-4ccc-8ccc-cccccccccccc',0,'Quaderno',:'cloud_path',repeat('a',64),10,false)).revision;
select public.nn_reserve_upload('cloud','cccccccc-cccc-4ccc-8ccc-cccccccccccc','nnbackup',10) as next_path \gset
insert into storage.objects(bucket_id,name,metadata) values('neuralnotes-private',:'next_path','{"size":10}');
select set_config('nn.test.next_path',:'next_path',false);
do $$begin
 begin perform public.nn_commit_document('cccccccc-cccc-4ccc-8ccc-cccccccccccc',0,'Vecchio',current_setting('nn.test.next_path'),repeat('a',64),10,false); raise exception 'lost update'; exception when sqlstate 'PT409' then null; end;
 begin perform public.nn_commit_document('cccccccc-cccc-4ccc-8ccc-cccccccccccc',null,'Bypass',current_setting('nn.test.next_path'),repeat('a',64),10,false); raise exception 'null revision accepted'; exception when invalid_parameter_value then null; end;
 if (select count(*) from public.nn_snapshots)<>1 then raise exception 'unexpected snapshot count'; end if;
end$$;
select public.nn_reserve_upload('community','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','pdf',3) as post_path \gset
insert into storage.objects(bucket_id,name,metadata) values('neuralnotes-private',:'post_path','{"size":3}');
insert into public.nn_resources(id,hub_id,owner_id,title,object_path) values('dddddddd-dddd-4ddd-8ddd-dddddddddddd','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',auth.uid(),'Appunti condivisi',:'post_path');
select public.nn_moderate_resource('dddddddd-dddd-4ddd-8ddd-dddddddddddd','published');
select public.nn_create_invite('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',repeat('e',64),now()+interval '1 hour',1);
select public.nn_reserve_upload('community','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','pdf',5) as bad_size_path \gset
select set_config('nn.test.bad_size',:'bad_size_path',false);
do $$begin
 begin insert into storage.objects(bucket_id,name,metadata) values('neuralnotes-private',current_setting('nn.test.bad_size'),'{"size":6}'); raise exception 'upload size bypass'; exception when insufficient_privilege then null; end;
end$$;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
do $$begin
 if (select count(*) from public.nn_documents)<>0 or (select count(*) from public.nn_snapshots)<>0 then raise exception 'private document leak'; end if;
 if (select count(*) from public.nn_profiles)<>0 then raise exception 'private profile leak'; end if;
 if (select count(*) from public.nn_hubs)<>1 then raise exception 'private hub leak'; end if;
 if (select count(*) from public.nn_resources)<>1 then raise exception 'published resource unavailable'; end if;
 begin perform public.nn_moderate_resource('dddddddd-dddd-4ddd-8ddd-dddddddddddd','hidden'); raise exception 'moderation privilege escalation'; exception when insufficient_privilege then null; end;
 begin perform public.nn_reserve_upload('cloud','ffffffff-ffff-4fff-8fff-ffffffffffff','nnbackup',21); raise exception 'quota bypass'; exception when raise_exception then if sqlerrm<>'storage_quota' then raise; end if; end;
end$$;
select public.nn_join_invite(repeat('e',64));
do $$begin if (select count(*) from public.nn_hubs)<>2 then raise exception 'invite did not grant membership'; end if; end$$;
insert into public.nn_reports(resource_id,reporter_id,reason) values('dddddddd-dddd-4ddd-8ddd-dddddddddddd',auth.uid(),'Verificare questa fonte');
insert into public.nn_blocks values(auth.uid(),'11111111-1111-4111-8111-111111111111');
do $$begin if (select count(*) from public.nn_resources)<>0 then raise exception 'blocked author still visible'; end if; end$$;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
do $$begin
 begin perform public.nn_join_invite(repeat('e',64)); raise exception 'invite overused'; exception when invalid_parameter_value then null; end;
 if (select count(*) from public.nn_hubs)<>1 then raise exception 'unauthorized membership'; end if;
end$$;
reset role;
insert into public.nn_entitlements(user_id,daily_ai_limit,monthly_ai_limit) values('33333333-3333-4333-8333-333333333333',200,100);
insert into public.nn_ai_usage(user_id,day,used) values('33333333-3333-4333-8333-333333333333',(now() at time zone 'UTC')::date,99);
set role authenticated;
do $$begin
 if public.nn_consume_ai(2) or not public.nn_consume_ai(1) or public.nn_consume_ai(1) then raise exception 'monthly quota bypass'; end if;
end$$;
reset role;
do $$begin
 if (select revision from public.nn_documents where id='cccccccc-cccc-4ccc-8ccc-cccccccccccc')<>1 then raise exception 'conflict overwrote document'; end if;
 if (select used from public.nn_invites where digest=repeat('e',64))<>1 then raise exception 'invite usage mismatch'; end if;
end$$;
select 'PLATFORM_SQL_PASS: quota, reservation size, RLS isolation, moderation, report/block, invite limits, revision CAS and null rejection';
