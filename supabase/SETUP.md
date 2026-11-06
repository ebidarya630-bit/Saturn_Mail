# اتصال backend برای Saturn Mailchat

این مخزن یک سایت استاتیک است و GitHub Pages به‌تنهایی سرور، پایگاه داده یا WebSocket اختصاصی اجرا نمی‌کند. این پوشه زیرساخت پیشنهادی Supabase را آماده می‌کند؛ تا وقتی پروژه و کلیدهای خودتان را تنظیم نکنید، برنامه همچنان در حالت محلی باقی می‌ماند.

## ۱) ساخت پروژه
1. در [Supabase](https://supabase.com/) یک پروژه بسازید.
2. از Project Settings → API، مقدار Project URL و کلید عمومی anon/publishable را بردارید.
3. فایل `supabase/config.example.js` را به `supabase/config.js` کپی کنید و دو مقدار را جایگزین کنید.
4. فایل `supabase/config.js` در Git نگذارید؛ در `.gitignore` مستثنا شده است.

## ۲) ساخت پایگاه داده
1. در Supabase → SQL Editor، محتوای `supabase/schema.sql` را اجرا کنید.
2. در Authentication → Providers، روش Email را فعال کنید و تنظیمات تأیید ایمیل و redirect URL را مطابق دامنه GitHub Pages تنظیم کنید.
3. در Authentication → URL Configuration، آدرس سایت را به Site URL و آدرس‌های مجاز Redirect URLs اضافه کنید.

## ۳) اتصال فایل تنظیمات به سایت
برای استفاده از کلاینت Supabase در صفحات، قبل از اسکریپت برنامه این دو فایل را بارگذاری کنید:
```html
<script src="supabase/config.js"></script>
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
```
نمونه تنظیمات فقط در `config.example.js` است. کلید service_role هرگز نباید به مرورگر یا GitHub Pages ارسال شود.

## ۴) قابلیت‌ها و وضعیت
- SQL این پوشه: پروفایل، گفتگو، اعضا، پیام، استوری، محصول، سفارش، RLS و فضای ذخیره‌سازی خصوصی.
- Realtime برای جدول پیام‌ها در publication فعال می‌شود.
- آپلودها در bucket خصوصی `saturn-media` قرار می‌گیرند؛ دسترسی باید با signed URL و سیاست‌های Storage انجام شود.
- این schema به‌تنهایی UI را به backend وصل نمی‌کند. کد رابط فعلی همچنان localStorage است تا زمانی که لایه client به‌صورت کامل به احراز هویت و جدول‌ها متصل شود.
- پرداخت واقعی، تأیید پرداخت سمت سرور، تماس صوتی/تصویری (WebRTC و TURN)، push notification، تعدیل محتوا و پنل مدیریت امن به سرویس/سرور جداگانه و تست نیاز دارند.

## امنیت
- هرگز service_role، رمز دیتابیس، کلید درگاه پرداخت یا کد مدیریتی را در فایل‌های عمومی قرار ندهید.
- RLS را خاموش نکنید.
- برای سفارش‌ها، تغییر وضعیت paid فقط باید از webhook تأییدشده در سرور مورداعتماد انجام شود.
- محدودیت نرخ، گزارش سوءاستفاده، حذف حساب و سیاست حریم خصوصی پیش از عرضه عمومی لازم‌اند.
