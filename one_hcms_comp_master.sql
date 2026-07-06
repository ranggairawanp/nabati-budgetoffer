-- =====================================================================
-- One HCMS, Compensation Master, Salary Structure and Market Benchmark
-- Group-wide, entity-aware. Effective dating and maker-checker.
-- Idempotent, safe to re-run. Run in the shared database czfwjapmcwnupqqtrydx.
--
-- Revision slot for real data: every row carries a source column and an
-- effective date. Dummy rows use source 'DUMMY'. To go live with real data,
-- insert real rows with a real source and a valid_from, then retire the dummy
-- rows with fn_retire_dummy_comp(). No application code changes are needed,
-- because Budget Offering reads whatever is ACTIVE and currently valid.
-- =====================================================================

-- 1. Tables ------------------------------------------------------------
create table if not exists salary_structure (
  id uuid primary key default gen_random_uuid(),
  entity_id text not null,
  grade text not null,
  currency text not null default 'IDR',
  min_amount numeric not null,
  mid_amount numeric not null,
  max_amount numeric not null,
  source text not null default 'DUMMY',
  valid_from date not null default current_date,
  valid_to date,
  status text not null default 'ACTIVE' check (status in ('DRAFT','ACTIVE','RETIRED')),
  created_by uuid,
  approved_by uuid,
  created_at timestamptz not null default now()
);
create index if not exists ix_salstruct_lookup on salary_structure (entity_id, grade, status);

create table if not exists market_benchmark (
  id uuid primary key default gen_random_uuid(),
  entity_id text not null,
  grade text not null,
  job_family text,
  currency text not null default 'IDR',
  p25 numeric not null,
  p50 numeric not null,
  p75 numeric not null,
  source text not null default 'DUMMY',
  period text,
  valid_from date not null default current_date,
  valid_to date,
  status text not null default 'ACTIVE' check (status in ('DRAFT','ACTIVE','RETIRED')),
  created_by uuid,
  approved_by uuid,
  created_at timestamptz not null default now()
);
create index if not exists ix_mktbench_lookup on market_benchmark (entity_id, grade, status);

alter table salary_structure enable row level security;
alter table market_benchmark enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='salary_structure' and policyname='salstruct_read') then
    create policy salstruct_read on salary_structure for select to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where tablename='market_benchmark' and policyname='mktbench_read') then
    create policy mktbench_read on market_benchmark for select to authenticated using (true);
  end if;
end $$;

-- 2. Read functions, consumed by Budget Offering ----------------------
-- Return the row that is ACTIVE and currently valid, newest valid_from wins.
create or replace function fn_get_salary_structure(p_entity text, p_grade text)
returns jsonb language sql stable security definer set search_path=public as $$
  select to_jsonb(r) from (
    select entity_id, grade, currency, min_amount, mid_amount, max_amount, source, valid_from, status
    from salary_structure
    where entity_id = p_entity and grade = p_grade and status = 'ACTIVE'
      and valid_from <= current_date and (valid_to is null or valid_to >= current_date)
    order by valid_from desc, created_at desc
    limit 1
  ) r;
$$;

create or replace function fn_get_market_benchmark(p_entity text, p_grade text, p_job_family text default null)
returns jsonb language sql stable security definer set search_path=public as $$
  select to_jsonb(r) from (
    select entity_id, grade, job_family, currency, p25, p50, p75, source, period, valid_from, status
    from market_benchmark
    where entity_id = p_entity and grade = p_grade and status = 'ACTIVE'
      and valid_from <= current_date and (valid_to is null or valid_to >= current_date)
      and (p_job_family is null or job_family is null or job_family = p_job_family)
    order by (case when job_family = p_job_family then 0 else 1 end), valid_from desc, created_at desc
    limit 1
  ) r;
$$;

-- 3. Maker-checker publish functions, for real data -------------------
-- Insert as DRAFT, then a different user publishes to ACTIVE, retiring the
-- previous ACTIVE row for the same entity and grade. This is the governed
-- path for real data.
create or replace function fn_draft_salary_structure(p_entity text, p_grade text, p_currency text, p_min numeric, p_mid numeric, p_max numeric, p_source text, p_valid_from date)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  insert into salary_structure (entity_id, grade, currency, min_amount, mid_amount, max_amount, source, valid_from, status, created_by)
  values (p_entity, p_grade, coalesce(p_currency,'IDR'), p_min, p_mid, p_max, coalesce(p_source,'MANUAL'), coalesce(p_valid_from, current_date), 'DRAFT', auth.uid())
  returning id into v_id;
  return v_id;
end $$;

create or replace function fn_publish_salary_structure(p_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r salary_structure;
begin
  select * into r from salary_structure where id = p_id;
  if not found then raise exception 'not found'; end if;
  if r.status <> 'DRAFT' then raise exception 'not a draft'; end if;
  if r.created_by = auth.uid() then raise exception 'maker cannot publish own draft'; end if;
  update salary_structure set status='RETIRED', valid_to = coalesce(valid_to, current_date)
    where entity_id=r.entity_id and grade=r.grade and status='ACTIVE';
  update salary_structure set status='ACTIVE', approved_by = auth.uid() where id = p_id;
  return jsonb_build_object('ok', true, 'id', p_id, 'status', 'ACTIVE');
end $$;

create or replace function fn_draft_market_benchmark(p_entity text, p_grade text, p_job_family text, p_currency text, p_p25 numeric, p_p50 numeric, p_p75 numeric, p_source text, p_period text, p_valid_from date)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  insert into market_benchmark (entity_id, grade, job_family, currency, p25, p50, p75, source, period, valid_from, status, created_by)
  values (p_entity, p_grade, p_job_family, coalesce(p_currency,'IDR'), p_p25, p_p50, p_p75, coalesce(p_source,'MANUAL'), p_period, coalesce(p_valid_from, current_date), 'DRAFT', auth.uid())
  returning id into v_id;
  return v_id;
end $$;

create or replace function fn_publish_market_benchmark(p_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r market_benchmark;
begin
  select * into r from market_benchmark where id = p_id;
  if not found then raise exception 'not found'; end if;
  if r.status <> 'DRAFT' then raise exception 'not a draft'; end if;
  if r.created_by = auth.uid() then raise exception 'maker cannot publish own draft'; end if;
  update market_benchmark set status='RETIRED', valid_to = coalesce(valid_to, current_date)
    where entity_id=r.entity_id and grade=r.grade and coalesce(job_family,'') = coalesce(r.job_family,'') and status='ACTIVE';
  update market_benchmark set status='ACTIVE', approved_by = auth.uid() where id = p_id;
  return jsonb_build_object('ok', true, 'id', p_id, 'status', 'ACTIVE');
end $$;

-- 4. Retire dummy, the switch to flip when real data lands ------------
create or replace function fn_retire_dummy_comp()
returns jsonb language plpgsql security definer set search_path=public as $$
declare a int; b int;
begin
  update salary_structure set status='RETIRED', valid_to=coalesce(valid_to,current_date) where source='DUMMY' and status<>'RETIRED';
  get diagnostics a = row_count;
  update market_benchmark set status='RETIRED', valid_to=coalesce(valid_to,current_date) where source='DUMMY' and status<>'RETIRED';
  get diagnostics b = row_count;
  return jsonb_build_object('salary_structure_retired', a, 'market_benchmark_retired', b);
end $$;

-- 5. Grants -----------------------------------------------------------
grant execute on function fn_get_salary_structure(text,text) to authenticated;
grant execute on function fn_get_market_benchmark(text,text,text) to authenticated;
grant execute on function fn_draft_salary_structure(text,text,text,numeric,numeric,numeric,text,date) to authenticated;
grant execute on function fn_publish_salary_structure(uuid) to authenticated;
grant execute on function fn_draft_market_benchmark(text,text,text,text,numeric,numeric,numeric,text,text,date) to authenticated;
grant execute on function fn_publish_market_benchmark(uuid) to authenticated;
grant execute on function fn_retire_dummy_comp() to authenticated;

-- 6. Dummy seed, monthly amounts, source DUMMY ------------------------
-- These exist so calibration works today. They are the slot to be replaced
-- by real data. Re-running does not duplicate, because we clear DUMMY first.
delete from salary_structure where source='DUMMY';
insert into salary_structure (entity_id, grade, currency, min_amount, mid_amount, max_amount, source, valid_from) values
  ('ID Sales','3A','IDR',4000000,5000000,6000000,'DUMMY','2026-01-01'),
  ('ID Sales','4A','IDR',6000000,8000000,10000000,'DUMMY','2026-01-01'),
  ('ID Sales','4B','IDR',5000000,6500000,8000000,'DUMMY','2026-01-01'),
  ('ID Sales','5A','IDR',12000000,16000000,20000000,'DUMMY','2026-01-01'),
  ('ID Manufacturing','3A','IDR',4200000,5200000,6200000,'DUMMY','2026-01-01'),
  ('ID Manufacturing','4A','IDR',5500000,7000000,9000000,'DUMMY','2026-01-01'),
  ('MY','4A','MYR',4000,5000,6500,'DUMMY','2026-01-01');

delete from market_benchmark where source='DUMMY';
insert into market_benchmark (entity_id, grade, job_family, currency, p25, p50, p75, source, period, valid_from) values
  ('ID Sales','3A',null,'IDR',4500000,5200000,6000000,'DUMMY','2026','2026-01-01'),
  ('ID Sales','4A',null,'IDR',7500000,8500000,9500000,'DUMMY','2026','2026-01-01'),
  ('ID Sales','4B',null,'IDR',6000000,7000000,8000000,'DUMMY','2026','2026-01-01'),
  ('ID Sales','5A',null,'IDR',14000000,17000000,20000000,'DUMMY','2026','2026-01-01'),
  ('ID Manufacturing','4A',null,'IDR',6500000,7500000,8500000,'DUMMY','2026','2026-01-01'),
  ('MY','4A',null,'MYR',4500,5200,6000,'DUMMY','2026','2026-01-01');

-- Done. Budget Offering will auto-fill calibration from these rows.
-- When real data is ready: use fn_draft_* then fn_publish_* (maker-checker),
-- or bulk insert real ACTIVE rows, then call fn_retire_dummy_comp().
