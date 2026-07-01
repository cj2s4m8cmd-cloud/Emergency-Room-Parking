-- =========================================================
-- setup_sub_admins.sql
-- Emergency Room Parking
--
-- هذا الملف يضيف المشرفين الفرعيين SUB_ADMIN مباشرة.
--
-- قبل تشغيله:
-- 1) شغّلي schema.sql أولًا.
-- 2) تأكدي أن هؤلاء المستخدمين موجودون في:
--    Supabase → Authentication → Users
-- 3) لا تضعي كلمات المرور هنا.
--
-- الصلاحيات الافتراضية:
-- - موافقة / رفض طلبات التسجيل: نعم
-- - مراجعة بلاغات الحارس: نعم
-- - رؤية سجلات الدخول والإحصائيات: نعم
-- - تصدير CSV: لا
-- - تعديل حدود الاختصاصات اليومية: لا
-- - رؤية Audit: لا
--
-- يمكنك تغيير الصلاحيات لاحقًا من:
-- admin_dashboard.html → Admins
-- =========================================================

alter table public.admin_profiles
add column if not exists phone_number text;

alter table public.admin_profiles
add column if not exists permissions jsonb not null default '{"can_approve_requests": true, "can_review_violations": true, "can_view_logs": true, "can_export_csv": false, "can_manage_limits": false, "can_view_audit": false}'::jsonb;

insert into public.admin_profiles (
  auth_user_id,
  email,
  full_name,
  phone_number,
  role,
  is_active,
  permissions
)
values
(
  'fa07528b-7173-4e8f-8aae-103a8379cd17'::uuid,
  'osamakan@yahoo.com',
  'Dr. Osama Kanan / د. أسامه كنعان',
  '07 9553 4663',
  'SUB_ADMIN',
  true,
  '{"can_approve_requests": true, "can_review_violations": true, "can_view_logs": true, "can_export_csv": false, "can_manage_limits": false, "can_view_audit": false}'::jsonb
),
(
  '86506d29-d00f-4c8d-b355-b04f84845d18'::uuid,
  'hasanshehadeh@yahoo.com',
  'Dr. Hasan Shehadeh / د. حسن شحاده',
  '07 9130 4742',
  'SUB_ADMIN',
  true,
  '{"can_approve_requests": true, "can_review_violations": true, "can_view_logs": true, "can_export_csv": false, "can_manage_limits": false, "can_view_audit": false}'::jsonb
),
(
  '62ba1e51-4d4d-4429-a2e1-947a4fe18b68'::uuid,
  'sulimanawaad@yahoo.com',
  'Dr. Suliman Abu Awaad / د. سليمان أبو عواد',
  '07 9649 1159',
  'SUB_ADMIN',
  true,
  '{"can_approve_requests": true, "can_review_violations": true, "can_view_logs": true, "can_export_csv": false, "can_manage_limits": false, "can_view_audit": false}'::jsonb
)
on conflict (auth_user_id)
do update set
  email = excluded.email,
  full_name = excluded.full_name,
  phone_number = excluded.phone_number,
  role = 'SUB_ADMIN',
  is_active = true,
  permissions = excluded.permissions;

-- للتأكد بعد التشغيل:
select
  email,
  full_name,
  phone_number,
  role,
  is_active,
  permissions
from public.admin_profiles
where lower(email) in (
  'osamakan@yahoo.com',
  'hasanshehadeh@yahoo.com',
  'sulimanawaad@yahoo.com'
)
order by full_name;
