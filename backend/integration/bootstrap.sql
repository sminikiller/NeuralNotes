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
-- Storage API migrates its real schema before application migrations run.
create role supabase_storage_admin login noinherit createrole password 'nn-integration-storage-only';
create schema storage authorization supabase_storage_admin;
grant authenticated, anon, service_role to supabase_storage_admin;
grant usage on schema public to supabase_storage_admin;
alter role supabase_storage_admin set search_path = storage, public;
grant usage on schema storage to authenticated, anon, service_role;
alter default privileges for role supabase_storage_admin in schema storage grant select,insert,update,delete on tables to authenticated;
alter default privileges for role supabase_storage_admin in schema storage grant all on tables to service_role;
