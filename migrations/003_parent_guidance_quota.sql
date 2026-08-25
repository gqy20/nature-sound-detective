begin;

create table if not exists community_parent_guidance_quotas (
  identity_hash text primary key,
  used_count integer not null default 0 check (used_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists community_parent_guidance_quotas_updated_idx
  on community_parent_guidance_quotas (updated_at desc);

comment on table community_parent_guidance_quotas is
  'Successful AI parent-guidance generations used by each anonymous identity.';

commit;
