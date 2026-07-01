# Emergency Room Parking — Employee Private Parking Access System

**Concept & Programming:** Dr. Alaa Aqrabawi

نظام ويب بسيط وخاص لإدارة دخول كراج الموظفين باستخدام:

- HTML
- CSS
- JavaScript
- Supabase
- Netlify
- GitHub

بدون:

- Next.js
- React
- npm
- build command
- Terminal
- ملفات معقدة

---

## 1. فكرة النظام

النظام مكوّن من أربع صفحات رئيسية:

| الملف | الوظيفة |
|---|---|
| `index.html` | شاشة الحارس + QR متغير كل 30 ثانية + بلاغ مخالفة بصورة |
| `verify.html` | صفحة تسجيل الموظف أو التحقق من الدخول |
| `login.html` | تسجيل دخول الإدارة |
| `admin_dashboard.html` | لوحة الإدارة الكاملة |
| `schema.sql` | تجهيز قاعدة بيانات Supabase |
| `netlify.toml` | إعداد Netlify |

---

## 2. طريقة العمل

الموظفون يحصلون على رابط التسجيل عبر واتساب.

الموظف يفتح الرابط ويعبئ:

- الاسم الكامل
- رقم الموظف
- رقم الهاتف
- القسم / الاختصاص

الطلب يظهر في لوحة الأدمن.

الحارس يفتح `index.html` على هاتفه، ويعرض QR للموظفين.

QR:

- يتغير كل 30 ثانية
- ينتهي بعد 30 ثانية
- ينتهي بعد أول استخدام
- يظهر نتيجة الدخول على شاشة الحارس

النتائج:

| النتيجة | المعنى | اللون |
|---|---|---|
| `ALLOWED` | مسموح بالدخول | أخضر |
| `DENIED` | غير مسموح | أحمر |
| `LIMITED` | مسموح جزئيًا | أصفر |
| `PENDING_FIRST_ENTRY` | دخول أول مرة بعد التسجيل | أصفر |

---

## 3. الدخول الأول بعد التسجيل

الموظف الجديد يحصل على دخول أول مرة فقط إذا:

- أدخل الاسم
- أدخل رقم الموظف
- أدخل رقم الهاتف
- أدخل القسم / الاختصاص
- فتح الصفحة من QR صالح وغير مستخدم

هذا الدخول:

- لا يجعله Approved نهائيًا
- يظهر في لوحة الإدارة بوضوح
- يستخدم مرة واحدة فقط
- بعده يبقى الطلب `PENDING`
- لا يستطيع الدخول مرة ثانية إلا بعد موافقة الإدارة

---

## 4. خطوات Supabase

### الخطوة 1 — إنشاء مشروع Supabase

ادخلي إلى Supabase وأنشئي مشروعًا جديدًا.

بعد إنشاء المشروع، ستحتاجين:

```txt
Project URL
Anon / Publishable Key
```

مهم جدًا:

```txt
لا تضعي service_role key في ملفات HTML أبدًا.
استخدمي فقط anon / publishable key.
```

---

### الخطوة 2 — تشغيل schema.sql

افتحي:

```txt
Supabase Dashboard → SQL Editor → New Query
```

انسخي محتوى ملف:

```txt
schema.sql
```

ثم اضغطي:

```txt
Run
```

إذا ظهر تحذير عن Realtime أو publication موجود مسبقًا، غالبًا يمكن تجاهله إذا الجداول انعملت.

---

### الخطوة 3 — إنشاء مستخدم الإدارة

افتحي:

```txt
Authentication → Users
```

ثم أضيفي مستخدمًا جديدًا:

```txt
Email: الإيميل الذي ستدخلين به إلى لوحة الإدارة
Password: كلمة مرور قوية
Auto Confirm: مفعّل إذا ظهر الخيار
```

بعد إنشاء المستخدم:

1. افتحي المستخدم.
2. انسخي `User UID`.

---

### الخطوة 4 — إضافة Super Admin

بعد نسخ `User UID`، افتحي:

```txt
SQL Editor → New Query
```

وشغّلي هذا الكود بعد تبديل القيم:

```sql
insert into public.admin_profiles (
  auth_user_id,
  email,
  full_name,
  role,
  is_active
)
values (
  'PASTE_YOUR_AUTH_USER_UID_HERE',
  'PASTE_YOUR_AUTH_EMAIL_HERE',
  'Dr. Alaa Aqrabawi',
  'SUPER_ADMIN',
  true
)
on conflict (auth_user_id)
do update set
  email = excluded.email,
  full_name = excluded.full_name,
  role = 'SUPER_ADMIN',
  is_active = true;
```

مثال إذا كان اليوزر فعلًا هو:

```txt
Email: kisscrisis@list.ru
User UID: dfc76ed3-aa22-4c5d-98f4-a2f7235dbd69
```

استخدمي:

```sql
insert into public.admin_profiles (
  auth_user_id,
  email,
  full_name,
  role,
  is_active
)
values (
  'dfc76ed3-aa22-4c5d-98f4-a2f7235dbd69',
  'kisscrisis@list.ru',
  'Dr. Alaa Aqrabawi',
  'SUPER_ADMIN',
  true
)
on conflict (auth_user_id)
do update set
  email = excluded.email,
  full_name = excluded.full_name,
  role = 'SUPER_ADMIN',
  is_active = true;
```

للتأكد:

```sql
select *
from public.admin_profiles;
```

يجب أن يظهر:

```txt
role = SUPER_ADMIN
is_active = true
```

---

## 5. وضع قيم Supabase داخل الملفات

افتحي كل ملف من الملفات التالية:

```txt
index.html
verify.html
login.html
admin_dashboard.html
```

وابحثي عن:

```js
SUPABASE_URL: "https://hnsbsvwxxxysjnhgtinl.supabase.co",
SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imhuc2Jzdnd4eHh5c2puaGd0aW5sIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI4NTMwNjAsImV4cCI6MjA5ODQyOTA2MH0.QtzYlzjmoGNvjhJhxdGxEwUTKWm0WHGGKn2THSBOgAo",
```

بدّليها بالقيم الحقيقية من Supabase.

مثال:

```js
SUPABASE_URL: "https://xxxxxxxx.supabase.co",
SUPABASE_ANON_KEY: "eyJhbGciOi..."
```

في `index.html` و `verify.html` يوجد أيضًا:

```js
LIVE_SITE_URL: "https://garagey.netlify.app",
```

بعد نشر الموقع على Netlify، ضعي رابط الموقع النهائي مثل:

```js
LIVE_SITE_URL: "https://garagey.netlify.app",
```

قبل نشر Netlify يمكن تركها كما هي، وسيحاول الموقع استخدام الرابط الحالي تلقائيًا.

---

## 6. رفع المشروع على GitHub

ارفعي الملفات التالية إلى GitHub في نفس المكان:

```txt
index.html
verify.html
login.html
admin_dashboard.html
schema.sql
README.md
netlify.toml
```

لا تضعيها داخل مجلدات معقدة.

---

## 7. إعداد Netlify

من Netlify:

```txt
Add new site → Import from Git
```

اختاري المستودع من GitHub.

الإعدادات:

```txt
Branch: main
Build command: اتركيه فارغًا
Publish directory: .
Functions directory: اتركيه كما هو أو فارغًا
```

إذا الملفات داخل مجلد وليس في root، ضعي اسم المجلد في Base directory.

لكن الأفضل لهذا المشروع:

```txt
الملفات تكون في root
Publish directory = .
Build command = empty
```

---

## 8. الصفحات بعد النشر

بعد نشر الموقع:

| الصفحة | الرابط |
|---|---|
| شاشة الحارس | `/index.html` |
| تسجيل الموظفين | `/verify.html` |
| دخول الإدارة | `/login.html` |
| لوحة الإدارة | `/admin_dashboard.html` |

مثال:

```txt
https://garagey.netlify.app/index.html
https://garagey.netlify.app/verify.html
https://garagey.netlify.app/login.html
https://garagey.netlify.app/admin_dashboard.html
```

---

## 9. طريقة الاستخدام اليومية

### الحارس

يفتح:

```txt
index.html
```

ثم يعرض QR للموظف.

الحارس لا يحتاج إلى بحث أو كتابة.

إذا حدثت مخالفة:

1. يضغط تسجيل مخالفة.
2. يلتقط صورة.
3. يضيف رقم الموظف أو ملاحظة إذا عرف.
4. يرسل البلاغ.

---

### الموظف

يفتح رابط QR أو رابط التسجيل.

إذا جديد:

```txt
يعبئ نموذج التسجيل
```

إذا مسجل:

```txt
يدخل رقم الموظف + رقم الهاتف
```

---

### الأدمن

يفتح:

```txt
login.html
```

يسجل الدخول بنفس إيميل وكلمة مرور Supabase Auth.

ثم ينتقل إلى:

```txt
admin_dashboard.html
```

---

## 10. صلاحيات الإدارة

### SUPER_ADMIN

يستطيع:

- الموافقة والرفض
- إضافة مشرفين
- تعطيل مشرفين
- تعديل حدود الاختصاصات
- رؤية البلاغات
- رؤية الإحصائيات
- تصدير CSV
- رؤية Audit

### SUB_ADMIN

يستطيع:

- الموافقة والرفض
- رؤية البلاغات
- رؤية الإحصائيات
- رؤية سجلات الدخول

ولا يستطيع:

- إضافة مشرفين
- تغيير حدود الاختصاصات
- رفع نفسه إلى Super Admin

---

## 11. ملاحظات أمان مهمة

- لا تستخدمي `service_role` داخل أي HTML.
- لا تنشري Database password.
- استخدمي فقط anon / publishable key.
- الصلاحيات محمية بـ RLS و RPC.
- شاشة الحارس بسيطة ومفتوحة وظيفيًا، لذلك لا تشاركي رابطها إلا مع الحارس أو الفريق المسؤول.
- لنسخة أقوى أمنيًا لاحقًا يمكن إضافة تسجيل دخول للحارس أو Edge Function.

---

## 12. إذا ظهرت شاشة بيضاء

المفروض لا تظهر شاشة بيضاء.

إذا ظهر خطأ، افحصي:

1. هل شغّلتِ `schema.sql`؟
2. هل وضعتِ `SUPABASE_URL`؟
3. هل وضعتِ `SUPABASE_ANON_KEY`؟
4. هل أضفتِ Super Admin في `admin_profiles`؟
5. هل دخلتِ من `login.html` بنفس إيميل Auth؟
6. هل Netlify Publish directory = `.`؟

---

## 13. الملفات المطلوبة نهائيًا

```txt
index.html
verify.html
login.html
admin_dashboard.html
schema.sql
README.md
netlify.toml
```



---

## القيم التي تم إدخالها في هذه النسخة

```txt
APP_NAME = Emergency Room Parking
LIVE_SITE_URL = https://garagey.netlify.app
SUPABASE_URL = https://hnsbsvwxxxysjnhgtinl.supabase.co
SUPABASE_ANON_KEY = تم إدخاله داخل ملفات HTML
```

ملاحظة: رابط Supabase الذي أعطيته كان يحتوي `/rest/v1/`، وتم تصحيحه داخل الملفات إلى رابط المشروع الأساسي:

```txt
https://hnsbsvwxxxysjnhgtinl.supabase.co
```


---

## V1.1 — معلومات المستشفى والشعار والصلاحيات

تم اعتماد:

```txt
App Name: Emergency Room Parking
Hospital Arabic: مستشفى الإسعاف والطوارئ / البشير
Hospital English: Al-Bashir Hospital Emergency Department
Logo file: logo.jpeg
Favicon file: favicon.svg
```

### الاختصاصات النهائية

```txt
- جراحة عامة: Max 7 per day
- باطني: Max 7 per day
- ENT: Max 7 per day
- نسائية: Max 7 per day
- مسالك بولية: Max 7 per day
- عيون: Max 7 per day
- جراحة دماغ وأعصاب: Max 7 per day
- تخدير: Max 7 per day
- طب عام: Max 7 per day
- جراحة أوعية دموية: Max 7 per day
- أخرى: Max 7 per day
```

### المشرفون المرشحون للإضافة

تم تزويد الإيميلات والـ UID، ويمكن إضافتهم مباشرة بتشغيل:

```txt
setup_sub_admins.sql
```

```txt
1) Dr. Hasan Shehadeh / د. حسن شحاده
Email: hasanshehadeh@yahoo.com
UID: 86506d29-d00f-4c8d-b355-b04f84845d18
Phone: 07 9130 4742

2) Dr. Suliman Abu Awaad / د. سليمان أبو عواد
Email: sulimanawaad@yahoo.com
UID: 62ba1e51-4d4d-4429-a2e1-947a4fe18b68
Phone: 07 9649 1159

3) Dr. Osama Kanan / د. أسامه كنعان
Email: osamakan@yahoo.com
UID: fa07528b-7173-4e8f-8aae-103a8379cd17
Phone: 07 9553 4663
```

الصلاحيات الافتراضية لهم بعد تشغيل الملف:
- موافقة / رفض طلبات التسجيل
- مراجعة بلاغات الحارس
- رؤية سجلات الدخول والإحصائيات

وتبقى الصلاحيات التالية غير مفعّلة افتراضيًا إلا إذا عدلتيها من صفحة Admins:
- تصدير CSV
- تعديل حدود الاختصاصات اليومية
- رؤية Audit

### صلاحيات المشرفين من صفحة Admins

من صفحة `Admins` يستطيع `SUPER_ADMIN`:

- إضافة مشرف
- تعديل مشرف
- تعطيل مشرف
- حذف مشرف من لوحة الإدارة
- تحديد رقم الهاتف
- تحديد الدور
- تحديد المهام التالية:
  - موافقة / رفض طلبات التسجيل
  - مراجعة بلاغات الحارس
  - رؤية سجلات الدخول والإحصائيات
  - تصدير CSV
  - تعديل حدود الاختصاصات اليومية
  - رؤية Audit

ملاحظة: حذف المشرف من لوحة الإدارة لا يحذف مستخدم Supabase Auth نفسه.

---

## V1.3 — قاعدة QR لكل دخول

تم تثبيت القاعدة التالية داخل الواجهات والتعليمات:

```txt
كل دخول للكراج يجب أن يتم عبر QR مباشر من شاشة الحارس.
هذا ينطبق على:
- الموظفين
- SUB_ADMIN
- SUPER_ADMIN
- Dr. Alaa Aqrabawi
```

صلاحية الإدارة لا تعني دخول الكراج تلقائيًا.

أي أدمن يريد دخول الكراج يجب أن يكون أيضًا موجودًا في `employee_registrations` وحالته `APPROVED`.

الـ QR:
- يتغير كل 30 ثانية
- ينتهي بعد 30 ثانية
- يستخدم مرة واحدة فقط
- تصوير الشاشة لا يعطي صلاحية لاحقة للدخول

---

## V1.4 — صورة واجهة التطبيق

تم اعتماد الصورة الثانية كواجهة مرئية للتطبيق وتمت تسميتها:

```txt
hero.jpeg
```

يجب رفع الملف مع باقي الملفات في نفس مكان صفحات HTML:

```txt
hero.jpeg
logo.jpeg
favicon.svg
index.html
verify.html
login.html
admin_dashboard.html
```

الاستخدام:
- `hero.jpeg` = صورة واجهة / Banner للتطبيق
- `logo.jpeg` = شعار المستشفى داخل البطاقات
- `favicon.svg` = أيقونة المتصفح / الموقع
