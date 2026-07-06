-- =====================================================================
-- One HCMS, COMBEN_DIRECT initiation.
-- Lets Comben start an Offering Letter without an FLK candidate and without
-- the Lolos Seleksi gate. The FLK gate is replaced, not removed:
--   1. MPP Index and MPN Number are mandatory (the position must be planned).
--   2. The maker must hold maker authority for the grade.
--   3. The full grade-based approval chain still applies afterward.
--   4. Every direct OL is tagged origin = COMBEN_DIRECT for audit and reporting.
-- Idempotent, safe to re-run. Run in the shared database czfwjapmcwnupqqtrydx.
-- =====================================================================

-- 1. Provenance columns on candidates ---------------------------------
alter table candidates add column if not exists origin text not null default 'FLK';
alter table candidates add column if not exists subject_type text;

-- 2. Allow the INIT_DIRECT audit action -------------------------------
alter table approval_audit drop constraint if exists approval_audit_action_check;
alter table approval_audit add constraint approval_audit_action_check
  check (action in ('SUBMIT','APPROVE','RETURN','SHORTLIST','REJECT','REVISE','REQUEST_CORRECTION','INIT_DIRECT'));

-- 3. Direct initiation function ---------------------------------------
-- p_subject_type: 'NEW_HIRE' (external direct hire) or 'POSITION_ONLY'
-- (budget for a planned position with no person yet).
create or replace function fn_init_direct_ol(p_code text, p_name text, p_position text, p_subject_type text, p_ol jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_uid uuid := auth.uid();
  v_grade text := p_ol->>'grade';
  v_entity text := p_ol->>'entity';
  v_mpp text := coalesce(p_ol->'basicData'->>'mppIndex','');
  v_mpn text := coalesce(p_ol->'basicData'->>'mpnNumber','');
  v_exists boolean;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if v_grade is null or v_grade = '' then raise exception 'grade required'; end if;
  if v_entity is null or v_entity = '' then raise exception 'entity required'; end if;
  -- Substitute gate: the position must be planned in MPP.
  if v_mpp = '' or v_mpn = '' then
    raise exception 'MPP Index and MPN Number are required for a direct OL' using errcode = 'P0001';
  end if;
  -- Maker authority for the grade, same rule as the FLK path.
  if not fn_can_act(v_uid, fn_maker(v_grade), v_entity) then
    raise exception 'not authorized to initiate OL as maker for grade %', v_grade using errcode = '42501';
  end if;
  if coalesce(p_subject_type,'') not in ('NEW_HIRE','POSITION_ONLY') then
    raise exception 'invalid subject_type, expected NEW_HIRE or POSITION_ONLY';
  end if;
  select exists(select 1 from candidates where code = p_code) into v_exists;
  if v_exists then raise exception 'code % already exists', p_code; end if;

  insert into candidates (code, name, email, position, origin, subject_type, stage, flk, ol, agreement, created_at, updated_at)
  values (
    p_code,
    coalesce(nullif(p_name,''), case when p_subject_type = 'POSITION_ONLY' then '(Posisi tanpa nama)' else 'Kandidat langsung' end),
    null,
    p_position,
    'COMBEN_DIRECT',
    p_subject_type,
    'OL_REVIEW',
    null,
    jsonb_set(p_ol, '{approvals}', '[]'::jsonb, true),
    null,
    now(), now()
  );

  insert into approval_audit (candidate_code, action, authority, acted_by, grade, ctc_annual, entity_id, from_stage, to_stage)
  values (p_code, 'INIT_DIRECT', fn_maker(v_grade), v_uid, v_grade, fn_ctc_annual(p_ol), v_entity, 'NONE', 'OL_REVIEW');

  return jsonb_build_object('ok', true, 'code', p_code, 'stage', 'OL_REVIEW', 'origin', 'COMBEN_DIRECT');
end $$;

grant execute on function fn_init_direct_ol(text,text,text,text,jsonb) to authenticated;

-- Note: approve and return already operate on any candidate at OL_REVIEW by
-- code, so the graduated approval chain works on direct OL with no change.
