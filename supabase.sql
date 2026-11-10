-- R7 Key Generator: execute todo este arquivo no SQL Editor do Supabase.
-- As tabelas não ficam acessíveis diretamente a visitantes; somente o backend usa a chave secreta.

create extension if not exists pgcrypto;

create table if not exists public.key_sessions (
  id uuid primary key default gen_random_uuid(),
  mission integer not null default 0 check (mission between 0 and 4),
  mission_started_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  key_hash text unique
);

create table if not exists public.generated_keys (
  key_hash text primary key,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  claimed_user_id bigint,
  claimed_at timestamptz
);

alter table public.key_sessions enable row level security;
alter table public.generated_keys enable row level security;

revoke all on public.key_sessions from anon, authenticated;
revoke all on public.generated_keys from anon, authenticated;
grant all on public.key_sessions to service_role;
grant all on public.generated_keys to service_role;

create or replace function public.start_key_session()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare new_id uuid;
begin
  insert into public.key_sessions default values returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.get_key_session_status(p_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.key_sessions%rowtype;
  remaining bigint;
  expires timestamptz;
begin
  select * into s from public.key_sessions where id = p_session_id;
  if not found then return jsonb_build_object('error', 'NOT_FOUND'); end if;

  if s.mission >= 4 and s.key_hash is not null then
    select expires_at into expires from public.generated_keys where key_hash = s.key_hash;
    return jsonb_build_object('completed', true, 'expires_at', expires);
  end if;

  remaining := greatest(0, 120000 - floor(extract(epoch from (now() - s.mission_started_at)) * 1000)::bigint);
  return jsonb_build_object(
    'completed', false,
    'mission', s.mission + 1,
    'completed_missions', s.mission,
    'remaining_ms', remaining,
    'can_continue', remaining = 0
  );
end;
$$;

create or replace function public.complete_key_mission(p_session_id uuid, p_key_hash text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.key_sessions%rowtype;
  next_mission integer;
  expiry timestamptz;
begin
  select * into s from public.key_sessions where id = p_session_id for update;
  if not found then return jsonb_build_object('error', 'NOT_FOUND'); end if;

  if s.mission >= 4 and s.key_hash is not null then
    select expires_at into expiry from public.generated_keys where key_hash = s.key_hash;
    return jsonb_build_object('completed', true, 'expires_at', expiry);
  end if;

  if now() < s.mission_started_at + interval '2 minutes' then
    raise exception 'WAIT: mission timer has not finished';
  end if;

  next_mission := s.mission + 1;
  if next_mission = 4 then
    expiry := now() + interval '24 hours';
    insert into public.generated_keys(key_hash, expires_at) values (p_key_hash, expiry);
    update public.key_sessions set mission = 4, key_hash = p_key_hash where id = p_session_id;
    return jsonb_build_object('completed', true, 'expires_at', expiry);
  end if;

  update public.key_sessions
    set mission = next_mission, mission_started_at = now()
    where id = p_session_id;

  return jsonb_build_object(
    'completed', false,
    'mission', next_mission + 1,
    'completed_missions', next_mission
  );
end;
$$;

create or replace function public.validate_generated_key(p_key_hash text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare expiry timestamptz;
begin
  select expires_at into expiry
  from public.generated_keys
  where key_hash = p_key_hash;

  if not found then return jsonb_build_object('valid', false, 'reason', 'KEY não encontrada.'); end if;
  if now() >= expiry then return jsonb_build_object('valid', false, 'reason', 'KEY expirada.'); end if;

  return jsonb_build_object('valid', true, 'expires_at', expiry);
end;
$$;

revoke all on function public.start_key_session() from public, anon, authenticated;
revoke all on function public.get_key_session_status(uuid) from public, anon, authenticated;
revoke all on function public.complete_key_mission(uuid, text) from public, anon, authenticated;
revoke all on function public.validate_generated_key(text) from public, anon, authenticated;

grant execute on function public.start_key_session() to service_role;
grant execute on function public.get_key_session_status(uuid) to service_role;
grant execute on function public.complete_key_mission(uuid, text) to service_role;
grant execute on function public.validate_generated_key(text) to service_role;
