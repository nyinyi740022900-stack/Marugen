-- Local PostgreSQL only. Runs right after sprint1_bootstrap.sql, before any
-- migration: the two pg_net pieces migration 0080 looks at, which the
-- shared bootstrap does not need. Nothing here talks to a network.
\set ON_ERROR_STOP on
set client_min_messages = warning;
-- pg_net hands out one id per request; the shared stand-in always said 1.
create sequence net.http_request_queue_id_seq;
create or replace function net.http_post(url text, headers jsonb, body jsonb) returns bigint
language sql as $$ select nextval('net.http_request_queue_id_seq'); $$;
-- Same columns as pg_net's response table.
create table net._http_response (
  id bigint, status_code integer, content_type text, headers jsonb,
  content text, timed_out boolean, error_msg text,
  created timestamptz not null default now()
);
