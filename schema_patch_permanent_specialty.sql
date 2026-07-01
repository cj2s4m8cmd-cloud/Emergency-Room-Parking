-- =========================================================
-- PATCH: Permanently allowed specialty option
-- الإسعاف والطوارئ (DRS/NRS/EMT/MLT)
-- شغّلي هذا الملف في Supabase SQL Editor إذا كانت قاعدة البيانات موجودة مسبقًا.
-- =========================================================

create or replace function public.normalize_specialty_name(p_specialty text)
returns text
language plpgsql
immutable
as $$
declare
  v text;
begin
  v := upper(trim(coalesce(p_specialty, '')));

  v := replace(v, 'أ', 'ا');
  v := replace(v, 'إ', 'ا');
  v := replace(v, 'آ', 'ا');
  v := replace(v, 'ٱ', 'ا');
  v := replace(v, 'ة', 'ه');

  v := regexp_replace(v, '\s+', '', 'g');
  v := replace(v, '،', ',');
  v := replace(v, '／', '/');
  v := replace(v, '(', '');
  v := replace(v, ')', '');
  v := replace(v, '-', '');

  return v;
end;
$$;

create or replace function public.is_permanently_allowed_specialty(p_specialty text)
returns boolean
language plpgsql
immutable
as $$
declare
  v text;
begin
  v := public.normalize_specialty_name(p_specialty);

  return v in (
    public.normalize_specialty_name('الإسعاف والطوارئ (DRS/NRS/EMT/MLT)'),
    public.normalize_specialty_name('الإسعاف والطوارئ - DRS/NRS/EMT/MLT'),
    public.normalize_specialty_name('الإسعاف والطوارئ DRS,NRS,EMT/MLT'),
    public.normalize_specialty_name('DRS,NRS,EMT/MLT'),
    public.normalize_specialty_name('DRS/NRS/EMT/MLT'),
    public.normalize_specialty_name('الإسعاف والطوارئ')
  );
end;
$$;

create or replace function public.manual_employee_check(
  p_employee_id text,
  p_mobile_number text,
  p_qr_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  lim record;
  used_count integer := 0;
  qr_required boolean := false;
  qr_ok boolean := true;
  clean_emp text := trim(p_employee_id);
  clean_mobile text := trim(p_mobile_number);
begin
  if clean_emp = '' or clean_mobile = '' then
    return jsonb_build_object('ok', false, 'result', 'DENIED', 'message', 'أدخل رقم الموظف ورقم الهاتف');
  end if;

  if p_qr_token is not null and length(trim(p_qr_token)) > 0 then
    qr_required := true;
    qr_ok := public.validate_and_use_qr_token(p_qr_token);
  end if;

  if qr_required and qr_ok = false then
    perform public.set_guard_status('DENIED', null, clean_emp, 'QR غير صالح أو منتهي');
    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'QR غير صالح أو منتهي، يرجى مسح QR جديد'
    );
  end if;

  select *
  into reg
  from public.employee_registrations
  where employee_id = clean_emp
    and mobile_number = clean_mobile
  limit 1;

  if reg.id is null then
    perform public.set_guard_status('DENIED', null, clean_emp, 'الموظف غير موجود');
    return jsonb_build_object(
      'ok', true,
      'result', 'NOT_FOUND',
      'message', 'الموظف غير موجود، الرجاء التسجيل أولًا'
    );
  end if;

  if reg.status = 'PENDING' then
    insert into public.gate_access_logs (
      employee_registration_id,
      employee_id,
      mobile_number,
      full_name,
      specialty,
      result,
      reason
    )
    values (
      reg.id,
      reg.employee_id,
      reg.mobile_number,
      reg.full_name,
      reg.specialty,
      'DENIED',
      'PENDING_EMPLOYEE'
    );

    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'طلب قيد المراجعة');

    return jsonb_build_object('ok', true, 'result', 'DENIED', 'message', 'طلبك قيد المراجعة');
  end if;

  if reg.status = 'REJECTED' then
    insert into public.gate_access_logs (
      employee_registration_id,
      employee_id,
      mobile_number,
      full_name,
      specialty,
      result,
      reason
    )
    values (
      reg.id,
      reg.employee_id,
      reg.mobile_number,
      reg.full_name,
      reg.specialty,
      'DENIED',
      'REJECTED_EMPLOYEE'
    );

    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'تم رفض الطلب');

    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'تم رفض الطلب، يرجى مراجعة الإدارة'
    );
  end if;

  -- Permanently allowed specialty group:
  -- الإسعاف والطوارئ (DRS/NRS/EMT/MLT)
  -- هذا الاختصاص لا يدخل في specialty_daily_limits ولا يتحول إلى LIMITED.
  if public.is_permanently_allowed_specialty(reg.specialty) then
    insert into public.gate_access_logs (
      employee_registration_id,
      employee_id,
      mobile_number,
      full_name,
      specialty,
      result,
      reason,
      qr_token
    )
    values (
      reg.id,
      reg.employee_id,
      reg.mobile_number,
      reg.full_name,
      reg.specialty,
      'ALLOWED',
      'PERMANENTLY_ALLOWED_SPECIALTY',
      case when p_qr_token is null or p_qr_token = '' then null else p_qr_token::uuid end
    );

    perform public.set_guard_status(
      'ALLOWED',
      reg.full_name,
      reg.employee_id,
      'مسموح بالدخول — اختصاص مسموح دائمًا'
    );

    return jsonb_build_object(
      'ok', true,
      'result', 'ALLOWED',
      'message', 'مسموح بالدخول — اختصاص مسموح دائمًا'
    );
  end if;

  -- APPROVED employee: check specialty limit.
  select *
  into lim
  from public.specialty_daily_limits
  where specialty_name = reg.specialty
    and is_active = true
  limit 1;

  if lim.id is not null then
    select count(*)
    into used_count
    from public.gate_access_logs
    where specialty = reg.specialty
      and result = 'LIMITED'
      and created_at >= date_trunc('day', now())
      and created_at < date_trunc('day', now()) + interval '1 day';

    if used_count >= lim.daily_limit then
      insert into public.gate_access_logs (
        employee_registration_id,
        employee_id,
        mobile_number,
        full_name,
        specialty,
        result,
        reason
      )
      values (
        reg.id,
        reg.employee_id,
        reg.mobile_number,
        reg.full_name,
        reg.specialty,
        'DENIED',
        'SPECIALTY_DAILY_LIMIT_REACHED'
      );

      perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'تم الوصول للحد اليومي لهذا الاختصاص');

      return jsonb_build_object(
        'ok', true,
        'result', 'DENIED',
        'message', 'غير مسموح — تم الوصول للحد اليومي لهذا الاختصاص'
      );
    end if;

    insert into public.gate_access_logs (
      employee_registration_id,
      employee_id,
      mobile_number,
      full_name,
      specialty,
      result,
      reason,
      qr_token
    )
    values (
      reg.id,
      reg.employee_id,
      reg.mobile_number,
      reg.full_name,
      reg.specialty,
      'LIMITED',
      'SPECIALTY_LIMITED_ACCESS',
      case when p_qr_token is null or p_qr_token = '' then null else p_qr_token::uuid end
    );

    perform public.set_guard_status('LIMITED', reg.full_name, reg.employee_id, 'مسموح جزئيًا حسب الاختصاص');

    return jsonb_build_object('ok', true, 'result', 'LIMITED', 'message', 'مسموح جزئيًا حسب الاختصاص');
  end if;

  insert into public.gate_access_logs (
    employee_registration_id,
    employee_id,
    mobile_number,
    full_name,
    specialty,
    result,
    reason,
    qr_token
  )
  values (
    reg.id,
    reg.employee_id,
    reg.mobile_number,
    reg.full_name,
    reg.specialty,
    'ALLOWED',
    'APPROVED_EMPLOYEE',
    case when p_qr_token is null or p_qr_token = '' then null else p_qr_token::uuid end
  );

  perform public.set_guard_status('ALLOWED', reg.full_name, reg.employee_id, 'مسموح بالدخول');

  return jsonb_build_object('ok', true, 'result', 'ALLOWED', 'message', 'مسموح بالدخول');
end;
$$;

notify pgrst, 'reload schema';

-- بعد تشغيل الباتش: الموظف APPROVED صاحب هذا الاختصاص سيظهر ALLOWED دائمًا.
