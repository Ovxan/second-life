-- New admin fees are billed to the seller only when the listing becomes Terjual.
-- Existing financial records retain their original payer. No money moves here.
begin;
alter table public.admin_fee_invoices add column payer_id uuid references auth.users(id);
update public.admin_fee_invoices set payer_id=buyer_id;
alter table public.admin_fee_invoices alter column payer_id set not null;
alter table public.admin_fee_invoices alter column buyer_id drop not null;
alter table public.admin_fee_invoices add constraint fee_payer_matches_record check
  ((buyer_id is null and payer_id=seller_id) or (buyer_id is not null and payer_id=buyer_id));
create index admin_fee_payer_created on public.admin_fee_invoices(payer_id,created_at desc);
alter table public.admin_fee_invoices add column sale_confirmed_at timestamptz;
update public.admin_fee_invoices i set sale_confirmed_at=now()
from public.listings l where l.id=i.listing_id and l.status='Terjual';
alter table public.admin_fee_events drop constraint admin_fee_events_event_check;
alter table public.admin_fee_events add constraint admin_fee_events_event_check
check(event in ('created','proof_submitted','proof_rejected','paid','cancelled','recipient_set'));

drop policy "Buyer or owner reads fee invoices" on public.admin_fee_invoices;
create policy "Payer or owner reads fee invoices" on public.admin_fee_invoices for select to authenticated
using ((select public.has_registered_account()) and (payer_id=(select auth.uid()) or (select public.is_site_admin())));
drop policy "Buyer or owner reads fee history" on public.admin_fee_events;
create policy "Payer or owner reads fee history" on public.admin_fee_events for select to authenticated
using (exists(select 1 from public.admin_fee_invoices i where i.id=invoice_id));
drop policy "Buyer uploads fee evidence" on storage.objects;
create policy "Payer uploads fee evidence" on storage.objects for insert to authenticated with check(
  bucket_id='second-life-receipts' and (select public.has_registered_account())
  and name ~ ('^' || (select auth.uid())::text || '/[0-9a-f-]{36}/[0-9a-f-]{36}\.jpg$')
  and exists(select 1 from public.admin_fee_invoices i where i.id::text=(storage.foldername(name))[2]
    and i.payer_id=(select auth.uid()) and i.status in ('unpaid','rejected') and i.sale_confirmed_at is not null and i.account_number <> '')
);

create function public.issue_sold_fee_invoice(p_listing_id uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_listing public.listings%rowtype; v_settings public.admin_fee_settings%rowtype; v_existing public.admin_fee_invoices%rowtype; v_id uuid;
begin
  if not public.has_registered_account() then raise exception 'Login dengan akun terverifikasi terlebih dahulu.' using errcode='42501'; end if;
  select * into v_listing from public.listings where id=p_listing_id for update;
  if not found or v_listing.kind <> 'jual' then raise exception 'Biaya admin hanya untuk barang jual beli.'; end if;
  if v_listing.owner_id <> auth.uid() and not public.is_site_admin() then raise exception 'Hanya penjual atau admin yang dapat menyelesaikan penjualan.' using errcode='42501'; end if;
  select * into v_settings from public.admin_fee_settings where id for share;
  if not found then raise exception 'Pengaturan pembayaran belum tersedia.'; end if;
  select * into v_existing from public.admin_fee_invoices where listing_id=p_listing_id and status <> 'cancelled' for update;
  if found then
    if v_existing.payer_id <> v_listing.owner_id and v_existing.status <> 'paid' then raise exception 'Tagihan lama masih memakai penanggung lain. Pengelola perlu memeriksanya terlebih dahulu.'; end if;
    if v_existing.sale_confirmed_at is null then update public.admin_fee_invoices set sale_confirmed_at=now() where id=v_existing.id; end if;
    return v_existing.id;
  end if;
  insert into public.admin_fee_invoices(listing_id,payer_id,seller_id,title,item_price,channel,provider,account_name,account_number,instructions,sale_confirmed_at)
  values(v_listing.id,v_listing.owner_id,v_listing.owner_id,v_listing.title,v_listing.price,v_settings.channel,
    case when v_settings.enabled then v_settings.provider else '' end,
    case when v_settings.enabled then v_settings.account_name else '' end,
    case when v_settings.enabled then v_settings.account_number else '' end,
    case when v_settings.enabled then v_settings.instructions else '' end,now()) returning id into v_id;
  insert into public.admin_fee_events(invoice_id,actor_id,event,note)
  values(v_id,auth.uid(),'created','Barang dikonfirmasi Terjual. Tagihan biaya admin Rp5.000 diterbitkan untuk penjual.');
  return v_id;
end;
$$;
revoke all on function public.issue_sold_fee_invoice(uuid) from public,anon,authenticated;

create or replace function public.create_fee_invoice(p_listing_id uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_listing public.listings%rowtype; v_existing uuid;
begin
  if not public.has_registered_account() then raise exception 'Login terlebih dahulu.' using errcode='42501'; end if;
  select * into v_listing from public.listings where id=p_listing_id for update;
  if not found or v_listing.kind <> 'jual' then raise exception 'Tagihan hanya tersedia untuk barang jual beli.'; end if;
  if v_listing.status <> 'Terjual' then raise exception 'Barang belum berstatus Terjual. Biaya admin belum ditagihkan.'; end if;
  if v_listing.owner_id=auth.uid() or public.is_site_admin() then return public.issue_sold_fee_invoice(p_listing_id); end if;
  -- Old invoices remain readable by the originally recorded payer, without new charges.
  select id into v_existing from public.admin_fee_invoices where listing_id=p_listing_id and payer_id=auth.uid() and status <> 'cancelled';
  if found then return v_existing; end if;
  raise exception 'Tagihan biaya admin ditujukan kepada penjual barang.' using errcode='42501';
end;
$$;

create function public.complete_sale(p_listing_id uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_listing public.listings%rowtype; v_invoice uuid;
begin
  if not public.has_registered_account() then raise exception 'Login terlebih dahulu.' using errcode='42501'; end if;
  select * into v_listing from public.listings where id=p_listing_id for update;
  if not found or (v_listing.owner_id <> auth.uid() and not public.is_site_admin()) then raise exception 'Hanya penjual atau admin yang dapat menyelesaikan penjualan.' using errcode='42501'; end if;
  if v_listing.kind <> 'jual' then raise exception 'Konfirmasi penjualan hanya berlaku untuk barang jual beli.'; end if;
  v_invoice:=public.issue_sold_fee_invoice(p_listing_id);
  update public.listings set status='Terjual' where id=p_listing_id;
  return v_invoice;
end;
$$;
revoke all on function public.complete_sale(uuid) from public,anon,authenticated;
grant execute on function public.complete_sale(uuid) to authenticated;

create function public.guard_sold_fee_status() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.kind <> 'jual' then return new; end if;
  if TG_OP='INSERT' then
    if new.status='Terjual' then raise exception 'Tayangkan barang dahulu, lalu konfirmasikan Terjual agar tagihan penjual diterbitkan.'; end if;
    return new;
  end if;
  if new.status='Terjual' and old.status <> 'Terjual' then
    if not exists(select 1 from public.admin_fee_invoices where listing_id=new.id and seller_id=new.owner_id and sale_confirmed_at is not null and status <> 'cancelled') then raise exception 'Gunakan konfirmasi Terjual agar tagihan admin diterbitkan ke akun penjual.'; end if;
  elsif old.status='Terjual' and new.status <> 'Terjual' then
    if exists(select 1 from public.admin_fee_invoices where listing_id=new.id and status <> 'cancelled') then raise exception 'Tagihan penjualan masih aktif. Pengelola perlu memeriksa pembatalan sebelum status barang diubah.'; end if;
  end if;
  return new;
end;
$$;
revoke all on function public.guard_sold_fee_status() from public,anon,authenticated;
create trigger listings_sold_fee_guard before insert or update on public.listings for each row execute function public.guard_sold_fee_status();

create or replace function public.save_fee_payment_settings(p_enabled boolean,p_channel text,p_provider text,p_account_name text,p_account_number text,p_instructions text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_site_admin() then raise exception 'Hanya admin pemilik web yang dapat mengatur tujuan pembayaran.' using errcode='42501'; end if;
  if p_enabled is null or p_channel is null or p_channel not in ('bank','ewallet')
    or p_provider is null or p_account_name is null or p_account_number is null or p_instructions is null
    or length(trim(p_provider)) > 70 or length(trim(p_account_name)) > 100 or length(trim(p_account_number)) > 50 or length(trim(p_instructions)) > 700
    or (p_enabled and (length(trim(p_provider)) < 2 or length(trim(p_account_name)) < 2 or length(trim(p_account_number)) < 5)) then
    raise exception 'Lengkapi nama bank/e-wallet, nama penerima, dan nomor tujuan pembayaran.';
  end if;
  update public.admin_fee_settings set enabled=p_enabled,channel=p_channel,provider=trim(p_provider),account_name=trim(p_account_name),account_number=trim(p_account_number),instructions=trim(p_instructions),updated_at=now() where id;
  if p_enabled then
    with assigned as (
      update public.admin_fee_invoices set channel=p_channel,provider=trim(p_provider),account_name=trim(p_account_name),account_number=trim(p_account_number),instructions=trim(p_instructions)
      where sale_confirmed_at is not null and account_number='' and status in ('unpaid','rejected') returning id
    ) insert into public.admin_fee_events(invoice_id,actor_id,event,note)
      select id,auth.uid(),'recipient_set','Tujuan transfer disiapkan pengelola untuk tagihan barang terjual.' from assigned;
  end if;
end;
$$;

create or replace function public.submit_fee_proof(p_invoice_id uuid,p_receipt_path text,p_buyer_note text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_invoice public.admin_fee_invoices%rowtype;
begin
  if not public.has_registered_account() then raise exception 'Login dengan akun penanggung tagihan terlebih dahulu.' using errcode='42501'; end if;
  select * into v_invoice from public.admin_fee_invoices where id=p_invoice_id for update;
  if not found or v_invoice.payer_id <> v_user then raise exception 'Tagihan ini bukan milik akun yang sedang login.' using errcode='42501'; end if;
  if v_invoice.sale_confirmed_at is null then raise exception 'Biaya admin baru ditagihkan setelah barang berstatus Terjual.'; end if;
  if v_invoice.account_number='' then raise exception 'Tunggu pengelola menyiapkan tujuan transfer pada tagihan ini.'; end if;
  if v_invoice.status not in ('unpaid','rejected') then raise exception 'Bukti hanya dapat dikirim untuk tagihan yang belum lunas atau perlu diperbaiki.'; end if;
  if p_buyer_note is null or length(trim(p_buyer_note)) not between 3 and 300 then raise exception 'Isi nama pengirim atau keterangan transfer antara 3–300 karakter.'; end if;
  if p_receipt_path is null or p_receipt_path !~ ('^' || v_user::text || '/' || p_invoice_id::text || '/[0-9a-f-]{36}\.jpg$')
    or not exists(select 1 from storage.objects where bucket_id='second-life-receipts' and name=p_receipt_path) then
    raise exception 'Unggah bukti transfer melalui tagihan ini terlebih dahulu.';
  end if;
  update public.admin_fee_invoices set status='submitted',receipt_path=p_receipt_path,buyer_note=trim(p_buyer_note),submitted_at=now(),review_note='',reviewer_id=null,reviewed_at=null where id=p_invoice_id;
  insert into public.admin_fee_events(invoice_id,actor_id,event,note,receipt_path) values(p_invoice_id,v_user,'proof_submitted',trim(p_buyer_note),p_receipt_path);
end;
$$;

create or replace function public.review_fee_proof(p_invoice_id uuid,p_approved boolean,p_note text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_invoice public.admin_fee_invoices%rowtype;
begin
  if not public.is_site_admin() then raise exception 'Verifikasi pembayaran hanya tersedia untuk admin pemilik web.' using errcode='42501'; end if;
  select * into v_invoice from public.admin_fee_invoices where id=p_invoice_id for update;
  if not found or v_invoice.status <> 'submitted' then raise exception 'Tagihan ini belum mempunyai bukti yang menunggu verifikasi.'; end if;
  if p_approved and v_invoice.sale_confirmed_at is null then raise exception 'Tagihan belum aktif karena barang belum dikonfirmasi Terjual.'; end if;
  if p_approved is null or p_note is null or length(trim(p_note)) > 300 or (not p_approved and length(trim(p_note)) < 3) then raise exception 'Isi alasan penolakan antara 3–300 karakter.'; end if;
  update public.admin_fee_invoices set status=case when p_approved then 'paid' else 'rejected' end,review_note=trim(p_note),reviewer_id=auth.uid(),reviewed_at=now(),paid_at=case when p_approved then now() else null end where id=p_invoice_id;
  insert into public.admin_fee_events(invoice_id,actor_id,event,note,receipt_path)
  values(p_invoice_id,auth.uid(),case when p_approved then 'paid' else 'proof_rejected' end,case when p_approved and trim(p_note)='' then 'Penerimaan biaya admin dikonfirmasi pengelola.' else trim(p_note) end,v_invoice.receipt_path);
end;
$$;

create or replace function public.cancel_fee_invoice(p_invoice_id uuid,p_note text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_invoice public.admin_fee_invoices%rowtype; v_admin boolean := public.is_site_admin();
begin
  if not public.has_registered_account() then raise exception 'Login terlebih dahulu.' using errcode='42501'; end if;
  select * into v_invoice from public.admin_fee_invoices where id=p_invoice_id for update;
  if not found or (v_invoice.payer_id <> auth.uid() and not v_admin) then raise exception 'Tagihan ini tidak dapat diubah oleh akun Anda.' using errcode='42501'; end if;
  if v_invoice.sale_confirmed_at is not null and not v_admin then raise exception 'Tagihan penjualan sudah aktif. Hubungi pengelola jika penjualan dibatalkan.'; end if;
  if v_invoice.status not in ('unpaid','rejected') then raise exception 'Tagihan yang sedang diperiksa atau sudah lunas tidak dapat dibatalkan.'; end if;
  if p_note is null or length(trim(p_note)) not between 3 and 300 then raise exception 'Isi alasan pembatalan antara 3–300 karakter.'; end if;
  update public.admin_fee_invoices set status='cancelled',review_note=trim(p_note) where id=p_invoice_id;
  insert into public.admin_fee_events(invoice_id,actor_id,event,note) values(p_invoice_id,auth.uid(),'cancelled',trim(p_note));
end;
$$;

create or replace function public.fee_income_summary() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_site_admin() then raise exception 'Rekap pendapatan hanya tersedia untuk admin.' using errcode='42501'; end if;
  return (select jsonb_build_object('paid',coalesce(sum(fee_amount) filter(where status='paid'),0),
    'submitted',coalesce(sum(fee_amount) filter(where status='submitted' and sale_confirmed_at is not null),0),
    'unpaid',coalesce(sum(fee_amount) filter(where status in ('unpaid','rejected') and sale_confirmed_at is not null),0),
    'paid_count',count(*) filter(where status='paid')) from public.admin_fee_invoices);
end;
$$;

-- Only sessions that satisfy invoice RLS receive their invoice changes.
do $$ begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(
    select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='admin_fee_invoices'
  ) then alter publication supabase_realtime add table public.admin_fee_invoices; end if;
end $$;
commit;
