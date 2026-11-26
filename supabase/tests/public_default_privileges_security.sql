-- Run after 20261126071600_harden_public_default_privileges.sql.
-- The workflow seeds Supabase-like insecure defaults before applying the
-- migration. These probes verify the defaults for both object owners.

CREATE TABLE public.gativx_default_privilege_probe_postgres (id integer);
CREATE SEQUENCE public.gativx_default_privilege_probe_postgres_seq;
CREATE FUNCTION public.gativx_default_privilege_probe_postgres_fn()
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT 1;
$function$;

SET ROLE supabase_admin;
CREATE TABLE public.gativx_default_privilege_probe_supabase_admin (id integer);
CREATE SEQUENCE public.gativx_default_privilege_probe_supabase_admin_seq;
CREATE FUNCTION public.gativx_default_privilege_probe_supabase_admin_fn()
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT 1;
$function$;
RESET ROLE;

CREATE FUNCTION storage.gativx_default_privilege_probe_storage_fn()
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT 1;
$function$;

SET ROLE supabase_admin;
CREATE FUNCTION graphql.gativx_default_privilege_probe_graphql_fn()
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT 1;
$function$;
RESET ROLE;

DO $
DECLARE
    v_table text;
    v_sequence text;
    v_function text;
BEGIN
    FOREACH v_table IN ARRAY ARRAY[
        'public.gativx_default_privilege_probe_postgres',
        'public.gativx_default_privilege_probe_supabase_admin'
    ] LOOP
        IF has_table_privilege('anon', v_table, 'SELECT')
           OR has_table_privilege('anon', v_table, 'INSERT')
           OR has_table_privilege('anon', v_table, 'UPDATE')
           OR has_table_privilege('anon', v_table, 'DELETE')
           OR has_table_privilege('anon', v_table, 'TRUNCATE')
           OR has_table_privilege('anon', v_table, 'TRIGGER')
           OR has_table_privilege('anon', v_table, 'REFERENCES')
           OR has_table_privilege('authenticated', v_table, 'SELECT')
           OR has_table_privilege('authenticated', v_table, 'INSERT')
           OR has_table_privilege('authenticated', v_table, 'UPDATE')
           OR has_table_privilege('authenticated', v_table, 'DELETE')
           OR has_table_privilege('authenticated', v_table, 'TRUNCATE')
           OR has_table_privilege('authenticated', v_table, 'TRIGGER')
           OR has_table_privilege('authenticated', v_table, 'REFERENCES') THEN
            RAISE EXCEPTION 'A client role inherited privileges on future table %', v_table;
        END IF;

        IF NOT has_table_privilege('service_role', v_table, 'SELECT')
           OR NOT has_table_privilege('service_role', v_table, 'TRUNCATE') THEN
            RAISE EXCEPTION 'service_role default table privileges were unexpectedly removed from %', v_table;
        END IF;
    END LOOP;

    FOREACH v_sequence IN ARRAY ARRAY[
        'public.gativx_default_privilege_probe_postgres_seq',
        'public.gativx_default_privilege_probe_supabase_admin_seq'
    ] LOOP
        IF has_sequence_privilege('anon', v_sequence, 'USAGE')
           OR has_sequence_privilege('anon', v_sequence, 'SELECT')
           OR has_sequence_privilege('anon', v_sequence, 'UPDATE')
           OR has_sequence_privilege('authenticated', v_sequence, 'USAGE')
           OR has_sequence_privilege('authenticated', v_sequence, 'SELECT')
           OR has_sequence_privilege('authenticated', v_sequence, 'UPDATE') THEN
            RAISE EXCEPTION 'A client role inherited privileges on future sequence %', v_sequence;
        END IF;

        IF NOT has_sequence_privilege('service_role', v_sequence, 'USAGE') THEN
            RAISE EXCEPTION 'service_role default sequence privileges were unexpectedly removed from %', v_sequence;
        END IF;
    END LOOP;

    FOREACH v_function IN ARRAY ARRAY[
        'public.gativx_default_privilege_probe_postgres_fn()',
        'public.gativx_default_privilege_probe_supabase_admin_fn()'
    ] LOOP
        IF has_function_privilege('anon', v_function, 'EXECUTE')
           OR has_function_privilege('authenticated', v_function, 'EXECUTE') THEN
            RAISE EXCEPTION 'A client role inherited EXECUTE on future function %', v_function;
        END IF;

        IF NOT has_function_privilege('service_role', v_function, 'EXECUTE') THEN
            RAISE EXCEPTION 'service_role default function privilege was unexpectedly removed from %', v_function;
        END IF;
    END LOOP;

    -- Global PUBLIC EXECUTE is removed, but existing schema-specific defaults
    -- outside public remain for the Supabase roles that already had them.
    IF NOT has_function_privilege('anon', 'storage.gativx_default_privilege_probe_storage_fn()', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'storage.gativx_default_privilege_probe_storage_fn()', 'EXECUTE')
       OR NOT has_function_privilege('service_role', 'storage.gativx_default_privilege_probe_storage_fn()', 'EXECUTE')
       OR has_function_privilege('untrusted_client', 'storage.gativx_default_privilege_probe_storage_fn()', 'EXECUTE') THEN
        RAISE EXCEPTION 'postgres storage-specific function defaults changed unexpectedly';
    END IF;

    IF NOT has_function_privilege('anon', 'graphql.gativx_default_privilege_probe_graphql_fn()', 'EXECUTE')
       OR NOT has_function_privilege('authenticated', 'graphql.gativx_default_privilege_probe_graphql_fn()', 'EXECUTE')
       OR NOT has_function_privilege('service_role', 'graphql.gativx_default_privilege_probe_graphql_fn()', 'EXECUTE')
       OR has_function_privilege('untrusted_client', 'graphql.gativx_default_privilege_probe_graphql_fn()', 'EXECUTE') THEN
        RAISE EXCEPTION 'supabase_admin graphql-specific function defaults changed unexpectedly';
    END IF;
END;
$;

DROP FUNCTION public.gativx_default_privilege_probe_postgres_fn();
DROP FUNCTION public.gativx_default_privilege_probe_supabase_admin_fn();
DROP FUNCTION storage.gativx_default_privilege_probe_storage_fn();
DROP FUNCTION graphql.gativx_default_privilege_probe_graphql_fn();
DROP SEQUENCE public.gativx_default_privilege_probe_postgres_seq;
DROP SEQUENCE public.gativx_default_privilege_probe_supabase_admin_seq;
DROP TABLE public.gativx_default_privilege_probe_postgres;
DROP TABLE public.gativx_default_privilege_probe_supabase_admin;
