-- =========================================================
-- Employee Private Parking Access System
-- Supabase schema.sql
-- Version: 1.0
--
-- هدف الملف:
-- يجهّز قاعدة البيانات كاملة لتطبيق كراج الموظفين:
-- - تسجيل الموظفين
-- - دخول أول مرة بعد التسجيل بشرط QR صالح
-- - شاشة الحارس realtime
-- - مسموح / مرفوض / مسموح جزئيًا
-- - حدود يومية حسب الاختصاص
-- - بلاغات الحارس بالصور
-- - أدمن / سوبر أدمن / مشرفين
-- - سجلات تدقيق Audit
--
-- مهم:
-- 1) شغّلي هذا الملف في Supabase SQL Editor.
-- 2) بعدها أنشئي مستخدمك من Authentication → Users.
-- 3) ثم شغّلي كود SUPER ADMIN الموجود في آخر الملف بعد تبديل القيم.
-- =========================================================

create extension if not exists "pgcrypto";

-- =========================================================
-- ADMIN PROFILES
-- =========================================================

create table if not exists public.admin_profiles (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique not null,
  email text unique not null,
  full_name text,
  role text not null check (role in ('SUPER_ADMIN', 'SUB_ADMIN')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.admin_profiles enable row level security;

-- =========================================================
-- EMPLOYEE REGISTRATIONS
-- =========================================================

create table if not exists public.employee_registrations (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  employee_id text not null unique,
  mobile_number text not null,
  specialty text not null,
  status text not null default 'PENDING' check (status in ('PENDING', 'APPROVED', 'REJECTED')),
  first_entry_used boolean not null default false,
  first_entry_at timestamptz,
  approved_at timestamptz,
  approved_by uuid,
  rejected_at timestamptz,
  rejected_by uuid,
  created_at timestamptz not null default now()
);

alter table public.employee_registrations enable row level security;

create index if not exists idx_employee_registrations_status
on public.employee_registrations(status);

create index if not exists idx_employee_registrations_employee_id
on public.employee_registrations(employee_id);

create index if not exists idx_employee_registrations_specialty
on public.employee_registrations(specialty);

-- =========================================================
-- SPECIALTY DAILY LIMITS
-- =========================================================

create table if not exists public.specialty_daily_limits (
  id uuid primary key default gen_random_uuid(),
  specialty_name text not null unique,
  daily_limit integer not null default 0 check (daily_limit >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.specialty_daily_limits enable row level security;

-- =========================================================
-- GATE ACCESS LOGS
-- =========================================================

create table if not exists public.gate_access_logs (
  id uuid primary key default gen_random_uuid(),
  employee_registration_id uuid references public.employee_registrations(id) on delete set null,
  employee_id text,
  mobile_number text,
  full_name text,
  specialty text,
  result text not null check (result in ('ALLOWED', 'DENIED', 'LIMITED', 'PENDING_FIRST_ENTRY')),
  reason text,
  qr_token uuid,
  created_at timestamptz not null default now()
);

alter table public.gate_access_logs enable row level security;

create index if not exists idx_gate_access_logs_created_at
on public.gate_access_logs(created_at);

create index if not exists idx_gate_access_logs_result
on public.gate_access_logs(result);

create index if not exists idx_gate_access_logs_specialty
on public.gate_access_logs(specialty);

-- =========================================================
-- GUARD SCREEN STATUS
-- one row only: id = 1
-- =========================================================

create table if not exists public.guard_screen_status (
  id integer primary key default 1 check (id = 1),
  current_status text not null default 'READY' check (current_status in ('READY', 'ALLOWED', 'DENIED', 'LIMITED')),
  employee_name text,
  employee_id text,
  message text,
  updated_at timestamptz not null default now()
);

alter table public.guard_screen_status enable row level security;

insert into public.guard_screen_status (id, current_status, message)
values (1, 'READY', 'QR جاهز للمسح')
on conflict (id) do nothing;

-- =========================================================
-- QR SESSIONS
-- كل QR له token ينتهي خلال 30 ثانية أو بعد أول استخدام.
-- =========================================================

create table if not exists public.qr_sessions (
  id uuid primary key default gen_random_uuid(),
  token uuid not null unique default gen_random_uuid(),
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.qr_sessions enable row level security;

create index if not exists idx_qr_sessions_token
on public.qr_sessions(token);

create index if not exists idx_qr_sessions_expires_at
on public.qr_sessions(expires_at);

-- =========================================================
-- VIOLATION REPORTS
-- صور مخالفات الحارس تحفظ في Supabase Storage.
-- الجدول يحفظ رابط الصورة.
-- =========================================================

create table if not exists public.violation_reports (
  id uuid primary key default gen_random_uuid(),
  employee_id text,
  note text,
  photo_url text not null,
  status text not null default 'NEW' check (status in ('NEW', 'REVIEWED', 'RESOLVED')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid
);

alter table public.violation_reports enable row level security;

create index if not exists idx_violation_reports_status
on public.violation_reports(status);

create index if not exists idx_violation_reports_created_at
on public.violation_reports(created_at);

-- =========================================================
-- ADMIN AUDIT LOGS
-- =========================================================

create table if not exists public.admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  admin_auth_user_id uuid,
  action text not null,
  target_table text,
  target_id text,
  details jsonb,
  created_at timestamptz not null default now()
);

alter table public.admin_audit_logs enable row level security;

create index if not exists idx_admin_audit_logs_created_at
on public.admin_audit_logs(created_at);

-- =========================================================
-- STORAGE BUCKET
-- =========================================================

insert into storage.buckets (id, name, public)
values ('violation-photos', 'violation-photos', true)
on conflict (id) do nothing;

-- =========================================================
-- HELPER FUNCTIONS
-- =========================================================

create or replace function public.current_admin_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role
  from public.admin_profiles
  where auth_user_id = auth.uid()
    and is_active = true
  limit 1;
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_admin_role() in ('SUPER_ADMIN', 'SUB_ADMIN'), false);
$$;

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_admin_role() = 'SUPER_ADMIN', false);
$$;

-- =========================================================
-- RLS POLICIES
-- =========================================================

-- admin_profiles
drop policy if exists "Admins can read admin profiles" on public.admin_profiles;
create policy "Admins can read admin profiles"
on public.admin_profiles
for select
to authenticated
using (public.is_admin());

drop policy if exists "Super admin can manage admin profiles" on public.admin_profiles;
create policy "Super admin can manage admin profiles"
on public.admin_profiles
for all
to authenticated
using (public.is_super_admin())
with check (public.is_super_admin());

-- employee_registrations
drop policy if exists "Admins can read registrations" on public.employee_registrations;
create policy "Admins can read registrations"
on public.employee_registrations
for select
to authenticated
using (public.is_admin());

drop policy if exists "Admins can update registrations" on public.employee_registrations;
create policy "Admins can update registrations"
on public.employee_registrations
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- specialty_daily_limits
drop policy if exists "Admins can read specialty limits" on public.specialty_daily_limits;
create policy "Admins can read specialty limits"
on public.specialty_daily_limits
for select
to authenticated
using (public.is_admin());

drop policy if exists "Super admin can manage specialty limits" on public.specialty_daily_limits;
create policy "Super admin can manage specialty limits"
on public.specialty_daily_limits
for all
to authenticated
using (public.is_super_admin())
with check (public.is_super_admin());

-- gate_access_logs
drop policy if exists "Admins can read access logs" on public.gate_access_logs;
create policy "Admins can read access logs"
on public.gate_access_logs
for select
to authenticated
using (public.is_admin());

-- guard_screen_status
drop policy if exists "Anyone can read guard screen status" on public.guard_screen_status;
create policy "Anyone can read guard screen status"
on public.guard_screen_status
for select
to anon, authenticated
using (true);

-- violation_reports
drop policy if exists "Admins can read violation reports" on public.violation_reports;
create policy "Admins can read violation reports"
on public.violation_reports
for select
to authenticated
using (public.is_admin());

drop policy if exists "Admins can update violation reports" on public.violation_reports;
create policy "Admins can update violation reports"
on public.violation_reports
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

-- admin_audit_logs
drop policy if exists "Admins can read audit logs" on public.admin_audit_logs;
create policy "Admins can read audit logs"
on public.admin_audit_logs
for select
to authenticated
using (public.is_admin());

-- Storage policies
drop policy if exists "Anyone can upload violation photos" on storage.objects;
create policy "Anyone can upload violation photos"
on storage.objects
for insert
to anon, authenticated
with check (bucket_id = 'violation-photos');

drop policy if exists "Anyone can read violation photos" on storage.objects;
create policy "Anyone can read violation photos"
on storage.objects
for select
to anon, authenticated
using (bucket_id = 'violation-photos');

-- =========================================================
-- RPC: get_my_admin_profile
-- =========================================================

create or replace function public.get_my_admin_profile()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  prof record;
begin
  select *
  into prof
  from public.admin_profiles
  where auth_user_id = auth.uid()
    and is_active = true
  limit 1;

  if prof.id is null then
    return jsonb_build_object('ok', false, 'message', 'غير مصرح لك بالدخول');
  end if;

  return jsonb_build_object(
    'ok', true,
    'id', prof.id,
    'email', prof.email,
    'full_name', prof.full_name,
    'role', prof.role
  );
end;
$$;

-- =========================================================
-- RPC: create_qr_session
-- =========================================================

create or replace function public.create_qr_session()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  new_token uuid;
begin
  delete from public.qr_sessions
  where expires_at < now() - interval '5 minutes';

  insert into public.qr_sessions (expires_at)
  values (now() + interval '30 seconds')
  returning token into new_token;

  return jsonb_build_object(
    'ok', true,
    'token', new_token::text,
    'expires_in_seconds', 30
  );
end;
$$;

-- =========================================================
-- RPC HELPER: validate_and_use_qr_token
-- =========================================================

create or replace function public.validate_and_use_qr_token(p_token text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  token_uuid uuid;
  found_id uuid;
begin
  if p_token is null or length(trim(p_token)) = 0 then
    return false;
  end if;

  begin
    token_uuid := p_token::uuid;
  exception when others then
    return false;
  end;

  select id
  into found_id
  from public.qr_sessions
  where token = token_uuid
    and used_at is null
    and expires_at > now()
  limit 1;

  if found_id is null then
    return false;
  end if;

  update public.qr_sessions
  set used_at = now()
  where id = found_id;

  return true;
end;
$$;

-- =========================================================
-- RPC HELPER: set_guard_status
-- =========================================================

create or replace function public.set_guard_status(
  p_status text,
  p_employee_name text,
  p_employee_id text,
  p_message text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.guard_screen_status
  set current_status = p_status,
      employee_name = p_employee_name,
      employee_id = p_employee_id,
      message = p_message,
      updated_at = now()
  where id = 1;
end;
$$;

-- =========================================================
-- RPC: reset_guard_screen
-- =========================================================

create or replace function public.reset_guard_screen()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.guard_screen_status
  set current_status = 'READY',
      employee_name = null,
      employee_id = null,
      message = 'QR جاهز للمسح',
      updated_at = now()
  where id = 1;

  return jsonb_build_object('ok', true);
end;
$$;

-- =========================================================
-- RPC: register_employee_request
-- الموظف الجديد يحصل على دخول أول مرة فقط إذا:
-- - أدخل الاسم + رقم الموظف + الهاتف + الاختصاص
-- - فتح من QR صالح وغير مستخدم
-- =========================================================

create or replace function public.register_employee_request(
  p_full_name text,
  p_employee_id text,
  p_mobile_number text,
  p_specialty text,
  p_qr_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
  qr_ok boolean := false;
  clean_name text := trim(p_full_name);
  clean_emp text := trim(p_employee_id);
  clean_mobile text := trim(p_mobile_number);
  clean_specialty text := trim(p_specialty);
begin
  if clean_name = '' or clean_emp = '' or clean_mobile = '' or clean_specialty = '' then
    return jsonb_build_object(
      'ok', false,
      'result', 'DENIED',
      'message', 'الرجاء تعبئة الاسم ورقم الموظف ورقم الهاتف والقسم'
    );
  end if;

  select *
  into reg
  from public.employee_registrations
  where employee_id = clean_emp
  limit 1;

  if reg.id is null then
    insert into public.employee_registrations (
      full_name,
      employee_id,
      mobile_number,
      specialty,
      status,
      first_entry_used,
      first_entry_at
    )
    values (
      clean_name,
      clean_emp,
      clean_mobile,
      clean_specialty,
      'PENDING',
      false,
      null
    )
    returning * into reg;
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

    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'تم رفض الطلب مسبقًا');

    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'تم رفض الطلب، يرجى مراجعة الإدارة'
    );
  end if;

  if reg.status = 'APPROVED' then
    return public.manual_employee_check(reg.employee_id, reg.mobile_number, p_qr_token);
  end if;

  if reg.first_entry_used = true then
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
      'PENDING_FIRST_ENTRY_ALREADY_USED'
    );

    perform public.set_guard_status('DENIED', reg.full_name, reg.employee_id, 'طلب قيد المراجعة — تم استخدام الدخول الأول سابقًا');

    return jsonb_build_object(
      'ok', true,
      'result', 'DENIED',
      'message', 'طلبك قيد المراجعة، وتم استخدام الدخول الأول سابقًا'
    );
  end if;

  -- التحقق من QR هنا فقط بعد التأكد أن الطلب PENDING ولم يستخدم الدخول الأول.
  qr_ok := public.validate_and_use_qr_token(p_qr_token);

  if qr_ok then
    update public.employee_registrations
    set first_entry_used = true,
        first_entry_at = now()
    where id = reg.id
    returning * into reg;

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
      'PENDING_FIRST_ENTRY',
      'FIRST_ENTRY_AFTER_REGISTRATION',
      p_qr_token::uuid
    );

    perform public.set_guard_status('LIMITED', reg.full_name, reg.employee_id, 'دخول أول مرة — بانتظار موافقة الإدارة');

    return jsonb_build_object(
      'ok', true,
      'result', 'LIMITED',
      'message', 'تم إرسال طلبك. تم السماح بدخول أول مرة فقط، والطلب بانتظار موافقة الإدارة'
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'result', 'PENDING',
    'message', 'تم إرسال طلبك، الرجاء انتظار موافقة الإدارة'
  );
end;
$$;

-- =========================================================
-- HELPER: permanently allowed specialties
-- خيار الإسعاف والطوارئ DRS/NRS/EMT/MLT مسموح دائمًا ولا يُحسب ضمن الحدود اليومية
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

-- =========================================================
-- RPC: manual_employee_check
-- الفحص اليدوي عند تعطل QR.
-- يتحقق من employee_id + mobile_number معًا.
-- =========================================================

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

-- =========================================================
-- RPC: submit_violation_report
-- =========================================================

create or replace function public.submit_violation_report(
  p_employee_id text,
  p_note text,
  p_photo_url text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
begin
  if p_photo_url is null or trim(p_photo_url) = '' then
    return jsonb_build_object('ok', false, 'message', 'الصورة مطلوبة');
  end if;

  insert into public.violation_reports (employee_id, note, photo_url)
  values (nullif(trim(p_employee_id), ''), nullif(trim(p_note), ''), trim(p_photo_url))
  returning id into new_id;

  return jsonb_build_object('ok', true, 'id', new_id, 'message', 'تم إرسال المخالفة إلى الإدارة');
end;
$$;

-- =========================================================
-- ADMIN RPC: update registration status
-- =========================================================

create or replace function public.admin_update_registration_status(
  p_registration_id uuid,
  p_status text
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

  if p_status not in ('APPROVED', 'REJECTED') then
    return jsonb_build_object('ok', false, 'message', 'حالة غير صحيحة');
  end if;

  update public.employee_registrations
  set status = p_status,
      approved_at = case when p_status = 'APPROVED' then now() else approved_at end,
      approved_by = case when p_status = 'APPROVED' then auth.uid() else approved_by end,
      rejected_at = case when p_status = 'REJECTED' then now() else rejected_at end,
      rejected_by = case when p_status = 'REJECTED' then auth.uid() else rejected_by end
  where id = p_registration_id
  returning * into reg;

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    target_id,
    details
  )
  values (
    auth.uid(),
    'UPDATE_REGISTRATION_STATUS',
    'employee_registrations',
    p_registration_id::text,
    jsonb_build_object('status', p_status)
  );

  return jsonb_build_object('ok', true, 'message', 'تم تحديث الطلب');
end;
$$;

-- =========================================================
-- ADMIN RPC: save specialty limit
-- =========================================================

create or replace function public.admin_upsert_specialty_limit(
  p_specialty_name text,
  p_daily_limit integer,
  p_is_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    return jsonb_build_object('ok', false, 'message', 'هذه العملية للسوبر أدمن فقط');
  end if;

  if trim(p_specialty_name) = '' then
    return jsonb_build_object('ok', false, 'message', 'اسم الاختصاص مطلوب');
  end if;

  insert into public.specialty_daily_limits (
    specialty_name,
    daily_limit,
    is_active,
    updated_at
  )
  values (
    trim(p_specialty_name),
    greatest(p_daily_limit, 0),
    p_is_active,
    now()
  )
  on conflict (specialty_name)
  do update set daily_limit = excluded.daily_limit,
                is_active = excluded.is_active,
                updated_at = now();

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    details
  )
  values (
    auth.uid(),
    'UPSERT_SPECIALTY_LIMIT',
    'specialty_daily_limits',
    jsonb_build_object(
      'specialty',
      p_specialty_name,
      'daily_limit',
      p_daily_limit,
      'is_active',
      p_is_active
    )
  );

  return jsonb_build_object('ok', true, 'message', 'تم حفظ حد الاختصاص');
end;
$$;

-- =========================================================
-- ADMIN RPC: update violation status
-- =========================================================

create or replace function public.admin_update_violation_status(
  p_violation_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    return jsonb_build_object('ok', false, 'message', 'غير مصرح');
  end if;

  if p_status not in ('NEW', 'REVIEWED', 'RESOLVED') then
    return jsonb_build_object('ok', false, 'message', 'حالة غير صحيحة');
  end if;

  update public.violation_reports
  set status = p_status,
      reviewed_at = now(),
      reviewed_by = auth.uid()
  where id = p_violation_id;

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    target_id,
    details
  )
  values (
    auth.uid(),
    'UPDATE_VIOLATION_STATUS',
    'violation_reports',
    p_violation_id::text,
    jsonb_build_object('status', p_status)
  );

  return jsonb_build_object('ok', true, 'message', 'تم تحديث البلاغ');
end;
$$;

-- =========================================================
-- SUPER ADMIN RPC: add / update admin profile
-- =========================================================

create or replace function public.super_admin_upsert_admin_profile(
  p_email text,
  p_full_name text,
  p_role text,
  p_is_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_user record;
begin
  if not public.is_super_admin() then
    return jsonb_build_object('ok', false, 'message', 'هذه العملية للسوبر أدمن فقط');
  end if;

  if p_role not in ('SUPER_ADMIN', 'SUB_ADMIN') then
    return jsonb_build_object('ok', false, 'message', 'دور غير صحيح');
  end if;

  select id, email
  into target_user
  from auth.users
  where lower(email) = lower(trim(p_email))
  limit 1;

  if target_user.id is null then
    return jsonb_build_object('ok', false, 'message', 'يجب إنشاء المستخدم أولًا من Supabase Auth');
  end if;

  insert into public.admin_profiles (
    auth_user_id,
    email,
    full_name,
    role,
    is_active
  )
  values (
    target_user.id,
    target_user.email,
    p_full_name,
    p_role,
    p_is_active
  )
  on conflict (auth_user_id)
  do update set full_name = excluded.full_name,
                role = excluded.role,
                is_active = excluded.is_active;

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    details
  )
  values (
    auth.uid(),
    'UPSERT_ADMIN_PROFILE',
    'admin_profiles',
    jsonb_build_object(
      'email',
      p_email,
      'role',
      p_role,
      'is_active',
      p_is_active
    )
  );

  return jsonb_build_object('ok', true, 'message', 'تم حفظ المشرف');
end;
$$;

-- =========================================================
-- DEFAULT SPECIALTY LIMITS
-- تستطيعين تعديلها لاحقًا من لوحة الأدمن.
-- =========================================================

insert into public.specialty_daily_limits (specialty_name, daily_limit, is_active)
values
('أطباء الاختصاصات الأخرى', 10, true),
('الأشعة', 5, true),
('المختبر', 5, true),
('التمريض', 20, false),
('التخدير', 5, false),
('الإدارة', 0, false),
('غير ذلك', 0, false)
on conflict (specialty_name) do nothing;

-- =========================================================
-- REALTIME
-- يجعل Realtime أكثر موثوقية.
-- إذا ظهر خطأ أن الجدول already member of publication، تجاهليه.
-- =========================================================

alter table public.guard_screen_status replica identity full;
alter table public.employee_registrations replica identity full;
alter table public.violation_reports replica identity full;
alter table public.gate_access_logs replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'guard_screen_status'
  ) then
    alter publication supabase_realtime add table public.guard_screen_status;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'employee_registrations'
  ) then
    alter publication supabase_realtime add table public.employee_registrations;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'violation_reports'
  ) then
    alter publication supabase_realtime add table public.violation_reports;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'gate_access_logs'
  ) then
    alter publication supabase_realtime add table public.gate_access_logs;
  end if;
end $$;

-- =========================================================
-- SUPER ADMIN SETUP
-- بعد إنشاء مستخدمك في Supabase Authentication → Users:
--
-- 1) انسخي User UID.
-- 2) بدلي القيم في الكود التالي.
-- 3) شغليه لوحده.
-- =========================================================

-- insert into public.admin_profiles (
--   auth_user_id,
--   email,
--   full_name,
--   role,
--   is_active
-- )
-- values (
--   'PASTE_YOUR_AUTH_USER_UID_HERE',
--   'PASTE_YOUR_AUTH_EMAIL_HERE',
--   'PASTE_YOUR_NAME_HERE',
--   'SUPER_ADMIN',
--   true
-- )
-- on conflict (auth_user_id)
-- do update set
--   email = excluded.email,
--   full_name = excluded.full_name,
--   role = 'SUPER_ADMIN',
--   is_active = true;


-- =========================================================
-- V1.1 PATCH — Hospital identity, final specialties, admin phone + permissions
-- يمكن تشغيل هذا الجزء بأمان حتى لو كان schema.sql شُغّل سابقًا.
-- =========================================================

alter table public.admin_profiles
add column if not exists phone_number text;

alter table public.admin_profiles
add column if not exists permissions jsonb not null default '{"can_approve_requests": true, "can_review_violations": true, "can_view_logs": true, "can_export_csv": false, "can_manage_limits": false, "can_view_audit": false}'::jsonb;

create or replace function public.default_admin_permissions(p_role text)
returns jsonb
language sql
stable
as $$
  select case
    when p_role = 'SUPER_ADMIN' then '{"can_approve_requests": true, "can_review_violations": true, "can_view_logs": true, "can_export_csv": true, "can_manage_limits": true, "can_view_audit": true}'::jsonb
    else '{"can_approve_requests": true, "can_review_violations": true, "can_view_logs": true, "can_export_csv": false, "can_manage_limits": false, "can_view_audit": false}'::jsonb
  end;
$$;

create or replace function public.has_admin_permission(p_permission text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  prof record;
begin
  select role, permissions, is_active
  into prof
  from public.admin_profiles
  where auth_user_id = auth.uid()
    and is_active = true
  limit 1;

  if prof.role = 'SUPER_ADMIN' then
    return true;
  end if;

  if prof.role is null then
    return false;
  end if;

  return coalesce((prof.permissions ->> p_permission)::boolean, false);
exception when others then
  return false;
end;
$$;

-- تحديث الاختصاصات النهائية والحد = 7
update public.specialty_daily_limits
set is_active = false
where specialty_name not in (
  'جراحة عامة',
  'باطني',
  'ENT',
  'نسائية',
  'مسالك بولية',
  'عيون',
  'جراحة دماغ وأعصاب',
  'تخدير',
  'طب عام',
  'جراحة أوعية دموية',
  'أخرى'
);

insert into public.specialty_daily_limits (specialty_name, daily_limit, is_active)
values
('جراحة عامة', 7, true),
('باطني', 7, true),
('ENT', 7, true),
('نسائية', 7, true),
('مسالك بولية', 7, true),
('عيون', 7, true),
('جراحة دماغ وأعصاب', 7, true),
('تخدير', 7, true),
('طب عام', 7, true),
('جراحة أوعية دموية', 7, true),
('أخرى', 7, true)
on conflict (specialty_name)
do update set
  daily_limit = 7,
  is_active = true,
  updated_at = now();

-- RLS policies updated for permissions
drop policy if exists "Admins can read admin profiles" on public.admin_profiles;
create policy "Admins can read admin profiles"
on public.admin_profiles
for select
to authenticated
using (
  auth_user_id = auth.uid()
  or public.is_super_admin()
);

drop policy if exists "Super admin can manage admin profiles" on public.admin_profiles;
create policy "Super admin can manage admin profiles"
on public.admin_profiles
for all
to authenticated
using (public.is_super_admin())
with check (public.is_super_admin());

drop policy if exists "Admins can read registrations" on public.employee_registrations;
create policy "Admins can read registrations"
on public.employee_registrations
for select
to authenticated
using (public.is_super_admin() or public.has_admin_permission('can_approve_requests'));

drop policy if exists "Admins can update registrations" on public.employee_registrations;
create policy "Admins can update registrations"
on public.employee_registrations
for update
to authenticated
using (public.is_super_admin() or public.has_admin_permission('can_approve_requests'))
with check (public.is_super_admin() or public.has_admin_permission('can_approve_requests'));

drop policy if exists "Admins can read access logs" on public.gate_access_logs;
create policy "Admins can read access logs"
on public.gate_access_logs
for select
to authenticated
using (public.is_super_admin() or public.has_admin_permission('can_view_logs'));

drop policy if exists "Admins can read violation reports" on public.violation_reports;
create policy "Admins can read violation reports"
on public.violation_reports
for select
to authenticated
using (public.is_super_admin() or public.has_admin_permission('can_review_violations'));

drop policy if exists "Admins can update violation reports" on public.violation_reports;
create policy "Admins can update violation reports"
on public.violation_reports
for update
to authenticated
using (public.is_super_admin() or public.has_admin_permission('can_review_violations'))
with check (public.is_super_admin() or public.has_admin_permission('can_review_violations'));

drop policy if exists "Super admin can manage specialty limits" on public.specialty_daily_limits;
create policy "Super admin can manage specialty limits"
on public.specialty_daily_limits
for all
to authenticated
using (public.is_super_admin() or public.has_admin_permission('can_manage_limits'))
with check (public.is_super_admin() or public.has_admin_permission('can_manage_limits'));

drop policy if exists "Admins can read audit logs" on public.admin_audit_logs;
create policy "Admins can read audit logs"
on public.admin_audit_logs
for select
to authenticated
using (public.is_super_admin() or public.has_admin_permission('can_view_audit'));

-- Updated profile function
create or replace function public.get_my_admin_profile()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  prof record;
begin
  select *
  into prof
  from public.admin_profiles
  where auth_user_id = auth.uid()
    and is_active = true
  limit 1;

  if prof.id is null then
    return jsonb_build_object('ok', false, 'message', 'غير مصرح لك بالدخول');
  end if;

  return jsonb_build_object(
    'ok', true,
    'id', prof.id,
    'email', prof.email,
    'full_name', prof.full_name,
    'phone_number', prof.phone_number,
    'role', prof.role,
    'permissions', coalesce(prof.permissions, public.default_admin_permissions(prof.role))
  );
end;
$$;

-- Updated admin registration action with permission check
create or replace function public.admin_update_registration_status(
  p_registration_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  reg record;
begin
  if not (public.is_super_admin() or public.has_admin_permission('can_approve_requests')) then
    return jsonb_build_object('ok', false, 'message', 'غير مصرح لك بالموافقة أو الرفض');
  end if;

  if p_status not in ('APPROVED', 'REJECTED') then
    return jsonb_build_object('ok', false, 'message', 'حالة غير صحيحة');
  end if;

  update public.employee_registrations
  set status = p_status,
      approved_at = case when p_status = 'APPROVED' then now() else approved_at end,
      approved_by = case when p_status = 'APPROVED' then auth.uid() else approved_by end,
      rejected_at = case when p_status = 'REJECTED' then now() else rejected_at end,
      rejected_by = case when p_status = 'REJECTED' then auth.uid() else rejected_by end
  where id = p_registration_id
  returning * into reg;

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    target_id,
    details
  )
  values (
    auth.uid(),
    'UPDATE_REGISTRATION_STATUS',
    'employee_registrations',
    p_registration_id::text,
    jsonb_build_object('status', p_status)
  );

  return jsonb_build_object('ok', true, 'message', 'تم تحديث الطلب');
end;
$$;

-- Updated specialty limits function with permissions
create or replace function public.admin_upsert_specialty_limit(
  p_specialty_name text,
  p_daily_limit integer,
  p_is_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_super_admin() or public.has_admin_permission('can_manage_limits')) then
    return jsonb_build_object('ok', false, 'message', 'غير مصرح لك بتعديل حدود الاختصاصات');
  end if;

  if trim(p_specialty_name) = '' then
    return jsonb_build_object('ok', false, 'message', 'اسم الاختصاص مطلوب');
  end if;

  insert into public.specialty_daily_limits (
    specialty_name,
    daily_limit,
    is_active,
    updated_at
  )
  values (
    trim(p_specialty_name),
    greatest(p_daily_limit, 0),
    p_is_active,
    now()
  )
  on conflict (specialty_name)
  do update set daily_limit = excluded.daily_limit,
                is_active = excluded.is_active,
                updated_at = now();

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    details
  )
  values (
    auth.uid(),
    'UPSERT_SPECIALTY_LIMIT',
    'specialty_daily_limits',
    jsonb_build_object(
      'specialty',
      p_specialty_name,
      'daily_limit',
      p_daily_limit,
      'is_active',
      p_is_active
    )
  );

  return jsonb_build_object('ok', true, 'message', 'تم حفظ حد الاختصاص');
end;
$$;

-- Updated violation status function with permissions
create or replace function public.admin_update_violation_status(
  p_violation_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_super_admin() or public.has_admin_permission('can_review_violations')) then
    return jsonb_build_object('ok', false, 'message', 'غير مصرح لك بمراجعة البلاغات');
  end if;

  if p_status not in ('NEW', 'REVIEWED', 'RESOLVED') then
    return jsonb_build_object('ok', false, 'message', 'حالة غير صحيحة');
  end if;

  update public.violation_reports
  set status = p_status,
      reviewed_at = now(),
      reviewed_by = auth.uid()
  where id = p_violation_id;

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    target_id,
    details
  )
  values (
    auth.uid(),
    'UPDATE_VIOLATION_STATUS',
    'violation_reports',
    p_violation_id::text,
    jsonb_build_object('status', p_status)
  );

  return jsonb_build_object('ok', true, 'message', 'تم تحديث البلاغ');
end;
$$;

-- Updated super admin function: add/update admins with phone and permissions
create or replace function public.super_admin_upsert_admin_profile(
  p_email text,
  p_full_name text,
  p_phone_number text,
  p_role text,
  p_is_active boolean,
  p_permissions jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  target_user record;
  final_permissions jsonb;
begin
  if not public.is_super_admin() then
    return jsonb_build_object('ok', false, 'message', 'هذه العملية للسوبر أدمن فقط');
  end if;

  if p_role not in ('SUPER_ADMIN', 'SUB_ADMIN') then
    return jsonb_build_object('ok', false, 'message', 'دور غير صحيح');
  end if;

  select id, email
  into target_user
  from auth.users
  where lower(email) = lower(trim(p_email))
  limit 1;

  if target_user.id is null then
    return jsonb_build_object('ok', false, 'message', 'يجب إنشاء المستخدم أولًا من Supabase Auth بنفس الإيميل');
  end if;

  final_permissions := coalesce(p_permissions, public.default_admin_permissions(p_role));

  insert into public.admin_profiles (
    auth_user_id,
    email,
    full_name,
    phone_number,
    role,
    is_active,
    permissions
  )
  values (
    target_user.id,
    target_user.email,
    p_full_name,
    p_phone_number,
    p_role,
    p_is_active,
    final_permissions
  )
  on conflict (auth_user_id)
  do update set full_name = excluded.full_name,
                phone_number = excluded.phone_number,
                role = excluded.role,
                is_active = excluded.is_active,
                permissions = excluded.permissions;

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    details
  )
  values (
    auth.uid(),
    'UPSERT_ADMIN_PROFILE',
    'admin_profiles',
    jsonb_build_object(
      'email',
      p_email,
      'full_name',
      p_full_name,
      'phone_number',
      p_phone_number,
      'role',
      p_role,
      'is_active',
      p_is_active,
      'permissions',
      final_permissions
    )
  );

  return jsonb_build_object('ok', true, 'message', 'تم حفظ المشرف');
end;
$$;

create or replace function public.super_admin_disable_admin_profile(
  p_admin_profile_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    return jsonb_build_object('ok', false, 'message', 'هذه العملية للسوبر أدمن فقط');
  end if;

  if exists (
    select 1 from public.admin_profiles
    where id = p_admin_profile_id
      and auth_user_id = auth.uid()
  ) then
    return jsonb_build_object('ok', false, 'message', 'لا يمكنك تعطيل حسابك الحالي');
  end if;

  update public.admin_profiles
  set is_active = false
  where id = p_admin_profile_id;

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    target_id
  )
  values (
    auth.uid(),
    'DISABLE_ADMIN_PROFILE',
    'admin_profiles',
    p_admin_profile_id::text
  );

  return jsonb_build_object('ok', true, 'message', 'تم تعطيل المشرف');
end;
$$;

create or replace function public.super_admin_delete_admin_profile(
  p_admin_profile_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    return jsonb_build_object('ok', false, 'message', 'هذه العملية للسوبر أدمن فقط');
  end if;

  if exists (
    select 1 from public.admin_profiles
    where id = p_admin_profile_id
      and auth_user_id = auth.uid()
  ) then
    return jsonb_build_object('ok', false, 'message', 'لا يمكنك حذف حسابك الحالي');
  end if;

  delete from public.admin_profiles
  where id = p_admin_profile_id;

  insert into public.admin_audit_logs (
    admin_auth_user_id,
    action,
    target_table,
    target_id
  )
  values (
    auth.uid(),
    'DELETE_ADMIN_PROFILE',
    'admin_profiles',
    p_admin_profile_id::text
  );

  return jsonb_build_object('ok', true, 'message', 'تم حذف المشرف من لوحة الإدارة');
end;
$$;

-- Update existing super admin record with phone field and full permissions if already exists
update public.admin_profiles
set full_name = 'Dr. Alaa Aqrabawi',
    permissions = public.default_admin_permissions('SUPER_ADMIN')
where lower(email) = lower('kisscrisis@list.ru')
  and role = 'SUPER_ADMIN';


-- =========================================================
-- schema_patch_qr_claim.sql
-- Emergency Room Parking V1.6
--
-- السبب:
-- QR token صالح 30 ثانية فقط. إذا الموظف مسح QR ثم أخذ وقتًا بإدخال بياناته،
-- كان النظام يرفضه لأن token انتهى قبل الضغط على إرسال.
--
-- الحل:
-- عند فتح verify.html من QR، يتم Claim للـ QR فورًا خلال أول 30 ثانية.
-- بعدها يحصل المستخدم على claim_token صالح لمدة 5 دقائق لإكمال النموذج.
--
-- الأمان:
-- - QR الأصلي يبقى صالح 30 ثانية فقط.
-- - بمجرد أن يفتحه أول شخص، يتم استعماله ولا يعود صالحًا لشخص آخر.
-- - claim_token يستخدم مرة واحدة فقط.
-- =========================================================

alter table public.qr_sessions
add column if not exists claim_token uuid unique;

alter table public.qr_sessions
add column if not exists claimed_at timestamptz;

alter table public.qr_sessions
add column if not exists claim_expires_at timestamptz;

alter table public.qr_sessions
add column if not exists claim_used_at timestamptz;

create index if not exists idx_qr_sessions_claim_token
on public.qr_sessions(claim_token);

create index if not exists idx_qr_sessions_claim_expires_at
on public.qr_sessions(claim_expires_at);

create or replace function public.claim_qr_session(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  token_uuid uuid;
  found_id uuid;
  new_claim uuid := gen_random_uuid();
begin
  if p_token is null or length(trim(p_token)) = 0 then
    return jsonb_build_object(
      'ok', false,
      'message', 'QR غير موجود'
    );
  end if;

  begin
    token_uuid := p_token::uuid;
  exception when others then
    return jsonb_build_object(
      'ok', false,
      'message', 'QR غير صحيح'
    );
  end;

  select id
  into found_id
  from public.qr_sessions
  where token = token_uuid
    and used_at is null
    and expires_at > now()
  limit 1;

  if found_id is null then
    return jsonb_build_object(
      'ok', false,
      'message', 'QR غير صالح أو منتهي، يرجى مسح QR جديد من شاشة الحارس'
    );
  end if;

  update public.qr_sessions
  set used_at = now(),
      claimed_at = now(),
      claim_token = new_claim,
      claim_expires_at = now() + interval '5 minutes',
      claim_used_at = null
  where id = found_id;

  return jsonb_build_object(
    'ok', true,
    'claim_token', new_claim::text,
    'expires_in_seconds', 300,
    'message', 'تم تفعيل جلسة QR، أكمل البيانات خلال 5 دقائق'
  );
end;
$$;

create or replace function public.validate_and_use_qr_token(p_token text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  input_uuid uuid;
  found_id uuid;
begin
  if p_token is null or length(trim(p_token)) = 0 then
    return false;
  end if;

  begin
    input_uuid := p_token::uuid;
  exception when others then
    return false;
  end;

  -- Backward compatibility: direct QR token use within original 30 seconds.
  select id
  into found_id
  from public.qr_sessions
  where token = input_uuid
    and used_at is null
    and expires_at > now()
  limit 1;

  if found_id is not null then
    update public.qr_sessions
    set used_at = now()
    where id = found_id;

    return true;
  end if;

  -- V1.6: claimed QR token. User opened QR on time, then has 5 minutes to submit form.
  select id
  into found_id
  from public.qr_sessions
  where claim_token = input_uuid
    and claim_used_at is null
    and claim_expires_at > now()
  limit 1;

  if found_id is not null then
    update public.qr_sessions
    set claim_used_at = now()
    where id = found_id;

    return true;
  end if;

  return false;
end;
$$;

grant execute on function public.claim_qr_session(text) to anon, authenticated;
grant execute on function public.validate_and_use_qr_token(text) to anon, authenticated;

notify pgrst, 'reload schema';

-- اختبار سريع بعد التشغيل:
-- افتحي QR جديد من شاشة الحارس، امسحيه، يجب أن يظهر في صفحة verify أن جلسة QR فعالة.
