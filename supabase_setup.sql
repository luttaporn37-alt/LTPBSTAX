-- =====================================================
-- LTP ระบบภาษี — Supabase Database Setup
-- รัน script นี้ใน Supabase SQL Editor
-- =====================================================

-- ─── Enable UUID ───
create extension if not exists "uuid-ossp";

-- ─── 1. USERS / AUTH ───
-- Supabase มี auth.users ให้อยู่แล้ว
-- เราสร้าง profiles table เพิ่มเพื่อเก็บ role

create table if not exists public.profiles (
  id uuid references auth.users on delete cascade primary key,
  email text,
  role text default 'user' check (role in ('admin','user')),
  name text,
  created_at timestamptz default now()
);

alter table public.profiles enable row level security;

create policy "Users can view own profile" on public.profiles
  for select using (auth.uid() = id);

create policy "Admin can view all profiles" on public.profiles
  for all using (
    exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
  );

-- ─── 2. MASTER INVOICES (ไฟล์หลักใบกำกับซื้อ) ───
create table if not exists public.master_invoices (
  id text primary key default 'mi_' || extract(epoch from now())::bigint::text,
  date date,
  invno text,
  taxid text,
  vendor text not null,
  amt numeric(14,2) default 0,
  vat numeric(14,2) default 0,
  total numeric(14,2) default 0,
  note text default '',
  used_month integer,
  used_year integer,
  pdf_url text,           -- Google Drive URL
  pdf_name text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.master_invoices enable row level security;
create policy "Authenticated users can CRUD master_invoices" on public.master_invoices
  for all using (auth.role() = 'authenticated');

create index on public.master_invoices (used_year, used_month);
create index on public.master_invoices (invno);
create index on public.master_invoices (vendor);

-- ─── 3. BUY TAX (ภาษีซื้อรายเดือน — อ้างอิงจาก master_invoices) ───
create table if not exists public.buy_tax (
  id uuid default uuid_generate_v4() primary key,
  tax_year integer not null,
  tax_month integer not null check (tax_month between 1 and 12),
  invoice_id text references public.master_invoices(id) on delete cascade,
  created_at timestamptz default now()
);

alter table public.buy_tax enable row level security;
create policy "Authenticated users can CRUD buy_tax" on public.buy_tax
  for all using (auth.role() = 'authenticated');

create unique index on public.buy_tax (tax_year, tax_month, invoice_id);

-- ─── 4. SELL TAX (ภาษีขาย) ───
create table if not exists public.sell_tax (
  id text primary key default 'sv_' || extract(epoch from now())::bigint::text,
  date date,
  invno text,
  doc_type text default 'invoice' check (doc_type in ('invoice','receipt','delivery','credit','both')),
  ref_no text,
  customer text,
  cust_taxid text,
  cust_addr text,
  amt numeric(14,2) default 0,
  vat numeric(14,2) default 0,
  total numeric(14,2) default 0,
  disc numeric(14,2) default 0,
  tax_month integer,
  tax_year integer,
  bill_no text,
  bill_date date,
  pay_term integer default 30,
  payment text default 'โอนเงิน',
  wht_amt numeric(14,2) default 0,
  status text default 'pending' check (status in ('pending','paid','partial')),
  has_warranty boolean default false,
  war_amt numeric(14,2) default 0,
  war_month integer default 0,
  war_start date,
  war_end date,
  war_bill text,
  note text default '',
  items jsonb,            -- รายการสินค้าใน invoice
  pdf_url text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.sell_tax enable row level security;
create policy "Authenticated users can CRUD sell_tax" on public.sell_tax
  for all using (auth.role() = 'authenticated');

create index on public.sell_tax (tax_year, tax_month);

-- ─── 5. STOCK (สต๊อค FIFO) ───
create table if not exists public.stock_items (
  id uuid default uuid_generate_v4() primary key,
  code text,
  name text not null unique,
  unit text default 'ชิ้น',
  total_qty numeric(14,3) default 0,
  avg_cost numeric(14,2) default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.stock_batches (
  id uuid default uuid_generate_v4() primary key,
  item_id uuid references public.stock_items(id) on delete cascade,
  batch_no text,
  qty numeric(14,3) default 0,
  cost numeric(14,2) default 0,
  date date,
  note text default '',
  created_at timestamptz default now()
);

alter table public.stock_items enable row level security;
alter table public.stock_batches enable row level security;
create policy "Auth users can CRUD stock" on public.stock_items for all using (auth.role() = 'authenticated');
create policy "Auth users can CRUD batches" on public.stock_batches for all using (auth.role() = 'authenticated');

-- ─── 6. CUSTOMERS (ฐานข้อมูลลูกค้า) ───
create table if not exists public.customers (
  id uuid default uuid_generate_v4() primary key,
  name text not null unique,
  taxid text,
  addr text,
  contact text,
  created_at timestamptz default now()
);

alter table public.customers enable row level security;
create policy "Auth users can CRUD customers" on public.customers for all using (auth.role() = 'authenticated');

-- ─── 7. PDF FILES (เชื่อม Google Drive) ───
create table if not exists public.pdf_files (
  id uuid default uuid_generate_v4() primary key,
  ref_type text check (ref_type in ('master','sell','stock')),
  ref_id text,
  drive_id text,          -- Google Drive file ID
  drive_url text,         -- URL เปิด Google Drive
  file_name text,
  file_size integer,
  uploaded_by uuid references auth.users(id),
  created_at timestamptz default now()
);

alter table public.pdf_files enable row level security;
create policy "Auth users can CRUD pdf_files" on public.pdf_files for all using (auth.role() = 'authenticated');

-- ─── 8. SETTINGS ───
create table if not exists public.settings (
  key text primary key,
  value jsonb,
  updated_at timestamptz default now()
);

alter table public.settings enable row level security;
create policy "Auth users can read settings" on public.settings for select using (auth.role() = 'authenticated');
create policy "Admin can update settings" on public.settings
  for all using (
    exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
  );

-- Insert default settings
insert into public.settings (key, value) values
  ('company', '{"name":"แอล ที พี บิวดิ้ง ซัพพลายส์","taxid":"0-1055-65030-10-1","addr":"364/10 ซ.ไสวสุวรรณ แขวงบางซื่อ กทม. 10800"}')
  on conflict (key) do nothing;

-- ─── 9. REALTIME ───
alter publication supabase_realtime add table public.master_invoices;
alter publication supabase_realtime add table public.sell_tax;
alter publication supabase_realtime add table public.stock_items;
alter publication supabase_realtime add table public.customers;

-- ─── 10. FUNCTION: Auto-update updated_at ───
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

create trigger set_master_invoices_updated_at before update on public.master_invoices
  for each row execute function public.set_updated_at();
create trigger set_sell_tax_updated_at before update on public.sell_tax
  for each row execute function public.set_updated_at();
create trigger set_stock_items_updated_at before update on public.stock_items
  for each row execute function public.set_updated_at();

-- ─── สร้าง Admin user แรก ───
-- หลังจาก run SQL นี้แล้ว ให้ไปที่ Authentication > Users > Invite user
-- แล้วใส่ email แล้ว run SQL นี้เพื่อ set เป็น admin:
-- update public.profiles set role = 'admin', name = 'Admin LTP' where email = 'your@email.com';

select 'Setup complete! Tables created successfully.' as status;
