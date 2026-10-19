# Mango APK Studio

تطبيق Flutter لبناء تطبيقات Android من ملفات مشاريع ZIP، مع تخصيص الاسم والأيقونة واسم الحزمة والإصدار، ثم البناء عبر GitHub Actions. تطوير: MSK Organization.

## حالة المشروع (بدون مبالغة)

- كُتب الكود كاملاً (Flutter + Backend + Workflow + اختبارات + وثائق)، لكنه **لم يُشغَّل بعد**: لم يُنفذ `flutter analyze` ولا `flutter test` ولا `npm test` ولا أي بناء فعلي، لأن بيئة الإنشاء لا تحتوي Flutter SDK ولا اتصال شبكة. نفّذ الأوامر أدناه عندك أولاً وأصلح أي ملاحظات.
- لم يُنشأ APK، ولم يُرفع مستودع، ولم يُربط حساب GitHub. كل ذلك يحتاج إعدادك اليدوي (انظر الخطوات).
- مجلد `android/` مضمَّن (كُتب يدويًا بقالب Flutter القياسي ولم يُختبر): إصدارات AGP 8.11.1 وKotlin 2.2.20 وGradle 8.14.3 تخمين مبني على قوالب Flutter المعروفة لي، وقد تحتاج رفعًا لتناسب نسخة Flutter عندك. الحل الأضمن: `flutter create . --platforms=android` ثم احتفظ بالناتج.
- `.github/workflows/build-apk.yml` يبني تطبيق Mango نفسه على ريبو التطبيق. أما مجلد `build-repo/` فمحتواه يُنسخ إلى مستودع البناء الخاص المنفصل الذي يستخدمه الـ Backend (لا ترفعه داخل ريبو التطبيق).

## الأنواع المدعومة فعلياً

| النوع | الحالة |
|---|---|
| Flutter | مسار بناء كامل (Debug وRelease، الـ Release موقّع بمفتاح debug الافتراضي ولا يصلح للنشر في Play) |
| Android أصلي (Gradle) | Debug فقط، ويجب أن يتضمن `gradlew` |
| HTML/CSS/JS | **غير مدعوم**: لم يُنفذ مسار WebView/Capacitor، والتطبيق يرفض هذه المشاريع بسبب واضح |

## تشغيل تطبيق Flutter

```bash
flutter create . --platforms=android --org com.msk --project-name mango_apk_studio
# أضف الصلاحية في android/app/src/main/AndroidManifest.xml (قبل <application>):
#   <uses-permission android:name="android.permission.INTERNET"/>
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=BACKEND_URL=https://api.your-domain.example
flutter build apk --debug --dart-define=BACKEND_URL=https://api.your-domain.example
```

## إعداد GitHub

1. **OAuth App**: GitHub ← Settings ← Developer settings ← OAuth Apps ← New. فعّل **Device Flow**. انسخ `Client ID` فقط (لا حاجة لـ Client Secret).
2. **مستودع البناء**: أنشئ مستودعاً **خاصاً** مخصصاً للبناء، وانسخ إليه محتويات مجلد `build-repo/` (`.github/workflows/build-android.yml` و`.github/scripts/prepare.py`). لا تضع فيه أي Secrets.
3. **Token للـ Backend**: Fine-grained PAT محدود بمستودع البناء فقط: `Actions: Read and write` و`Contents: Read`. يوضع في `BUILD_REPO_TOKEN`.
4. صلاحية OAuth المطلوبة هي `read:user` فقط (لتعريف المستخدم). عمليات البناء لا تستخدم توكن المستخدم أبداً.

## تشغيل Backend

```bash
cd backend
cp .env.example .env     # املأ القيم
npm install
npm test
node --env-file=.env src/server.js
```

انشره خلف HTTPS (Render / Fly.io / VPS مع Caddy أو Nginx). المسارات المنفذة:

```
POST /api/session
POST /api/auth/github/device/start
GET  /api/auth/github/device/status
POST /api/auth/github/disconnect
POST /api/builds            GET /api/builds
GET  /api/builds/:jobId     GET /api/builds/:jobId/logs
POST /api/builds/:jobId/retry
POST /api/builds/:jobId/download-link   GET /api/builds/:jobId/download
```

الأسرار المطلوبة: `GITHUB_CLIENT_ID`, `BUILD_REPO`, `BUILD_REPO_TOKEN`, `ENCRYPTION_KEY`, `SIGNING_SECRET` (انظر `.env.example`).

## تدفق البناء

التطبيق ← Backend (فحص ZIP وحدود وتحقق) ← طابور (بناء واحد في المرة افتراضياً) ← `workflow_dispatch` ← runner نظيف لكل Job ← Artifact ← رابط تنزيل موقّع قصير العمر (5 دقائق افتراضياً) خاص بالمهمة وصاحبها.

- رابط المصدر الذي يحمّله الـ runner موقّع وصالح 15 دقيقة. قيم المدخلات تظهر في واجهة Actions، لذا اجعل مستودع البناء خاصاً.
- لا تتوفر نسبة تقدم حقيقية من GitHub Actions، لذلك تُعرض أسماء المراحل فقط.
- السجل يحتوي أحداث الـ Backend والخطوة الفاشلة. نص سجل Actions الكامل يُراجع من GitHub.

## تغيير اسم الحزمة

يُعدَّل `applicationId` فقط، ويبقى `namespace` كما هو حتى لا ينكسر كود Kotlin/Java وملف Manifest. إذا كان المشروع يستخدم Firebase (`google-services.json`) أو Deep Links أو Signing مربوطاً بالحزمة فقد تتعطل هذه التكاملات: راجعها يدوياً.

## الاحتفاظ والحدود

- الاحتفاظ بالملفات الناتجة والمؤقتة: 24 ساعة افتراضياً (`RETENTION_HOURS`) ثم تُحذف تلقائياً.
- حد ZIP: 200MB في الخادم (وقابل للتعديل في التطبيق حتى 500MB من جهة الواجهة فقط، والخادم هو المرجع).
- حدود GitHub Actions المجانية تنطبق (دقائق شهرية للمستودعات الخاصة، وحدود Artifacts). راجع الحدود الحالية في وثائق GitHub.
- حد 10 عمليات بناء في الساعة لكل مستخدم.

## ملاحظات أمنية سريعة

- لا توجد أسرار في كود Flutter. توكن GitHub للمستخدم يُحفظ في الخادم مشفراً (AES-256-GCM) ولا يعود للتطبيق.
- مصادقة التطبيق جلسة عشوائية لكل تثبيت (بدون حساب). للإنتاج الكبير أضف Play Integrity أو حسابات مستخدمين.
- التفاصيل في `SECURITY.md`.
