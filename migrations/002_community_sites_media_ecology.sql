begin;

alter table community_posts add column if not exists park_id text;
alter table community_posts add column if not exists zone_id text;
alter table community_posts add column if not exists site_id text;
alter table community_posts add column if not exists sampling_mode text not null default 'opportunistic';
alter table community_posts add column if not exists sampling_effort jsonb not null default '{}'::jsonb;
alter table community_posts add column if not exists audio_quality jsonb not null default '{}'::jsonb;
alter table community_posts add column if not exists ecology_eligible boolean not null default true;

-- PostgreSQL views keep the column shape from creation time. Recreate the
-- public projection so park/site and evidence fields are returned by the API.
drop view if exists community_public_posts;
create view community_public_posts as
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

create table if not exists community_sites (
  id text primary key,
  park_id text not null,
  park_name text not null,
  zone_id text not null,
  zone_name text not null,
  area_id text not null,
  area_name text not null,
  public_lat double precision not null,
  public_lng double precision not null,
  habitat_tags jsonb not null default '[]'::jsonb,
  sensitive_location_policy text not null default 'park_zone',
  active boolean not null default true,
  unique (park_id, zone_id)
);

create table if not exists community_media_assets (
  id text primary key,
  post_id text not null references community_posts(id) on delete cascade,
  media_type text not null check (media_type in ('audio','image','video','thumbnail')),
  source_type text not null check (source_type in ('original','ai_generated','composed')),
  storage_url text not null,
  thumbnail_url text,
  provider text,
  model text,
  moderation_status text not null default 'approved'
    check (moderation_status in ('pending','approved','rejected')),
  created_at timestamptz not null default now()
);

create index if not exists community_posts_park_zone_created_idx
  on community_posts (park_id, zone_id, created_at desc)
  where status <> 'withdrawn';

create index if not exists community_media_assets_post_idx
  on community_media_assets (post_id, created_at);

insert into community_sites
  (id, park_id, park_name, zone_id, zone_name, area_id, area_name,
   public_lat, public_lng, habitat_tags)
values
  ('hangzhou-botanical-garden:lingfeng-entrance','hangzhou-botanical-garden','杭州植物园','lingfeng-entrance','灵峰入口','xihu','西湖区',30.252,120.118,'["林缘","入口"]'::jsonb),
  ('hangzhou-botanical-garden:understory-trail','hangzhou-botanical-garden','杭州植物园','understory-trail','林下步道','xihu','西湖区',30.252,120.118,'["林下","树冠"]'::jsonb),
  ('hangzhou-botanical-garden:aquatic-edge','hangzhou-botanical-garden','杭州植物园','aquatic-edge','水生植物区外围','xihu','西湖区',30.252,120.118,'["水边","湿地"]'::jsonb),
  ('xixi-wetland:wetland-boardwalk','xixi-wetland','西溪湿地','wetland-boardwalk','湿地步道','xihu','西湖区',30.273,120.061,'["步道","水边"]'::jsonb),
  ('xixi-wetland:reed-edge','xixi-wetland','西溪湿地','reed-edge','芦苇外围','xihu','西湖区',30.273,120.061,'["芦苇","浅水"]'::jsonb),
  ('xixi-wetland:woodland-island','xixi-wetland','西溪湿地','woodland-island','林地岛外围','xihu','西湖区',30.273,120.061,'["林地","灌木"]'::jsonb),
  ('taiziwan-park:main-lawn','taiziwan-park','太子湾公园','main-lawn','中心草地区','xihu','西湖区',30.226,120.143,'["草地","开阔地"]'::jsonb),
  ('taiziwan-park:stream-trail','taiziwan-park','太子湾公园','stream-trail','溪流步道','xihu','西湖区',30.226,120.143,'["流水","步道"]'::jsonb),
  ('taiziwan-park:woodland-slope','taiziwan-park','太子湾公园','woodland-slope','林缘缓坡','xihu','西湖区',30.226,120.143,'["林缘","灌木"]'::jsonb)
on conflict (id) do update set
  park_name=excluded.park_name,
  zone_name=excluded.zone_name,
  habitat_tags=excluded.habitat_tags,
  active=true;

commit;
