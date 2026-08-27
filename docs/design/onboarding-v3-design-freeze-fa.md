# LifeMate Onboarding Design V3

## Design Freeze Candidate

این سند refinement مستقیم V2 و منبع مرجع پیاده‌سازی V3 است. اسکلت بدون اسکرول، CTA ثابت، یک تصمیم اصلی در هر صفحه، معماری تم‌های semantic و شخصیت‌های WellMate/Women Health/CareMate باید حفظ شوند. جزئیات بصری می‌توانند هنگام پیاده‌سازی برای هماهنگی با کد و UI واقعی اپ حرفه‌ای‌تر شوند، اما قراردادهای UX/data/privacy این سند نباید بدون تصمیم محصول تغییر کنند.

## تصمیم‌های نهایی معماری

- ثبت‌نام canonical: هویت → تأیید → تشخیص حساب موجود/جدید.
- کاربر موجود: بازیابی session/profile → آخرین یا Mate پیش‌فرض → Home؛ onboarding تکرار نمی‌شود مگر داده‌ای واقعاً ناقص باشد.
- کاربر جدید: نام نمایشی → هدف استفاده → ورود محصول.
- سال تولد از signup حذف شده و فقط در context مرتبط، با «فعلاً رد کردن» درخواست می‌شود.
- «هر دو»: WellMate اول فعال می‌شود؛ اتصال CareMate پیشنهاد اختیاری است و onboarding دوم اجباری نیست.
- Women Health فقط با فعال‌سازی صریح Period Calendar شروع می‌شود؛ بخشی از account onboarding نیست.
- اعلان فقط پس از ایجاد اولین reminder و توضیح ارزش درخواست می‌شود؛ سپس dialog بومی سیستم باز می‌شود.
- رابطه در CareMate فقط hint شخصی‌سازی است، نه permission.
- تمام permissionها server-authoritative هستند. UI فقط وضعیت تأییدشدهٔ سرور را نمایش می‌دهد.
- scope باروری مستقل، حساس و پیش‌فرض خاموش است و از هیچ scope یا رابطه‌ای ارث نمی‌برد.

## اسکلت ثابت موبایل

Viewport مرجع: `390 × 844` پیکسل؛ پیاده‌سازی Flutter باید constraint-based باشد و این مختصات را hardcode نکند.

| ناحیه | اندازه / رفتار |
|---|---|
| Status safe area | 24 px مرجع |
| Header | 64 px مرجع؛ back و title مطابق RTL/pattern پلتفرم |
| Progress | ارتفاع 4؛ پیشروی RTL از راست به چپ |
| Content gutter | 24 px دو طرف |
| Main content | flexible؛ بدون scroll در حالت عادی |
| CTA | عرض کامل داخل gutter، ارتفاع 56، radius 18 |
| Bottom safe area | 24–32 px مرجع |
| Keyboard adaptation | CTA بالای IME؛ header و ورودی فعال حفظ می‌شوند؛ صفحه به فرم بلند تبدیل نمی‌شود |

## Design Tokens V3

### فاصله، اندازه و elevation

| Token | مقدار | کاربرد |
|---|---:|---|
| `space.1` | 4 | micro gap |
| `space.2` | 8 | icon/text |
| `space.3` | 12 | compact content |
| `space.4` | 16 | intra-card |
| `space.5` | 20 | related sections |
| `space.6` | 24 | screen gutter / section |
| `space.8` | 32 | major separation |
| `space.10` | 40 | hero-to-question |
| `radius.control` | 18 | input, CTA, segmented |
| `radius.card` | 20–24 | option/scope cards |
| `radius.hero` | 28–32 | calendar, large surface |
| `size.cta` | 56 | primary/secondary button |
| `size.input` | 58 | text field |
| `size.touch` | حداقل 48 | همهٔ اهداف لمسی |
| `size.icon.sm/md/lg` | 20 / 24 / 32 | semantic icons |
| `card.gap` | 12–14 | فاصله کارت‌های هم‌سطح |
| `progress.height` | 4 | progress خطی |
| `elevation.0` | بدون سایه | سطح پایه |
| `elevation.1` | `0 6 20 / 6%` | فقط modal/OS guidance؛ در mockupهای عادی border ترجیح دارد |

### تایپوگرافی فارسی

فونت نهایی باید با فونت واقعی محصول هماهنگ باشد، ولی metrics تقریبی V3 حفظ شود.

| Style | Size / line height | Weight |
|---|---|---:|
| Display compact | 26 / 36 | 850–900 |
| Question | 22 / 31 | 850 |
| Card title | 15–16 / 24 | 800–850 |
| Body | 13.5–14 / 23 | 500–600 |
| Label | 12.5–13 / 20 | 700–750 |
| Caption | 12 / 18 | 500–650 |
| CTA | 16 / 24 | 850 |

متن اصلی از 13.5px کوچک‌تر نشود. Captionهای 12px فقط برای اطلاعات کم‌اهمیت و با contrast حداقل AA.

### رنگ‌های semantic

| Semantic token | LifeMate Shared | WellMate | Women Health | CareMate |
|---|---|---|---|---|
| `color.bg` | `#FAF7F2` | `#F3F8F5` | `#FFF9F4` | `#F3F7FC` |
| `color.surface` | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` |
| `color.surfaceAlt` | `#F2ECE5` | `#E8F4ED` | `#F6EEFA` | `#E6EFFA` |
| `color.ink` | `#25232A` | `#1F302A` | `#3D3542` | `#263754` |
| `color.muted` | `#69636D` | `#617169` | `#756B77` | `#5F7088` |
| `color.primary` | `#51475A` | `#12835F` | `#C83B60` | `#3272B7` |
| `color.secondary` | `#B98B64` | `#62B996` | `#8765B4` | `#73A9E4` |
| `color.soft` | `#EEE8F0` | `#DFF2E9` | `#FCE5EC` | `#E1EDFA` |
| `color.border` | `#DED6CF` | `#CFE2D7` | `#EAD7E2` | `#CCDDEF` |
| `color.success` | `#237A5A` | `#12835F` | `#387E72` | `#237A6A` |
| `color.error` | `#B4473F` | `#B4473F` | `#B4473F` | `#B4473F` |

Shared warm-neutral است؛ WellMate سبز/نعنایی؛ Women Health باید واقعاً pink + lilac + cream باشد نه pink-only؛ CareMate آبی/sky.

## قرارداد کامپوننت‌ها

- `OnboardingScaffold`: safe area، gutter 24، no-scroll، CTA slot ثابت، keyboard mode جدا.
- `Header`: back target حداقل 48×48 و semantic «بازگشت».
- `Progress`: جهت شروع در RTL از راست؛ label مرحله مستقل از track.
- `QuestionHeader`: حداکثر 2–3 خط، حداقل 22px.
- `OptionCard`: ارتفاع حدود 72–88، کل کارت clickable، border + surface + check برای selection؛ اتکا نکردن صرف به رنگ.
- `PrimaryCTA`: 56px؛ loading و disabled بدون تغییر layout.
- `SecondaryCTA`: touch target 48px؛ متن حداقل 14px.
- `TextInput`: ارتفاع 58؛ error با رنگ + متن، نه فقط border.
- `OTPInput`: cellهای مستقل با ترتیب logical و LTR isolation.
- `WheelPicker`: سه مقدار آشکار، selected band، fade عمقی و affordance حرکت.
- `DatePicker`: جلالی، weekday فارسی، target مناسب، انتخاب با contrast و shape.
- `ConsentScopeCard`: icon + scope + دلیل/اثر + toggle مستقل؛ sensitive badge جدا.
- `PermissionPrompt`: pre-permission ارزش‌محور قبل از dialog سیستم.
- `Empty/Error/Success`: همان skeleton و recovery روشن.

## قواعد RTL

- پاراگراف فارسی راست‌چین؛ نام محصولات Latin با directional isolate.
- شماره موبایل، OTP، ایمیل و ساعت LTR-isolated، ولی label/context فارسی RTL.
- OTP mirror نشود و ترتیب رقم‌ها منطقی بماند.
- تاریخ جلالی و عدد فارسی در UI؛ ذخیره‌سازی backend مستقل از نمایش.
- progress در RTL از راست به چپ پر شود.
- واحدهایی مثل «۲۸ روز» یک run غیرقابل‌شکست باشند.

## Accessibility / Real-device

- touch target حداقل 48dp.
- Question حدود 22px و Body حداقل 13.5px.
- selected/unselected حداقل با border + surface + icon/check متمایز شوند.
- error icon/text داشته باشد و فقط رنگ نباشد.
- normal onboarding screens scroll نخورند؛ keyboard mode layout مخصوص داشته باشد.
- تست روی viewport مرجع و حداقل یک ارتفاع کوچک‌تر انجام شود.

## Privacy model

CareMate consent باید روشن کند: چه چیزی، با چه کسی، برای چه هدفی و وضعیت ON/OFF. pending هیچ داده سلامت افشا نکند. accepted فقط scopeهای server-confirmed را نشان دهد. revoked output محافظت‌شده را فوراً متوقف کند.

اطلاعات باروری مستقل، sensitive و default OFF است و relationship یا scope دیگر آن را فعال نمی‌کند.

## Freeze checklist

- [x] signup حداقلی و existing-user bypass
- [x] both path بدون onboarding دوگانه
- [x] birth year progressive profiling
- [x] Women Health فقط feature activation
- [x] notification pre-permission contextual
- [x] CareMate invalid/expired/pending/accepted/revoked
- [x] CTA ثابت و normal no-scroll
- [x] font sizes و touch targetهای واقعی
- [x] RTL، OTP، mixed Latin، Jalali
- [x] tokenها و component matrix مشترک

## Engineering note

Mockupها مرجع design intent هستند، نه دستور pixel-perfect. هنگام پیاده‌سازی باید از componentهای واقعی اپ و constraintهای Flutter برای خروجی حرفه‌ای‌تر استفاده شود، ولی business/data/privacy semantics بالا canonical هستند.
