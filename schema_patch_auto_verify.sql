-- =========================================================
-- schema_patch_auto_verify.sql
-- Emergency Room Parking - Auto trusted-device verification
--
-- الهدف:
-- 5) الموظف يسجل مرة واحدة فقط، وبعد الموافقة يستخدم التحقق.
-- 6) موظف الدخول الدائم يمكنه مسح QR فقط، فيتعرف النظام على جهازه الموثوق
--    بدون إدخال رقم الموظف كل مرة.
--
-- مهم:
-- شغلي هذا الملف مرة واحدة فقط من Supabase SQL Editor بعد التأكد أن النسخة الحالية تعمل.
-- لا تشغلي schema.sql الكامل من جديد فوق قاعدة شغالة.
-- =========================================================

create extension if not exists "pgcrypto";

-- 1) أعمدة الجهاز الموثوق داخل جدول الموظفين
alter table public.employee_registrations
add column if not exists trusted_device_enabled boolean not null default false;

alter table public.employee_registrations
add column if not exists trusted_device_token_hash text;

alter table public.employee_registrations
add column if not exists trusted_device_registered_at timestamptz;

alter table public.employee_registrations
add column if not exists trusted_device_last_used_at timestamptz;

alter table public.employee_registrations
add column if not exists trusted_device_revoked_at timestamptz;

create index if not exists idx_employee_registrations_trusted_device_token_hash
on public.employee_registrations(trusted_device_token_hash)
where trusted_device_token_hash is not null;

create index if not exists idx_employee_registrations_trusted_device_enabled
on public.employee_registrations(trusted_device_enabled);

-- 2) Hash helper: لا نخزن رمز الجهاز الخام في قاعدة البيانات
create or replace function public.hash_trusted_device_token(p_token text)
returns text
language sql
immutable
as $$
  select encode(digest(trim(coalesce(p_token, '')), 'sha256'), 'hex');
$$;

-- 3) فحص أهلية الموظف لتفعيل التحقق السريع من جهازه
create or replace function public.can_register_trusted_device(
  p_employee_id text,
  p_mobile_number text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  clean_emp text := trim(coalesce(p_employee_id, ''));
  clean_mobile text := trim(coalesce(p_mobile_number, ''));
begin
  if clean_emp = '' or clean_mobile = '' then
    return jsonb_build_object('ok', false, 'eligible', false, 'message', 'رقم الموظف ورقم الهاتف مطلوبان');
  end if;

  select *
  into reg
  from public.employee_registrations
  where employee_id = clean_emp
    and mobile_number = clean_mobile
  limit 1;

  if reg.id is null then
    return jsonb_build_object('ok', true, 'eligible', false, 'message', 'الموظف غير موجود');
  end if;

  if reg.status <> 'APPROVED' then
    return jsonb_build_object('ok', true, 'eligible', false, 'message', 'التفعيل متاح بعد موافقة الإدارة فقط');
  end if;

  if not public.is_permanently_allowed_specialty(reg.specialty) then
    return jsonb_build_object('ok', true, 'eligible', false, 'message', 'التحقق السريع مخصص لاختصاص الدخول الدائم فقط');
  end if;

  if coalesce(reg.trusted_device_enabled, false) = false then
    return jsonb_build_object('ok', true, 'eligible', false, 'message', 'الإدارة لم تفعل التحقق السريع لهذا الموظف بعد');
  end if;

  return jsonb_build_object(
    'ok', true,
    'eligible', true,
    'already_linked', reg.trusted_device_token_hash is not null,
    'message', 'يمكن تفعيل التحقق السريع على هذا الجهاز'
  );
end;
$$;

-- 4) ربط هذا الجهاز بموظف بعد التحقق اليدوي الصحيح
create or replace function public.register_trusted_device(
  p_employee_id text,
  p_mobile_number text,
  p_device_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  clean_emp text := trim(coalesce(p_employee_id, ''));
  clean_mobile text := trim(coalesce(p_mobile_number, ''));
  clean_token text := trim(coalesce(p_device_token, ''));
begin
  if clean_emp = '' or clean_mobile = '' or length(clean_token) < 40 then
    return jsonb_build_object('ok', false, 'message', 'بيانات تفعيل الجهاز غير مكتملة');
  end if;

  select *
  into reg
  from public.employee_registrations
  where employee_id = clean_emp
    and mobile_number = clean_mobile
  limit 1;

  if reg.id is null then
    return jsonb_build_object('ok', false, 'message', 'الموظف غير موجود');
  end if;

  if reg.status <> 'APPROVED' then
    return jsonb_build_object('ok', false, 'message', 'لا يمكن ربط الجهاز قبل موافقة الإدارة');
  end if;

  if not public.is_permanently_allowed_specialty(reg.specialty) then
    return jsonb_build_object('ok', false, 'message', 'التحقق السريع مخصص لاختصاص الدخول الدائم فقط');
  end if;

  if coalesce(reg.trusted_device_enabled, false) = false then
    return jsonb_build_object('ok', false, 'message', 'الإدارة لم تفعل التحقق السريع لهذا الموظف بعد');
  end if;

  update public.employee_registrations
  set trusted_device_token_hash = public.hash_trusted_device_token(clean_token),
      trusted_device_registered_at = now(),
      trusted_device_last_used_at = null,
      trusted_device_revoked_at = null
  where id = reg.id;

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    target_id,
    details
  ) values (
    null,
    'TRUSTED_DEVICE_LINKED_BY_EMPLOYEE',
    'employee_registrations',
    reg.id::text,
    jsonb_build_object('employee_id', reg.employee_id)
  );

  return jsonb_build_object('ok', true, 'message', 'تم ربط هذا الجهاز بنجاح. في المرات القادمة امسح QR فقط.');
end;
$$;

-- 5) تحقق تلقائي من رمز الجهاز الموثوق + QR
-- ملاحظة أمان وتجربة استخدام:
-- لا يتم استهلاك QR إلا بعد التأكد أن رمز الجهاز مربوط بموظف مؤهل.
-- إذا كان الرمز المحلي قديمًا أو ملغيًا، يبقى QR صالحًا للتعبئة اليدوية خلال مهلة الـ 5 دقائق.
create or replace function public.auto_employee_check(
  p_device_token text,
  p_qr_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  clean_token text := trim(coalesce(p_device_token, ''));
  qr_ok boolean := false;
begin
  if length(clean_token) < 40 then
    return jsonb_build_object(
      'ok', false,
      'result', 'DENIED',
      'clear_device', true,
      'message', 'رمز الجهاز غير صالح. أعد التفعيل من التحقق اليدوي.'
    );
  end if;

  select *
  into reg
  from public.employee_registrations
  where trusted_device_enabled = true
    and trusted_device_token_hash = public.hash_trusted_device_token(clean_token)
  limit 1;

  if reg.id is null then
    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'clear_device', true,
      'message', 'هذا الجهاز غير مربوط أو تم إلغاء ربطه. استخدم التحقق اليدوي ثم أعد التفعيل.'
    );
  end if;

  if reg.status <> 'APPROVED' then
    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'clear_device', true,
      'message', 'الموظف غير معتمد حاليًا'
    );
  end if;

  if not public.is_permanently_allowed_specialty(reg.specialty) then
    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'التحقق السريع مخصص لاختصاص الدخول الدائم فقط'
    );
  end if;

  if p_qr_token is null or length(trim(p_qr_token)) = 0 then
    return jsonb_build_object(
      'ok', false,
      'result', 'DENIED',
      'message', 'يجب مسح QR مباشر من شاشة الحارس'
    );
  end if;

  qr_ok := public.validate_and_use_qr_token(p_qr_token);

  if qr_ok = false then
    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'QR غير صالح أو منتهي');
    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'QR غير صالح أو منتهي، يرجى مسح QR جديد'
    );
  end if;

  update public.employee_registrations
  set trusted_device_last_used_at = now()
  where id = reg.id;

  insert into public.gate_access_logs (
    employee_registration_id,
    employee_id,
    mobile_number,
    full_name,
    specialty,
    result,
    reason,
    qr_token
  ) values (
    reg.id,
    reg.employee_id,
    reg.mobile_number,
    reg.full_name,
    reg.specialty,
    'ALLOWED',
    'AUTO_TRUSTED_DEVICE',
    case when p_qr_token is null or p_qr_token = '' then null else p_qr_token::uuid end
  );

  perform public.set_guard_status(
    'ALLOWED',
    reg.full_name,
    reg.employee_id,
    'مسموح بالدخول — تحقق تلقائي من جهاز موثوق'
  );

  return jsonb_build_object(
    'ok', true,
    'result', 'ALLOWED',
    'message', 'مسموح بالدخول — تم التحقق تلقائيًا من الجهاز الموثوق',
    'employee_id', reg.employee_id,
    'full_name', reg.full_name
  );
end;
$$;

-- 6) تحكم الأدمن: تفعيل/تعطيل/إلغاء ربط الجهاز
create or replace function public.admin_set_trusted_device(
  p_registration_id uuid,
  p_enabled boolean,
  p_revoke boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
begin
  if not public.is_admin() then
    return jsonb_build_object('ok', false, 'message', 'غير مصرح');
  end if;

  select *
  into reg
  from public.employee_registrations
  where id = p_registration_id
  limit 1;

  if reg.id is null then
    return jsonb_build_object('ok', false, 'message', 'الموظف غير موجود');
  end if;

  if p_enabled = true then
    if reg.status <> 'APPROVED' then
      return jsonb_build_object('ok', false, 'message', 'يجب اعتماد الموظف أولًا');
    end if;

    if not public.is_permanently_allowed_specialty(reg.specialty) then
      return jsonb_build_object('ok', false, 'message', 'التحقق السريع مخصص لاختصاص الدخول الدائم فقط');
    end if;
  end if;

  update public.employee_registrations
  set trusted_device_enabled = p_enabled,
      trusted_device_token_hash = case when p_revoke or p_enabled = false then null else trusted_device_token_hash end,
      trusted_device_registered_at = case when p_revoke or p_enabled = false then null else trusted_device_registered_at end,
      trusted_device_last_used_at = case when p_revoke or p_enabled = false then null else trusted_device_last_used_at end,
      trusted_device_revoked_at = case when p_revoke or p_enabled = false then now() else trusted_device_revoked_at end
  where id = p_registration_id;

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    target_id,
    details
  ) values (
    auth.uid(),
    'ADMIN_SET_TRUSTED_DEVICE',
    'employee_registrations',
    p_registration_id::text,
    jsonb_build_object(
      'enabled', p_enabled,
      'revoked', p_revoke,
      'employee_id', reg.employee_id
    )
  );

  return jsonb_build_object(
    'ok', true,
    'message', case
      when p_enabled = false then 'تم تعطيل التحقق السريع وإلغاء ربط الجهاز'
      when p_revoke = true then 'تم إلغاء ربط الجهاز. يستطيع الموظف ربط جهاز جديد من التحقق اليدوي.'
      else 'تم تفعيل التحقق السريع. على الموظف إجراء تحقق يدوي مرة واحدة لربط جهازه.'
    end
  );
end;
$$;

grant execute on function public.can_register_trusted_device(text, text) to anon, authenticated;
grant execute on function public.register_trusted_device(text, text, text) to anon, authenticated;
grant execute on function public.auto_employee_check(text, text) to anon, authenticated;
grant execute on function public.admin_set_trusted_device(uuid, boolean, boolean) to authenticated;

notify pgrst, 'reload schema';
