begin;

create table if not exists community_parent_guidance_cache (
  identity_hash text not null,
  request_fingerprint text not null,
  response_payload jsonb,
  status text not null default 'pending' check (status in ('pending', 'completed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (identity_hash, request_fingerprint)
);

create index if not exists community_parent_guidance_cache_updated_idx
  on community_parent_guidance_cache (updated_at desc);

comment on table community_parent_guidance_cache is
  'Idempotent AI parent-guidance results keyed by anonymous identity and evidence fingerprint.';

commit;
