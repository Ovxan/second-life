-- Second Life: shared catalog, private favorites and owner-scoped photos.
-- Apply once to a new Supabase project. No user data is seeded here.
begin;

create table public.listings (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind text not null check (kind in ('jual','donasi','jasa')),
  title text not null check (char_length(btrim(title)) between 5 and 100),
  category text not null check (category in ('Furnitur','Elektronik','Buku & Kuliah','Perlengkapan Kos','Fashion & Hobi')),
  description text not null check (char_length(btrim(description)) between 20 and 3000),
  condition text not null check (condition in ('Seperti baru','Baik','Cukup baik','Perlu perbaikan')),
  location text not null check (char_length(btrim(location)) between 3 and 120),
  price bigint not null default 0 check (price between 0 and 100000000),
  photo_path text not null default '',
  seller_name text not null check (char_length(btrim(seller_name)) between 2 and 70),
  phone text not null check (phone ~ '^628[0-9]{7,11}$'),
  status text not null default 'Tersedia',
  source_id text check (source_id is null or char_length(source_id) between 1 and 64),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint listing_price_matches_kind check ((kind = 'jual' and price >= 1000) or (kind in ('donasi','jasa') and price = 0)),
  constraint listing_photo_required check (kind = 'jasa' or photo_path <> ''),
  constraint listing_photo_is_owned check (photo_path = '' or (split_part(photo_path,'/',1) = owner_id::text and photo_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|jpeg|png|webp)$')),
  constraint listing_status_matches_kind check ((kind='jual' and status in ('Tersedia','Dalam proses','Terjual')) or (kind='donasi' and status in ('Tersedia','Dalam proses','Tersalurkan')) or (kind='jasa' and status in ('Tersedia','Nonaktif'))),
  unique(owner_id, source_id)
);
create index listings_created_at_idx on public.listings(created_at desc);
create index listings_owner_id_idx on public.listings(owner_id);
create index listings_catalog_idx on public.listings(kind, status, category);

create table public.favorites (
  owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  listing_id uuid not null references public.listings(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(owner_id, listing_id)
);
create index favorites_listing_id_idx on public.favorites(listing_id);

alter table public.listings enable row level security;
alter table public.favorites enable row level security;
revoke all on public.listings, public.favorites from public, anon, authenticated;
grant usage on schema public to anon, authenticated;
grant select on public.listings to anon, authenticated;
grant insert (kind,title,category,description,condition,location,price,photo_path,seller_name,phone,source_id) on public.listings to authenticated;
grant update (title,category,description,condition,location,price,photo_path,seller_name,phone,status) on public.listings to authenticated;
grant delete on public.listings to authenticated;
grant select, delete on public.favorites to authenticated;
grant insert (listing_id) on public.favorites to authenticated;

create policy "Public can read active listings" on public.listings for select to anon, authenticated using (status in ('Tersedia','Dalam proses'));
create policy "Owners can read all their listings" on public.listings for select to authenticated using ((select auth.uid()) = owner_id);
create policy "Owners can insert listings" on public.listings for insert to authenticated with check ((select auth.uid()) = owner_id);
create policy "Owners can update listings" on public.listings for update to authenticated using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
create policy "Owners can delete listings" on public.listings for delete to authenticated using ((select auth.uid()) = owner_id);
create policy "Favorites are private" on public.favorites for select to authenticated using ((select auth.uid()) = owner_id);
create policy "Owners can add favorites" on public.favorites for insert to authenticated with check ((select auth.uid()) = owner_id and exists (select 1 from public.listings l where l.id = listing_id));
create policy "Owners can delete favorites" on public.favorites for delete to authenticated using ((select auth.uid()) = owner_id);

create function public.check_listing_write() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if TG_OP = 'INSERT' then
    perform pg_advisory_xact_lock(hashtextextended('second-life:' || NEW.owner_id::text,0));
    if (select count(*) from public.listings where owner_id=NEW.owner_id) >= 100 then
      raise exception 'Batas 100 iklan per pemilik telah tercapai.' using errcode='P0001';
    end if;
    if (select count(*) from public.listings where owner_id=NEW.owner_id and created_at>now()-interval '1 hour') >= 20 then
      raise exception 'Terlalu banyak iklan baru. Coba lagi beberapa saat lagi.' using errcode='P0001';
    end if;
  else
    NEW.id := OLD.id; NEW.owner_id := OLD.owner_id; NEW.kind := OLD.kind; NEW.created_at := OLD.created_at; NEW.source_id := OLD.source_id;
  end if;
  NEW.updated_at := now();
  return NEW;
end;
$$;
revoke all on function public.check_listing_write() from public, anon, authenticated;
create trigger listings_guard before insert or update on public.listings for each row execute function public.check_listing_write();

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('second-life-photos','second-life-photos',true,2097152,array['image/jpeg','image/png','image/webp']);
create policy "Second Life photo uploads are owned" on storage.objects for insert to authenticated with check (bucket_id='second-life-photos' and (storage.foldername(name))[1]=(select auth.uid())::text and lower(storage.extension(name)) in ('jpg','jpeg','png','webp'));
create policy "Second Life owners can read photo metadata" on storage.objects for select to authenticated using (bucket_id='second-life-photos' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "Second Life owners can remove their photos" on storage.objects for delete to authenticated using (bucket_id='second-life-photos' and (storage.foldername(name))[1]=(select auth.uid())::text);

-- Realtime notifications refresh the catalog in open browsers.
do $$ begin
  if exists (select 1 from pg_publication where pubname='supabase_realtime') and not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='listings') then
    alter publication supabase_realtime add table public.listings;
  end if;
end $$;
commit;
