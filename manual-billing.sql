-- Manual collection of the fixed admin fee. Item payments remain buyer-to-seller.
-- Apply once after the catalog and registered-account/admin migrations.
begin;

create table public.admin_fee_settings (
  id boolean primary key default true check (id),
  enabled boolean not null default false,
  channel text not null default 'bank' check (channel in ('bank','ewallet')),
  provider text not null default '' check (length(provider) <= 70),
  account_name text not null default '' check (length(account_name) <= 100),
  account_number text not null default '' check (length(account_number) <= 50),
  instructions text not null default '' check (length(instructions) <= 700),
  updated_at timestamptz not null default now(),
  check (not enabled or (length(trim(provider)) >= 2 and length(trim(account_name)) >= 2 and length(trim(account_number)) >= 5))
);
insert into public.admin_fee_settings(id) values (true);

create table public.admin_fee_invoices (
  id uuid primary key default gen_random_uuid(),
  number bigint generated always as identity unique,
  listing_id uuid references public.listings(id) on delete set null,
  buyer_id uuid not null references auth.users(id),
  seller_id uuid not null references auth.users(id),
  title text not null,
  item_price integer not null check (item_price between 1000 and 100000000),
  fee_amount integer not null default 5000 check (fee_amount = 5000),
  channel text not null check (channel in ('bank','ewallet')),
  provider text not null,
  account_name text not null,
  account_number text not null,
  instructions text not null default '',
  status text not null default 'unpaid' check (status in ('unpaid','submitted','rejected','paid','cancelled')),
  receipt_path text not null default '',
  buyer_note text not null default '' check (length(buyer_note) <= 300),
  review_note text not null default '' check (length(review_note) <= 300),
  reviewer_id uuid references auth.users(id),
  submitted_at timestamptz,
  reviewed_at timestamptz,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  check (buyer_id <> seller_id),
  check (status not in ('submitted','paid') or receipt_path <> ''),
  check (status <> 'paid' or (paid_at is not null and reviewer_id is not null))
);
-- One charge per item, including a paid charge. Cancelled attempts can be replaced.
create unique index admin_fee_one_active_per_listing on public.admin_fee_invoices(listing_id) where status <> 'cancelled';
create index admin_fee_buyer_created on public.admin_fee_invoices(buyer_id,created_at desc);
create index admin_fee_status_created on public.admin_fee_invoices(status,created_at desc);
create index admin_fee_seller on public.admin_fee_invoices(seller_id);
create index admin_fee_reviewer on public.admin_fee_invoices(reviewer_id);

create table public.admin_fee_events (
  id bigint generated always as identity primary key,
  invoice_id uuid not null references public.admin_fee_invoices(id),
  actor_id uuid not null references auth.users(id),
  event text not null check (event in ('created','proof_submitted','proof_rejected','paid','cancelled')),
  note text not null default '',
  receipt_path text not null default '',
  created_at timestamptz not null default now()
);
create index admin_fee_events_invoice on public.admin_fee_events(invoice_id,id);
create index admin_fee_events_actor on public.admin_fee_events(actor_id);

alter table public.admin_fee_settings enable row level security;
alter table public.admin_fee_invoices enable row level security;
alter table public.admin_fee_events enable row level security;
revoke all on public.admin_fee_settings,public.admin_fee_invoices,public.admin_fee_events from public,anon,authenticated;
revoke all on sequence public.admin_fee_invoices_number_seq,public.admin_fee_events_id_seq from public,anon,authenticated;
grant select on public.admin_fee_settings,public.admin_fee_invoices,public.admin_fee_events to authenticated;
create policy "Owner reads payment settings" on public.admin_fee_settings for select to authenticated using ((select public.is_site_admin()));
create policy "Buyer or owner reads fee invoices" on public.admin_fee_invoices for select to authenticated
using ((select public.has_registered_account()) and (buyer_id = (select auth.uid()) or (select public.is_site_admin())));
create policy "Buyer or owner reads fee history" on public.admin_fee_events for select to authenticated
using (exists (select 1 from public.admin_fee_invoices i where i.id=invoice_id));

create function public.fee_payment_ready() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select enabled from public.admin_fee_settings where id),false);
$$;

create function public.save_fee_payment_settings(p_enabled boolean,p_channel text,p_provider text,p_account_name text,p_account_number text,p_instructions text) returns void
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
end;
$$;

create function public.create_fee_invoice(p_listing_id uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_listing public.listings%rowtype; v_settings public.admin_fee_settings%rowtype; v_existing public.admin_fee_invoices%rowtype; v_id uuid;
begin
  if not public.has_registered_account() then raise exception 'Daftar, verifikasi email, dan login sebelum membuat tagihan.' using errcode='42501'; end if;
  select * into v_listing from public.listings where id=p_listing_id for update;
  if not found or v_listing.kind <> 'jual' then raise exception 'Tagihan admin hanya tersedia untuk barang jual beli asli.'; end if;
  if v_listing.owner_id = v_user then raise exception 'Pemilik barang tidak dapat membuat tagihan pembelian barangnya sendiri.'; end if;
  select * into v_existing from public.admin_fee_invoices where listing_id=p_listing_id and status <> 'cancelled' for update;
  if found then
    if v_existing.buyer_id=v_user then return v_existing.id; end if;
    raise exception 'Barang ini sudah mempunyai tagihan admin aktif. Hubungi pengelola untuk memeriksanya.';
  end if;
  select * into v_settings from public.admin_fee_settings where id for share;
  if not found or not v_settings.enabled then raise exception 'Pengelola belum mengaktifkan tujuan transfer biaya admin.'; end if;
  if (select count(*) from public.admin_fee_invoices where buyer_id=v_user and status in ('unpaid','rejected','submitted')) >= 10 then
    raise exception 'Selesaikan atau batalkan tagihan yang masih terbuka sebelum membuat tagihan baru.';
  end if;
  insert into public.admin_fee_invoices(listing_id,buyer_id,seller_id,title,item_price,channel,provider,account_name,account_number,instructions)
  values(v_listing.id,v_user,v_listing.owner_id,v_listing.title,v_listing.price,v_settings.channel,v_settings.provider,v_settings.account_name,v_settings.account_number,v_settings.instructions)
  returning id into v_id;
  insert into public.admin_fee_events(invoice_id,actor_id,event,note) values(v_id,v_user,'created','Tagihan biaya admin dibuat oleh pembeli. Pembayaran barang dilakukan langsung ke penjual.');
  return v_id;
end;
$$;

create function public.submit_fee_proof(p_invoice_id uuid,p_receipt_path text,p_buyer_note text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_invoice public.admin_fee_invoices%rowtype;
begin
  if not public.has_registered_account() then raise exception 'Login dengan akun pembeli terlebih dahulu.' using errcode='42501'; end if;
  select * into v_invoice from public.admin_fee_invoices where id=p_invoice_id for update;
  if not found or v_invoice.buyer_id <> v_user then raise exception 'Tagihan ini bukan milik akun pembeli yang sedang login.' using errcode='42501'; end if;
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

create function public.review_fee_proof(p_invoice_id uuid,p_approved boolean,p_note text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_invoice public.admin_fee_invoices%rowtype;
begin
  if not public.is_site_admin() then raise exception 'Verifikasi pembayaran hanya tersedia untuk admin pemilik web.' using errcode='42501'; end if;
  select * into v_invoice from public.admin_fee_invoices where id=p_invoice_id for update;
  if not found or v_invoice.status <> 'submitted' then raise exception 'Tagihan ini belum mempunyai bukti yang menunggu verifikasi.'; end if;
  if p_approved is null or p_note is null or length(trim(p_note)) > 300 or (not p_approved and length(trim(p_note)) < 3) then raise exception 'Isi alasan penolakan antara 3–300 karakter.'; end if;
  update public.admin_fee_invoices set status=case when p_approved then 'paid' else 'rejected' end,review_note=trim(p_note),reviewer_id=auth.uid(),reviewed_at=now(),paid_at=case when p_approved then now() else null end where id=p_invoice_id;
  insert into public.admin_fee_events(invoice_id,actor_id,event,note,receipt_path)
  values(p_invoice_id,auth.uid(),case when p_approved then 'paid' else 'proof_rejected' end,case when p_approved and trim(p_note)='' then 'Penerimaan biaya admin dikonfirmasi pengelola.' else trim(p_note) end,v_invoice.receipt_path);
end;
$$;

create function public.cancel_fee_invoice(p_invoice_id uuid,p_note text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_invoice public.admin_fee_invoices%rowtype; v_admin boolean := public.is_site_admin();
begin
  if not public.has_registered_account() then raise exception 'Login terlebih dahulu.' using errcode='42501'; end if;
  select * into v_invoice from public.admin_fee_invoices where id=p_invoice_id for update;
  if not found or (v_invoice.buyer_id <> auth.uid() and not v_admin) then raise exception 'Tagihan ini tidak dapat diubah oleh akun Anda.' using errcode='42501'; end if;
  if v_invoice.status not in ('unpaid','rejected') then raise exception 'Tagihan yang sedang diperiksa atau sudah lunas tidak dapat dibatalkan.'; end if;
  if p_note is null or length(trim(p_note)) not between 3 and 300 then raise exception 'Isi alasan pembatalan antara 3–300 karakter.'; end if;
  update public.admin_fee_invoices set status='cancelled',review_note=trim(p_note) where id=p_invoice_id;
  insert into public.admin_fee_events(invoice_id,actor_id,event,note) values(p_invoice_id,auth.uid(),'cancelled',trim(p_note));
end;
$$;

create function public.fee_income_summary() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.is_site_admin() then raise exception 'Rekap pendapatan hanya tersedia untuk admin.' using errcode='42501'; end if;
  return (select jsonb_build_object('paid',coalesce(sum(fee_amount) filter(where status='paid'),0),
    'submitted',coalesce(sum(fee_amount) filter(where status='submitted'),0),
    'unpaid',coalesce(sum(fee_amount) filter(where status in ('unpaid','rejected')),0),
    'paid_count',count(*) filter(where status='paid')) from public.admin_fee_invoices);
end;
$$;

revoke all on function public.fee_payment_ready(),public.save_fee_payment_settings(boolean,text,text,text,text,text),public.create_fee_invoice(uuid),public.submit_fee_proof(uuid,text,text),public.review_fee_proof(uuid,boolean,text),public.cancel_fee_invoice(uuid,text),public.fee_income_summary() from public,anon,authenticated;
grant execute on function public.fee_payment_ready() to anon,authenticated;
grant execute on function public.save_fee_payment_settings(boolean,text,text,text,text,text),public.create_fee_invoice(uuid),public.submit_fee_proof(uuid,text,text),public.review_fee_proof(uuid,boolean,text),public.cancel_fee_invoice(uuid,text),public.fee_income_summary() to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('second-life-receipts','second-life-receipts',false,2097152,array['image/jpeg']);
create policy "Buyer uploads fee evidence" on storage.objects for insert to authenticated with check (
  bucket_id='second-life-receipts' and (select public.has_registered_account())
  and name ~ ('^' || (select auth.uid())::text || '/[0-9a-f-]{36}/[0-9a-f-]{36}\.jpg$')
  and exists(select 1 from public.admin_fee_invoices i where i.id::text=(storage.foldername(name))[2]
    and i.buyer_id=(select auth.uid()) and i.status in ('unpaid','rejected'))
);
create policy "Buyer and owner privately read fee evidence" on storage.objects for select to authenticated using (
  bucket_id='second-life-receipts' and (select public.has_registered_account())
  and exists(select 1 from public.admin_fee_events e where e.receipt_path=name and e.receipt_path <> '')
);
-- Evidence and audit events have no client update/delete grants or policies.
commit;
