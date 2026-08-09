begin;

create table if not exists community_posts (
  id text primary key,
  owner_hash text not null,
  alias text not null check (char_length(alias) between 2 and 24),
  area_id text not null,
  area_name text not null,
  subject text not null,
  sound_type text not null,
  observed_at timestamptz not null,
  created_at timestamptz not null default now(),
  audio_url text not null,
  duration_ms integer not null check (duration_ms between 500 and 20000),
  candidate_names jsonb not null default '[]'::jsonb,
  field_observations jsonb not null default '[]'::jsonb,
  model_snapshot jsonb not null default '{}'::jsonb,
  status text not null check (status in ('published_unverified','community_supported','expert_confirmed','withdrawn')),
  review_status text not null check (review_status in ('not_requested','queued','confirmed','unable_to_confirm')),
  withdrawn_at timestamptz
);

create index if not exists community_posts_public_area_created_idx
  on community_posts (area_id, created_at desc) where status <> 'withdrawn';

create table if not exists community_consents (
  post_id text primary key references community_posts(id) on delete cascade,
  adult_confirmed boolean not null,
  public_consent boolean not null,
  review_consent boolean not null default false,
  consented_at timestamptz not null default now()
);

create table if not exists community_responses (
  id text primary key,
  post_id text not null references community_posts(id) on delete cascade,
  responder_hash text not null,
  choice text not null,
  also_heard boolean not null default false,
  key_second integer check (key_second between 0 and 20),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (post_id, responder_hash)
);

create or replace view community_public_posts as
select
  p.*,
  coalesce(sum(r.choice_count), 0)::integer as response_count,
  coalesce(
    jsonb_object_agg(r.choice, r.choice_count) filter (where r.choice is not null),
    '{}'::jsonb
  ) as response_summary
from community_posts p
left join (
  select post_id, choice, count(*)::integer as choice_count
  from community_responses
  group by post_id, choice
) r on r.post_id = p.id
where p.status <> 'withdrawn'
group by p.id;

create or replace view community_area_summaries as
select
  area_id,
  min(area_name) as area_name,
  count(*)::integer as post_count,
  count(*) filter (where not exists (
    select 1 from community_responses r where r.post_id = community_posts.id
  ))::integer as waiting_count,
  array_agg(distinct sound_type) as sound_types
from community_posts
where status <> 'withdrawn'
group by area_id;

commit;
