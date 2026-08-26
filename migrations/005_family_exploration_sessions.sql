begin;

create table if not exists family_exploration_sessions (
  id text primary key,
  parent_hash text not null,
  child_hash text,
  status text not null check (status in (
    'waiting_for_child','pending_approval','active','ended','expired'
  )),
  pair_code_hash text not null,
  pair_code_lookup_hash text not null,
  pair_expires_at timestamptz not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  child_joined_at timestamptz,
  approved_at timestamptz,
  ended_at timestamptz
);

create index if not exists idx_family_sessions_parent
  on family_exploration_sessions (parent_hash, created_at desc);
create index if not exists idx_family_sessions_child
  on family_exploration_sessions (child_hash, created_at desc)
  where child_hash is not null;
create index if not exists idx_family_sessions_pair_lookup
  on family_exploration_sessions (pair_code_lookup_hash, pair_expires_at desc);

create table if not exists family_exploration_events (
  event_id text primary key,
  session_id text not null references family_exploration_sessions(id) on delete cascade,
  sequence integer not null check (sequence > 0),
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  unique (session_id, sequence)
);

create index if not exists idx_family_events_session_sequence
  on family_exploration_events (session_id, sequence);

create table if not exists family_session_commands (
  command_id text primary key,
  session_id text not null references family_exploration_sessions(id) on delete cascade,
  sequence integer not null check (sequence > 0),
  template_id text not null,
  created_at timestamptz not null default now(),
  delivered_at timestamptz,
  unique (session_id, sequence)
);

create index if not exists idx_family_commands_session_sequence
  on family_session_commands (session_id, sequence);

commit;
