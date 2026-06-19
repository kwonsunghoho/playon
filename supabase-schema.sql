-- Playon admin/database setup for Supabase
-- Run this entire file once in Supabase > SQL Editor.

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admin_users where user_id = auth.uid()
  );
$$;

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  legacy_key text unique,
  name text not null,
  category text not null check (category in ('스포츠','비디오','슈팅','리듬','키즈','인형뽑기')),
  description text not null default '',
  image_url text,
  rental_enabled boolean not null default true,
  sale_enabled boolean not null default false,
  rental_price integer check (rental_price is null or rental_price >= 0),
  sale_price integer check (sale_price is null or sale_price >= 0),
  price_note text not null default '',
  stock_total integer not null default 1 check (stock_total >= 0),
  stock_maintenance integer not null default 0 check (stock_maintenance >= 0),
  visible boolean not null default true,
  featured boolean not null default false,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (rental_enabled or sale_enabled),
  check (stock_maintenance <= stock_total)
);

create table if not exists public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  image_url text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.inquiries (
  id uuid primary key default gen_random_uuid(),
  company text not null,
  contact_name text not null,
  phone text not null,
  event_date date,
  place text not null default '',
  memo text not null default '',
  status text not null default 'new' check (status in ('new','contacted','quoted','confirmed','closed')),
  privacy_agreed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.inquiry_items (
  id uuid primary key default gen_random_uuid(),
  inquiry_id uuid not null references public.inquiries(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  quantity integer not null default 1 check (quantity > 0),
  created_at timestamptz not null default now()
);

create table if not exists public.reservations (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  inquiry_id uuid references public.inquiries(id) on delete set null,
  start_date date not null,
  end_date date not null,
  quantity integer not null check (quantity > 0),
  status text not null default 'hold' check (status in ('hold','confirmed','completed','cancelled')),
  memo text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_date >= start_date)
);

create table if not exists public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  movement_type text not null check (movement_type in ('purchase','sale','repair_in','repair_out','loss','adjustment')),
  quantity integer not null,
  memo text not null default '',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

drop trigger if exists products_set_updated_at on public.products;
create trigger products_set_updated_at before update on public.products
for each row execute function public.set_updated_at();
drop trigger if exists inquiries_set_updated_at on public.inquiries;
create trigger inquiries_set_updated_at before update on public.inquiries
for each row execute function public.set_updated_at();
drop trigger if exists reservations_set_updated_at on public.reservations;
create trigger reservations_set_updated_at before update on public.reservations
for each row execute function public.set_updated_at();

alter table public.admin_users enable row level security;
alter table public.products enable row level security;
alter table public.product_images enable row level security;
alter table public.inquiries enable row level security;
alter table public.inquiry_items enable row level security;
alter table public.reservations enable row level security;
alter table public.inventory_movements enable row level security;

drop policy if exists "admins can read admin list" on public.admin_users;
drop policy if exists "public can read visible products" on public.products;
drop policy if exists "admins can insert products" on public.products;
drop policy if exists "admins can update products" on public.products;
drop policy if exists "admins can delete products" on public.products;
drop policy if exists "public can read product images" on public.product_images;
drop policy if exists "admins manage product images" on public.product_images;
drop policy if exists "visitors create inquiries" on public.inquiries;
drop policy if exists "admins manage inquiries" on public.inquiries;
drop policy if exists "visitors create inquiry items" on public.inquiry_items;
drop policy if exists "admins manage inquiry items" on public.inquiry_items;
drop policy if exists "admins manage reservations" on public.reservations;
drop policy if exists "admins manage inventory" on public.inventory_movements;
create policy "admins can read admin list" on public.admin_users for select using (public.is_admin());
create policy "public can read visible products" on public.products for select using (visible or public.is_admin());
create policy "admins can insert products" on public.products for insert with check (public.is_admin());
create policy "admins can update products" on public.products for update using (public.is_admin()) with check (public.is_admin());
create policy "admins can delete products" on public.products for delete using (public.is_admin());
create policy "public can read product images" on public.product_images for select using (true);
create policy "admins manage product images" on public.product_images for all using (public.is_admin()) with check (public.is_admin());
create policy "admins manage inquiries" on public.inquiries for all using (public.is_admin()) with check (public.is_admin());
create policy "admins manage inquiry items" on public.inquiry_items for all using (public.is_admin()) with check (public.is_admin());
create policy "admins manage reservations" on public.reservations for all using (public.is_admin()) with check (public.is_admin());
create policy "admins manage inventory" on public.inventory_movements for all using (public.is_admin()) with check (public.is_admin());

insert into storage.buckets (id, name, public)
values ('product-images','product-images',true)
on conflict (id) do update set public = true;

drop policy if exists "public reads product image files" on storage.objects;
drop policy if exists "admins upload product image files" on storage.objects;
drop policy if exists "admins update product image files" on storage.objects;
drop policy if exists "admins delete product image files" on storage.objects;
create policy "public reads product image files" on storage.objects for select using (bucket_id = 'product-images');
create policy "admins upload product image files" on storage.objects for insert with check (bucket_id = 'product-images' and public.is_admin());
create policy "admins update product image files" on storage.objects for update using (bucket_id = 'product-images' and public.is_admin());
create policy "admins delete product image files" on storage.objects for delete using (bucket_id = 'product-images' and public.is_admin());

-- Public inquiries are accepted through one validated transaction instead of direct table writes.
create or replace function public.submit_inquiry(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_inquiry_id uuid;
  item jsonb;
  item_product_id uuid;
begin
  if coalesce((p_payload->>'privacy_agreed')::boolean,false) is not true then
    raise exception '개인정보 수집 동의가 필요합니다.';
  end if;
  if length(trim(coalesce(p_payload->>'company',''))) not between 1 and 100
     or length(trim(coalesce(p_payload->>'contact_name',''))) not between 1 and 100
     or length(trim(coalesce(p_payload->>'phone',''))) not between 5 and 30 then
    raise exception '필수 문의 정보를 확인해 주세요.';
  end if;
  insert into public.inquiries(company,contact_name,phone,event_date,place,memo,privacy_agreed)
  values (
    left(trim(p_payload->>'company'),100),
    left(trim(p_payload->>'contact_name'),100),
    left(trim(p_payload->>'phone'),30),
    nullif(p_payload->>'event_date','')::date,
    left(trim(coalesce(p_payload->>'place','')),200),
    left(trim(coalesce(p_payload->>'memo','')),3000),
    true
  ) returning id into new_inquiry_id;
  for item in select value from jsonb_array_elements(coalesce(p_payload->'items','[]'::jsonb)) loop
    item_product_id := case when coalesce(item->>'product_id','') ~* '^[0-9a-f-]{36}$' then (item->>'product_id')::uuid else null end;
    insert into public.inquiry_items(inquiry_id,product_id,product_name,quantity)
    values (new_inquiry_id,item_product_id,left(coalesce(item->>'product_name','상품'),150),greatest(1,least(100,coalesce((item->>'quantity')::integer,1))));
  end loop;
  return new_inquiry_id;
end;
$$;
revoke all on function public.submit_inquiry(jsonb) from public;
grant execute on function public.submit_inquiry(jsonb) to anon, authenticated;

-- Initial 32 products. Existing rows are preserved when this script is rerun.
insert into public.products (legacy_key,name,category,rental_enabled,sale_enabled,sort_order)
values
('스포츠-0','썬더SD 해머','스포츠',true,false,10),
('스포츠-1','비트앤덩크','스포츠',true,false,20),
('스포츠-2','슈퍼루키2','스포츠',true,false,30),
('스포츠-3','타겟헌터 비비탄 사격기','스포츠',true,true,40),
('스포츠-4','픽셀크래프트','스포츠',true,true,50),
('스포츠-5','10초를 잡아라','스포츠',true,false,60),
('비디오-0','데드히트라이더','비디오',true,false,70),
('비디오-1','이니셜D8','비디오',true,false,80),
('비디오-2','스마트메이커 천방지축','비디오',true,false,90),
('비디오-3','애벌레키우기','비디오',true,false,100),
('비디오-4','딥씨파티','비디오',true,false,110),
('비디오-5','더비시바시','비디오',true,false,120),
('비디오-6','히든캐치5','비디오',true,false,130),
('슈팅-0','아이스맨','슈팅',true,false,140),
('슈팅-1','다크이스케이프DX','슈팅',true,false,150),
('슈팅-2','데드스톰 스페셜DX','슈팅',true,false,160),
('슈팅-3','렛츠고 정글DX','슈팅',true,false,170),
('슈팅-4','라이징스톰','슈팅',true,false,180),
('슈팅-5','트랜스포머SD','슈팅',true,false,190),
('리듬-0','댄스러쉬스타덤','리듬',true,true,200),
('리듬-1','비트매니아2DX','리듬',true,true,210),
('리듬-2','펌프LX 프라임2','리듬',true,false,220),
('리듬-3','기타도라 드럼매니아','리듬',true,true,230),
('리듬-4','노스텔지어','리듬',true,true,240),
('키즈-0','어린이 포크레인','키즈',true,false,250),
('키즈-1','미니레이싱2','키즈',true,false,260),
('키즈-2','베이비원트레이싱','키즈',true,false,270),
('인형뽑기-0','럭셔리러브푸시 1200','인형뽑기',true,false,280),
('인형뽑기-1','해피트윈','인형뽑기',true,false,290),
('인형뽑기-2','요요파티','인형뽑기',true,false,300),
('인형뽑기-3','토이즈팝','인형뽑기',true,false,310),
('인형뽑기-4','럭셔리자이언트 2인용','인형뽑기',true,false,320)
on conflict (legacy_key) do nothing;

-- After creating an Auth user in Supabase, make it an admin once:
-- insert into public.admin_users(user_id)
-- select id from auth.users where email = 'YOUR_ADMIN_EMAIL';
