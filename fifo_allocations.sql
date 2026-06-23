-- =====================================================
-- fifo_allocations.sql — v1
-- Append-only inventory journal for FIFO stock deduction
--
-- Design decisions:
--   - invoice_id is TEXT to match sell_tax.id exactly
--   - No UNIQUE constraint on business keys
--   - Duplicate tuples across Sale/Void/Restore cycles are expected
--   - allocation_event_id deferred to v2 (not yet in JS layer)
--   - Table is append-only: INSERT only, no UPDATE, no DELETE
--
-- Row type semantics:
--   Sale OUT:    allocation_type='OUT',     reversed_allocation_id=NULL, restored_allocation_id=NULL
--   Void REVERSE:allocation_type='REVERSE', reversed_allocation_id=OUT.id, restored_allocation_id=NULL
--   Restore OUT: allocation_type='OUT',     reversed_allocation_id=NULL, restored_allocation_id=REVERSE.id
--
-- Chain reconstruction: follow reversed_allocation_id (REVERSE→OUT) and
--   restored_allocation_id (Restore OUT→REVERSE) to trace the full lifecycle.
-- =====================================================

-- ─── TABLE ───────────────────────────────────────────
create table if not exists public.fifo_allocations (
  -- surrogate primary key only
  id                      uuid          default uuid_generate_v4() primary key,

  -- FK → sell_tax.id (TEXT — must not cast to uuid)
  -- historical records may contain non-UUID format values (e.g. sv_1234567890)
  invoice_id              text          not null
                                        references public.sell_tax(id)
                                        on delete restrict
                                        deferrable initially deferred,

  -- human-readable document reference — audit snapshot independent of FK
  -- remains meaningful even if sell_tax record is voided or unavailable
  invoice_no              text          not null,

  -- FK → stock_batches.id (UUID)
  batch_id                uuid          not null
                                        references public.stock_batches(id)
                                        on delete restrict
                                        deferrable initially deferred,

  -- FK → stock_items.id (UUID)
  -- stored to allow item-level queries without joining through stock_batches
  item_id                 uuid          not null
                                        references public.stock_items(id)
                                        on delete restrict
                                        deferrable initially deferred,

  -- OUT  = stock deducted at sale
  -- REVERSE = stock returned at void or credit note
  allocation_type         text          not null
                                        check (allocation_type in ('OUT', 'REVERSE')),

  -- REVERSE rows only: points to the OUT row being reversed (Void → Sale)
  -- null for all OUT rows (both original Sale and Restore)
  reversed_allocation_id  uuid          null
                                        references public.fifo_allocations(id)
                                        on delete restrict
                                        deferrable initially deferred,

  -- Restore OUT rows only: points to the REVERSE row being compensated (Restore → Void)
  -- null for original Sale OUT rows and for all REVERSE rows
  -- distinguishes Restore OUT rows from original Sale OUT rows without ambiguity
  restored_allocation_id  uuid          null
                                        references public.fifo_allocations(id)
                                        on delete restrict
                                        deferrable initially deferred,

  -- quantity taken from this batch for this allocation event
  qty_allocated           numeric(14,3) not null
                                        check (qty_allocated > 0),

  -- cost snapshot at time of allocation — not bound to batch.cost which may change
  cost_per_unit           numeric(14,2) not null
                                        check (cost_per_unit >= 0),

  -- computed for audit convenience — always consistent with qty × cost
  total_cost              numeric(14,2) generated always as
                            (qty_allocated * cost_per_unit) stored,

  allocated_at            timestamptz   not null default now(),
  created_at              timestamptz   not null default now()
);

-- ─── RLS ─────────────────────────────────────────────
alter table public.fifo_allocations enable row level security;

-- idempotent: drop before create
drop policy if exists "Auth users can select fifo_allocations" on public.fifo_allocations;
create policy "Auth users can select fifo_allocations"
  on public.fifo_allocations
  for select
  using (auth.role() = 'authenticated');

drop policy if exists "Auth users can insert fifo_allocations" on public.fifo_allocations;
create policy "Auth users can insert fifo_allocations"
  on public.fifo_allocations
  for insert
  with check (auth.role() = 'authenticated');

-- UPDATE: forbidden — this table is an immutable ledger
-- DELETE: forbidden — use allocation_type='REVERSE' to compensate instead
-- (no policy = no access by default under RLS)

-- ─── GRANTS ──────────────────────────────────────────
-- Required for tables created via SQL Editor (not auto-granted by Supabase Dashboard)
grant select, insert on public.fifo_allocations to authenticated;
grant select            on public.fifo_allocations to anon;

-- ─── INDEXES (named, idempotent) ─────────────────────
-- primary query pattern: all allocations for a given invoice
create index if not exists idx_fifo_alloc_invoice
  on public.fifo_allocations (invoice_id);

-- FIFO accounting: all allocations drawn from a given batch
create index if not exists idx_fifo_alloc_batch
  on public.fifo_allocations (batch_id);

-- item-level cost and quantity reporting
create index if not exists idx_fifo_alloc_item
  on public.fifo_allocations (item_id);

-- balance calculation: SUM(OUT) - SUM(REVERSE) per invoice/batch/item
create index if not exists idx_fifo_alloc_type
  on public.fifo_allocations (allocation_type);

-- ─── BUSINESS INVARIANT CONSTRAINTS ──────────────────
-- These two partial unique indexes enforce the core ledger invariants
-- at the database level, independent of application-level idempotency checks.
-- They protect against race conditions (concurrent browser sessions) and
-- future code paths that might bypass the JS idempotency checks.

-- Invariant 1: An OUT allocation can be reversed at most once.
-- Prevents two REVERSE rows from pointing to the same OUT row.
-- Compatible with all approved lifecycles: no valid operation inserts
-- two REVERSE rows with the same reversed_allocation_id.
create unique index if not exists ux_fifo_reverse_once
  on public.fifo_allocations (reversed_allocation_id)
  where reversed_allocation_id is not null;

-- Invariant 2: A REVERSE allocation can be restored at most once.
-- Prevents two Restore OUT rows from pointing to the same REVERSE row.
-- Compatible with all approved lifecycles: no valid operation inserts
-- two OUT rows with the same restored_allocation_id.
create unique index if not exists ux_fifo_restore_once
  on public.fifo_allocations (restored_allocation_id)
  where restored_allocation_id is not null;

-- ─── NON-UNIQUE BUSINESS KEYS ────────────────────────
-- fifo_allocations is a journal ledger.
-- Sale → Void → Restore → Void → Restore is a legitimate lifecycle.
-- The same (invoice_id, batch_id, item_id) tuple will appear multiple times
-- across lifecycle events. This is expected behavior, not a data error.
-- The unique constraints above enforce chain integrity, not tuple uniqueness.
--
-- Idempotency protection via allocation_event_id is deferred to v2,
-- pending implementation in Sale, Void, and Restore flows in the JS layer.

-- ─── FUTURE v2 (do not apply yet) ────────────────────
-- alter table public.fifo_allocations
--   add column allocation_event_id uuid not null;
--
-- create unique index on public.fifo_allocations
--   (allocation_event_id, batch_id, item_id);

