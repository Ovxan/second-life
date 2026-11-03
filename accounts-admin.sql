-- Owner dashboard and restricted repair-service writes to approved, password-authenticated site owners.
-- Leaves existing sale/donation ownership and all listing data intact.
begin;
create table public.site_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.site_admins enable row level security;
revoke all on public.site_admins from public, anon, authenticated;

create function public.has_registered_account() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from auth.users u where u.id = (select auth.uid())
    and u.is_anonymous is false and u.email_confirmed_at is not null
    and coalesce(u.encrypted_password,'') <> '');
$$;
revoke all on function public.has_registered_account() from public;
grant execute on function public.has_registered_account() to anon, authenticated;

create function public.is_site_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select (select auth.uid()) is not null
    and (select public.has_registered_account())
    and exists (select 1 from public.site_admins where user_id = (select auth.uid()));
$$;
revoke all on function public.is_site_admin() from public;
grant execute on function public.is_site_admin() to anon, authenticated;

-- Registration is required even when clients call the public API directly.
create policy "Registered accounts insert listings" on public.listings
as restrictive for insert to authenticated with check ((select public.has_registered_account()));
create policy "Registered accounts update listings" on public.listings
as restrictive for update to authenticated using ((select public.has_registered_account()))
with check ((select public.has_registered_account()));
create policy "Registered accounts delete listings" on public.listings
as restrictive for delete to authenticated using ((select public.has_registered_account()));
create policy "Registered accounts save favorites" on public.favorites
as restrictive for insert to authenticated with check ((select public.has_registered_account()));
create policy "Registered accounts remove favorites" on public.favorites
as restrictive for delete to authenticated using ((select public.has_registered_account()));
create policy "Registered accounts upload photos" on storage.objects
as restrictive for insert to authenticated with check ((select public.has_registered_account()));
create policy "Registered accounts remove photos" on storage.objects
as restrictive for delete to authenticated using ((select public.has_registered_account()));

-- Restrictive policies AND with all existing owner policies. A new permissive
-- policy cannot accidentally let guests or ordinary accounts post services.
create policy "Repair inserts require approved admin" on public.listings
as restrictive for insert to authenticated
with check (kind <> 'jasa' or (select public.is_site_admin()));
create policy "Repair updates require approved admin" on public.listings
as restrictive for update to authenticated
using (kind <> 'jasa' or (select public.is_site_admin()))
with check (kind <> 'jasa' or (select public.is_site_admin()));
create policy "Repair deletes require approved admin" on public.listings
as restrictive for delete to authenticated
using (kind <> 'jasa' or (select public.is_site_admin()));
create policy "Closed repairs are admin only" on public.listings
as restrictive for select to anon, authenticated
using (kind <> 'jasa' or status = 'Tersedia' or (select public.is_site_admin()));
-- Owners may moderate the whole marketplace; other users retain only their own
-- sale/donation access. Favorites and the auth user directory are not exposed.
create policy "Site admins read all listings" on public.listings for select to authenticated
using ((select public.is_site_admin()));
create policy "Site admins update listings" on public.listings for update to authenticated
using ((select public.is_site_admin())) with check ((select public.is_site_admin()));
create policy "Site admins delete listings" on public.listings for delete to authenticated
using ((select public.is_site_admin()));

-- A moderator can replace a photo using one uploaded by their own identity,
-- while the listing's original owner stays unchanged.
alter table public.listings drop constraint listing_photo_is_owned;
alter table public.listings add constraint listing_photo_path_format check
(photo_path = '' or photo_path ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|jpeg|png|webp)$');
create function public.check_listing_photo_actor() returns trigger
language plpgsql set search_path = '' as $$
begin
  if TG_OP = 'INSERT' or NEW.photo_path is distinct from OLD.photo_path then
    if NEW.photo_path <> '' and split_part(NEW.photo_path,'/',1) is distinct from (select auth.uid())::text then
      raise exception 'Gunakan foto yang diunggah melalui sesi Anda sendiri.' using errcode='42501';
    end if;
  end if;
  return NEW;
end;
$$;
revoke all on function public.check_listing_photo_actor() from public, anon, authenticated;
create trigger listings_photo_actor before insert or update on public.listings
for each row execute function public.check_listing_photo_actor();
create policy "Site admins read photo metadata" on storage.objects for select to authenticated
using (bucket_id='second-life-photos' and (select public.is_site_admin()));
create policy "Site admins remove unused photos" on storage.objects for delete to authenticated
using (bucket_id='second-life-photos' and (select public.is_site_admin()));
commit;
