-- Manual campus-document review. No KTP, NIM, biometric matching, or OTP is collected.
-- Existing listings and billing history are preserved. Only new listings require review.
begin;

create table public.campus_verifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  full_name text not null check (char_length(btrim(full_name)) between 2 and 70),
  campus text not null check (char_length(btrim(campus)) between 2 and 120),
  document_kind text not null check (document_kind in ('ktm','alumni')),
  document_path text generated always as (user_id::text || '/' || id::text || '.jpg') stored,
  status text not null default 'draft' check (status in ('draft','pending','approved','rejected','withdrawn','revoked')),
  consent_version text not null default 'campus-v1' check (consent_version='campus-v1'),
  consented_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  submitted_at timestamptz,
  reviewed_at timestamptz,
  reviewer_id uuid references auth.users(id) on delete set null,
  review_note text not null default '' check (char_length(review_note)<=300),
  withdrawn_at timestamptz,
  revoked_at timestamptz,
  revoker_id uuid references auth.users(id) on delete set null,
  revoke_note text not null default '' check (char_length(revoke_note)<=300),
  document_deleted_at timestamptz,
  check (status not in ('approved','rejected','revoked') or reviewed_at is not null)
);
create unique index campus_one_active_request on public.campus_verifications(user_id)
  where status in ('draft','pending','approved');
create index campus_request_owner_date on public.campus_verifications(user_id,created_at desc);
create index campus_review_queue on public.campus_verifications(status,created_at);
alter table public.campus_verifications enable row level security;
revoke all on public.campus_verifications from public,anon,authenticated;
grant select on public.campus_verifications to authenticated;
create policy "Campus requests are private" on public.campus_verifications for select to authenticated
using ((select public.has_registered_account()) and (user_id=(select auth.uid()) or (select public.is_site_admin())));

create function public.can_publish_listings() returns boolean
language sql stable security definer set search_path='' as $$
  select public.has_registered_account() and (public.is_site_admin() or exists(
    select 1 from public.campus_verifications where user_id=auth.uid() and status='approved'
  ));
$$;
revoke all on function public.can_publish_listings() from public,anon,authenticated;
grant execute on function public.can_publish_listings() to anon,authenticated;

create function public.campus_account_access() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_review public.campus_verifications%rowtype;
begin
  if not public.has_registered_account() then raise exception 'Konfirmasi email dan login terlebih dahulu.' using errcode='42501'; end if;
  select * into v_review from public.campus_verifications where user_id=auth.uid() and status='approved';
  return jsonb_build_object('can_publish',public.can_publish_listings(),'reviewed',found,
    'full_name',v_review.full_name,'campus',v_review.campus);
end;
$$;
revoke all on function public.campus_account_access() from public,anon,authenticated;
grant execute on function public.campus_account_access() to authenticated;

create function public.start_campus_verification(p_full_name text,p_campus text,p_document_kind text,p_consent boolean) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_user uuid:=auth.uid();
begin
  if not public.has_registered_account() then raise exception 'Konfirmasi email dan login sebelum mengajukan dokumen.' using errcode='42501'; end if;
  if p_consent is distinct from true then raise exception 'Persetujuan penggunaan dokumen diperlukan sebelum mengunggah.'; end if;
  if p_full_name is null or char_length(btrim(p_full_name)) not between 2 and 70
    or p_campus is null or char_length(btrim(p_campus)) not between 2 and 120
    or p_document_kind is null or p_document_kind not in ('ktm','alumni') then
    raise exception 'Isi nama, kampus, dan jenis dokumen KTM atau bukti alumni dengan benar.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('campus:'||v_user::text,0));
  if exists(select 1 from public.campus_verifications where user_id=v_user and status in ('draft','pending','approved')) then
    raise exception 'Masih ada pengajuan aktif. Selesaikan atau tarik pengajuan tersebut terlebih dahulu.';
  end if;
  if (select count(*) from public.campus_verifications where user_id=v_user and created_at>now()-interval '1 day')>=5 then
    raise exception 'Batas lima pengajuan per hari tercapai. Coba kembali besok.';
  end if;
  insert into public.campus_verifications(user_id,full_name,campus,document_kind)
    values(v_user,btrim(p_full_name),btrim(p_campus),p_document_kind) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.start_campus_verification(text,text,text,boolean) from public,anon,authenticated;
grant execute on function public.start_campus_verification(text,text,text,boolean) to authenticated;

create function public.submit_campus_verification(p_request_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_row public.campus_verifications%rowtype;
begin
  if not public.has_registered_account() then raise exception 'Login dengan akun pengaju terlebih dahulu.' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('campus:'||auth.uid()::text,0));
  select * into v_row from public.campus_verifications where id=p_request_id for update;
  if not found or v_row.user_id<>auth.uid() then raise exception 'Pengajuan ini bukan milik akun Anda.' using errcode='42501'; end if;
  if v_row.status='pending' then return; end if;
  if v_row.status<>'draft' or v_row.document_deleted_at is not null then raise exception 'Pengajuan ini tidak dapat dikirim ulang.'; end if;
  if not exists(select 1 from storage.objects where bucket_id='second-life-campus-documents' and name=v_row.document_path) then
    raise exception 'Unggah foto dokumen terlebih dahulu.';
  end if;
  update public.campus_verifications set status='pending',submitted_at=now() where id=p_request_id;
end;
$$;
revoke all on function public.submit_campus_verification(uuid) from public,anon,authenticated;
grant execute on function public.submit_campus_verification(uuid) to authenticated;

create function public.withdraw_campus_verification(p_request_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_row public.campus_verifications%rowtype;
begin
  if not public.has_registered_account() then raise exception 'Login dengan akun pengaju terlebih dahulu.' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('campus:'||auth.uid()::text,0));
  select * into v_row from public.campus_verifications where id=p_request_id for update;
  if not found or v_row.user_id<>auth.uid() then raise exception 'Pengajuan ini bukan milik akun Anda.' using errcode='42501'; end if;
  if v_row.status='withdrawn' then return; end if;
  if v_row.status not in ('draft','pending','approved') then raise exception 'Pengajuan sudah diputuskan. Anda dapat menghapus fotonya atau membuat pengajuan baru.'; end if;
  update public.campus_verifications set status='withdrawn',withdrawn_at=now() where id=p_request_id;
end;
$$;
revoke all on function public.withdraw_campus_verification(uuid) from public,anon,authenticated;
grant execute on function public.withdraw_campus_verification(uuid) to authenticated;

create function public.review_campus_verification(p_request_id uuid,p_approved boolean,p_note text) returns void
language plpgsql security definer set search_path='' as $$
declare v_row public.campus_verifications%rowtype; v_user uuid;
begin
  if not public.is_site_admin() then raise exception 'Pemeriksaan dokumen hanya tersedia untuk admin pemilik web.' using errcode='42501'; end if;
  select user_id into v_user from public.campus_verifications where id=p_request_id;
  if v_user=auth.uid() then raise exception 'Pengelola tidak dapat menyetujui dokumennya sendiri.' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('campus:'||v_user::text,0));
  select * into v_row from public.campus_verifications where id=p_request_id for update;
  if not found or v_row.status<>'pending' then raise exception 'Pengajuan ini tidak lagi menunggu pemeriksaan. Perbarui daftar terlebih dahulu.'; end if;
  if p_approved is null or p_note is null or char_length(btrim(p_note))>300
    or (not p_approved and char_length(btrim(p_note))<3) then raise exception 'Isi alasan perbaikan antara 3–300 karakter.'; end if;
  if p_approved and (v_row.document_deleted_at is not null or not exists(
    select 1 from storage.objects where bucket_id='second-life-campus-documents' and name=v_row.document_path
  )) then raise exception 'Foto dokumen tidak tersedia. Pengajuan tidak dapat disetujui.'; end if;
  update public.campus_verifications set status=case when p_approved then 'approved' else 'rejected' end,
    reviewed_at=now(),reviewer_id=auth.uid(),review_note=btrim(p_note) where id=p_request_id;
end;
$$;
revoke all on function public.review_campus_verification(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.review_campus_verification(uuid,boolean,text) to authenticated;

create function public.revoke_campus_verification(p_request_id uuid,p_note text) returns void
language plpgsql security definer set search_path='' as $$
declare v_user uuid;
begin
  if not public.is_site_admin() then raise exception 'Pencabutan persetujuan hanya tersedia untuk admin.' using errcode='42501'; end if;
  if p_note is null or char_length(btrim(p_note)) not between 3 and 300 then raise exception 'Isi alasan pencabutan antara 3–300 karakter.'; end if;
  select user_id into v_user from public.campus_verifications where id=p_request_id;
  perform pg_advisory_xact_lock(hashtextextended('campus:'||v_user::text,0));
  perform 1 from public.campus_verifications where id=p_request_id and status='approved' for update;
  if not found then raise exception 'Pengajuan ini tidak mempunyai persetujuan aktif.'; end if;
  update public.campus_verifications set status='revoked',revoked_at=now(),revoker_id=auth.uid(),revoke_note=btrim(p_note) where id=p_request_id;
end;
$$;
revoke all on function public.revoke_campus_verification(uuid,text) from public,anon,authenticated;
grant execute on function public.revoke_campus_verification(uuid,text) to authenticated;

create function public.mark_campus_document_deleted(p_request_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_row public.campus_verifications%rowtype;
begin
  if not public.has_registered_account() then raise exception 'Login terlebih dahulu.' using errcode='42501'; end if;
  select * into v_row from public.campus_verifications where id=p_request_id for update;
  if not found or (v_row.user_id<>auth.uid() and not public.is_site_admin()) then raise exception 'Dokumen ini tidak dapat dikelola akun Anda.' using errcode='42501'; end if;
  if v_row.status='pending' then raise exception 'Tarik atau putuskan pengajuan sebelum menghapus dokumen.'; end if;
  if exists(select 1 from storage.objects where bucket_id='second-life-campus-documents' and name=v_row.document_path) then
    raise exception 'Hapus foto melalui penyimpanan privat terlebih dahulu.';
  end if;
  update public.campus_verifications set document_deleted_at=coalesce(document_deleted_at,now()) where id=p_request_id;
end;
$$;
revoke all on function public.mark_campus_document_deleted(uuid) from public,anon,authenticated;
grant execute on function public.mark_campus_document_deleted(uuid) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('second-life-campus-documents','second-life-campus-documents',false,2097152,array['image/jpeg']);
create policy "Campus document uploads match a private draft" on storage.objects for insert to authenticated with check (
  bucket_id='second-life-campus-documents' and (select public.has_registered_account()) and exists(
    select 1 from public.campus_verifications v where v.document_path=name and v.user_id=(select auth.uid())
      and v.status='draft' and v.document_deleted_at is null
  )
);
create policy "Campus documents belong to applicant or admin" on storage.objects for select to authenticated using (
  bucket_id='second-life-campus-documents' and (select public.has_registered_account()) and exists(
    select 1 from public.campus_verifications v where v.document_path=name and v.document_deleted_at is null
      and (v.user_id=(select auth.uid()) or (select public.is_site_admin()))
  )
);
create policy "Campus documents can be removed after review or withdrawal" on storage.objects for delete to authenticated using (
  bucket_id='second-life-campus-documents' and (select public.has_registered_account()) and exists(
    select 1 from public.campus_verifications v where v.document_path=name and v.status<>'pending'
      and (v.user_id=(select auth.uid()) or (select public.is_site_admin()))
  )
);

create policy "New listings require campus review" on public.listings as restrictive for insert to authenticated
with check ((select public.can_publish_listings()));
create function public.guard_listing_campus_name() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_name text;
begin
  if public.is_site_admin() then return new; end if;
  if tg_op='INSERT' then
    select full_name into v_name from public.campus_verifications where user_id=auth.uid() and status='approved' for share;
    if v_name is null then raise exception 'Ajukan KTM atau bukti alumni dan tunggu persetujuan admin sebelum memasang barang baru.' using errcode='42501'; end if;
    new.seller_name:=v_name;
  elsif new.seller_name is distinct from old.seller_name then
    select full_name into v_name from public.campus_verifications where user_id=auth.uid() and status='approved' for share;
    if v_name is null or new.seller_name<>v_name then raise exception 'Nama pemilik harus mengikuti dokumen kampus yang disetujui.' using errcode='42501'; end if;
  end if;
  return new;
end;
$$;
revoke all on function public.guard_listing_campus_name() from public,anon,authenticated;
create trigger listings_campus_name_guard before insert or update on public.listings for each row execute function public.guard_listing_campus_name();

-- This public projection exposes no account directory, request ID, NIM, email, or document path.
-- Only requested, currently visible listings with a matching reviewed display name get a badge.
create function public.public_campus_reviews(p_listing_ids uuid[]) returns table(listing_id uuid,campus text)
language plpgsql stable security definer set search_path='' as $$
begin
  if coalesce(cardinality(p_listing_ids),0)>1000 then raise exception 'Maksimal 1.000 iklan per permintaan.'; end if;
  return query select l.id,v.campus from public.listings l join public.campus_verifications v
    on v.user_id=l.owner_id and v.status='approved' and v.full_name=l.seller_name
    where l.id=any(p_listing_ids) and l.kind in ('jual','donasi')
      and (l.status in ('Tersedia','Dalam proses') or l.owner_id=auth.uid() or public.is_site_admin());
end;
$$;
revoke all on function public.public_campus_reviews(uuid[]) from public,anon,authenticated;
grant execute on function public.public_campus_reviews(uuid[]) to anon,authenticated;

-- Existing invoice/auth functions intentionally continue to use email registration,
-- so applicants can still pay outstanding fees and manage existing records.
commit;
