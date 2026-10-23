-- Public capability probe: contains no account/provider data or privileged access.
begin;
create function public.nn_platform_version() returns integer language sql immutable set search_path='' as $$ select 2 $$;
grant execute on function public.nn_platform_version() to public;
commit;
