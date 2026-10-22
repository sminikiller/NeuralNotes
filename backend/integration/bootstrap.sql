-- Only test bootstrap. GoTrue creates the real auth.users and sessions tables.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create role authenticator login noinherit password 'nn-integration-role-only';
grant anon, authenticated to authenticator;
create schema auth;
create role supabase_auth_admin login password 'nn-integration-auth-only';
alter schema auth owner to supabase_auth_admin;
alter role supabase_auth_admin set search_path = auth;
create function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid;
$$;
alter function auth.uid() owner to supabase_auth_admin;
grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
-- Storage HTTP is not tested by this environment. These tables only let the
-- production platform migration install; tests exercise Auth/RLS/AI routes.
create schema storage;
create table storage.buckets(id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid(), bucket_id text, name text, metadata jsonb);
alter table storage.objects enable row level security;
grant usage on schema storage to authenticated;
grant select, insert on storage.objects to authenticated;
