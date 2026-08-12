import 'runtime_locale.dart';

class LifeMateHealthFact {
  const LifeMateHealthFact({required this.category, required this.text});

  final String category;
  final String text;
}

/// Short, general-purpose wellbeing prompts shown only while account bootstrap
/// is genuinely running. They are intentionally non-diagnostic and do not
/// replace advice from a clinician who knows the user's medical history.
final List<LifeMateHealthFact> lifeMateHealthFacts = [
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'آب و بدن', en: "water and body"),
      en: "water and body",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'یک لیوان آب کنار محل کار یا استراحت، یادآوری نوشیدن آب را ساده‌تر می‌کند.',
        en: "A glass of water next to work or rest makes it easier to remember to drink water.",
      ),
      en: "A glass of water next to work or rest makes it easier to remember to drink water.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'آب و بدن', en: "water and body"),
      en: "water and body",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'رنگ بسیار تیره ادرار می‌تواند نشانه نیاز به مایعات بیشتر باشد؛ شرایط پزشکی خاص را با پزشک بررسی کنید.',
        en: "A very dark color of urine can be a sign of the need for more fluids; Check with your doctor for specific medical conditions.",
      ),
      en: "A very dark color of urine can be a sign of the need for more fluids; Check with your doctor for specific medical conditions.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'آب و بدن', en: "water and body"),
      en: "water and body",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'در هوای گرم و هنگام فعالیت بدنی، نیاز بدن به مایعات معمولاً بیشتر می‌شود.',
        en: "In hot weather and during physical activity, the body's need for fluids usually increases.",
      ),
      en: "In hot weather and during physical activity, the body's need for fluids usually increases.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'آب و بدن', en: "water and body"),
      en: "water and body",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'میوه‌ها و سبزی‌ها علاوه بر مواد مغذی، بخشی از آب روزانه بدن را هم تأمین می‌کنند.',
        en: "In addition to nutrients, fruits and vegetables also provide part of the body's daily water.",
      ),
      en: "In addition to nutrients, fruits and vegetables also provide part of the body's daily water.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'آب و بدن', en: "water and body"),
      en: "water and body",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'نوشیدنی‌های بسیار شیرین را می‌توان با آب، دوغ کم‌نمک یا نوشیدنی بدون شکر جایگزین کرد.',
        en: "Very sweet drinks can be replaced with water, low-salt butter or sugar-free drinks.",
      ),
      en: "Very sweet drinks can be replaced with water, low-salt butter or sugar-free drinks.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'خواب', en: "sleep"),
      en: "sleep",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'بیدارشدن در ساعت تقریباً ثابت، به منظم‌شدن ساعت زیستی بدن کمک می‌کند.',
        en: "Waking up at almost the same time helps regulate the biological clock of the body.",
      ),
      en: "Waking up at almost the same time helps regulate the biological clock of the body.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'خواب', en: "sleep"),
      en: "sleep",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'نور زیاد صفحه‌نمایش نزدیک زمان خواب می‌تواند به خواب‌رفتن را دشوارتر کند.',
        en: "Too much screen light near bedtime can make it harder to fall asleep.",
      ),
      en: "Too much screen light near bedtime can make it harder to fall asleep.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'خواب', en: "sleep"),
      en: "sleep",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'اتاق نسبتاً خنک، تاریک و آرام برای بسیاری از افراد خواب راحت‌تری ایجاد می‌کند.',
        en: "A relatively cool, dark, and quiet room makes for a more comfortable sleep for many people.",
      ),
      en: "A relatively cool, dark, and quiet room makes for a more comfortable sleep for many people.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'خواب', en: "sleep"),
      en: "sleep",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'کافئین عصرگاهی در بعضی افراد کیفیت خواب شبانه را کاهش می‌دهد.',
        en: "Caffeine in the evening reduces the quality of night sleep in some people.",
      ),
      en: "Caffeine in the evening reduces the quality of night sleep in some people.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'خواب', en: "sleep"),
      en: "sleep",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'یک روتین کوتاه مثل مسواک، نور کم و چند نفس آرام، به مغز پیام نزدیک‌شدن زمان خواب می‌دهد.',
        en: "A short routine such as brushing, low light and a few slow breaths will send a message to the brain that bedtime is approaching.",
      ),
      en: "A short routine such as brushing, low light and a few slow breaths will send a message to the brain that bedtime is approaching.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'خواب', en: "sleep"),
      en: "sleep",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'چرت طولانی یا دیرهنگام ممکن است خواب شب را به‌هم بزند؛ واکنش بدن خودتان را بررسی کنید.',
        en: "A long or late nap may disrupt the night's sleep; Check your body's reaction.",
      ),
      en: "A long or late nap may disrupt the night's sleep; Check your body's reaction.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'خواب', en: "sleep"),
      en: "sleep",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'اگر خرخر شدید، قطع تنفس یا خواب‌آلودگی روزانه مداوم دارید، ارزیابی پزشکی مهم است.',
        en: "If you have severe snoring, shortness of breath, or persistent daytime sleepiness, a medical evaluation is important.",
      ),
      en: "If you have severe snoring, shortness of breath, or persistent daytime sleepiness, a medical evaluation is important.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'خواب', en: "sleep"),
      en: "sleep",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'ثبت زمان خواب و بیداری برای چند روز می‌تواند الگوی واقعی خواب را روشن‌تر کند.',
        en: "Recording sleep and wake times for a few days can clarify the actual sleep pattern.",
      ),
      en: "Recording sleep and wake times for a few days can clarify the actual sleep pattern.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'خواب', en: "sleep"),
      en: "sleep",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'وعده بسیار سنگین درست پیش از خواب ممکن است باعث ناراحتی و اختلال خواب شود.',
        en: "A very heavy meal right before bed may cause discomfort and sleep disturbance.",
      ),
      en: "A very heavy meal right before bed may cause discomfort and sleep disturbance.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'خواب', en: "sleep"),
      en: "sleep",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'نور طبیعی صبحگاهی می‌تواند به تنظیم چرخه خواب و بیداری کمک کند.',
        en: "Natural light in the morning can help regulate the sleep-wake cycle.",
      ),
      en: "Natural light in the morning can help regulate the sleep-wake cycle.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تغذیه', en: "feeding"),
      en: "feeding",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'نیمی از بشقاب را می‌توان با سبزی‌ها و سالاد متنوع‌تر کرد.',
        en: "Half of the plate can be made more diverse with vegetables and salad.",
      ),
      en: "Half of the plate can be made more diverse with vegetables and salad.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تغذیه', en: "feeding"),
      en: "feeding",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'تنوع رنگ در میوه و سبزی معمولاً به معنی دریافت طیف متنوع‌تری از مواد مغذی است.',
        en: "Variety of colors in fruits and vegetables usually means getting a more diverse range of nutrients.",
      ),
      en: "Variety of colors in fruits and vegetables usually means getting a more diverse range of nutrients.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تغذیه', en: "feeding"),
      en: "feeding",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'حبوبات منبع خوب فیبر و پروتئین گیاهی هستند و می‌توانند چند وعده در هفته جای گوشت را بگیرند.',
        en: "Legumes are a good source of fiber and vegetable protein and can replace meat a few times a week.",
      ),
      en: "Legumes are a good source of fiber and vegetable protein and can replace meat a few times a week.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تغذیه', en: "feeding"),
      en: "feeding",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'غلات کامل معمولاً فیبر بیشتری از انواع کاملاً تصفیه‌شده دارند.',
        en: "Whole grains usually have more fiber than highly refined varieties.",
      ),
      en: "Whole grains usually have more fiber than highly refined varieties.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تغذیه', en: "feeding"),
      en: "feeding",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'آجیل و دانه‌ها مغذی‌اند، اما به دلیل انرژی بالا بهتر است مقدار مصرفشان متعادل باشد.',
        en: "Nuts and seeds are nutritious, but due to their high energy content, it is better to consume them in moderation.",
      ),
      en: "Nuts and seeds are nutritious, but due to their high energy content, it is better to consume them in moderation.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تغذیه', en: "feeding"),
      en: "feeding",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'خواندن برچسب محصول کمک می‌کند مقدار نمک، شکر افزوده و چربی اشباع را مقایسه کنید.',
        en: "Reading product labels will help you compare the amount of salt, added sugar, and saturated fat.",
      ),
      en: "Reading product labels will help you compare the amount of salt, added sugar, and saturated fat.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تغذیه', en: "feeding"),
      en: "feeding",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'آهسته‌تر غذاخوردن فرصت بیشتری برای درک سیری به بدن می‌دهد.',
        en: "Eating more slowly gives the body more time to sense fullness.",
      ),
      en: "Eating more slowly gives the body more time to sense fullness.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تغذیه', en: "feeding"),
      en: "feeding",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'برنامه‌ریزی یک میان‌وعده ساده مثل میوه، احتمال انتخاب خوراکی بسیار شیرین را کمتر می‌کند.',
        en: "Planning a simple snack like fruit makes it less likely that you will choose something too sweet.",
      ),
      en: "Planning a simple snack like fruit makes it less likely that you will choose something too sweet.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تغذیه', en: "feeding"),
      en: "feeding",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'ماهی، حبوبات، تخم‌مرغ و گوشت کم‌چرب می‌توانند منابع متنوع پروتئین باشند.',
        en: "Fish, legumes, eggs and lean meat can be varied sources of protein.",
      ),
      en: "Fish, legumes, eggs and lean meat can be varied sources of protein.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تغذیه', en: "feeding"),
      en: "feeding",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'روش‌هایی مثل بخارپز، تنوری و کبابی معمولاً به روغن کمتری از سرخ‌کردن عمیق نیاز دارند.',
        en: "Methods such as steaming, broiling, and grilling generally require less oil than deep frying.",
      ),
      en: "Methods such as steaming, broiling, and grilling generally require less oil than deep frying.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تغذیه', en: "feeding"),
      en: "feeding",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'نمکدان را از سفره دور کنید و برای طعم از سبزی‌های معطر و ادویه‌های مناسب استفاده کنید.',
        en: "Remove the salt shaker from the table and use aromatic herbs and spices for taste.",
      ),
      en: "Remove the salt shaker from the table and use aromatic herbs and spices for taste.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تغذیه', en: "feeding"),
      en: "feeding",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'ماست ساده همراه میوه می‌تواند جایگزین کم‌شکرتری برای بعضی دسرها باشد.',
        en: "Plain yogurt with fruit can be a less sugary alternative to some desserts.",
      ),
      en: "Plain yogurt with fruit can be a less sugary alternative to some desserts.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تغذیه', en: "feeding"),
      en: "feeding",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'خرید با فهرست از قبل نوشته‌شده، انتخاب‌های برنامه‌ریزی‌نشده را کمتر می‌کند.',
        en: "Shopping with a pre-written list minimizes unplanned choices.",
      ),
      en: "Shopping with a pre-written list minimizes unplanned choices.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تغذیه', en: "feeding"),
      en: "feeding",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'حجم مناسب غذا برای هر فرد متفاوت است؛ به گرسنگی، سیری و شرایط پزشکی توجه کنید.',
        en: "The right amount of food is different for each person; Pay attention to hunger, fullness, and medical conditions.",
      ),
      en: "The right amount of food is different for each person; Pay attention to hunger, fullness, and medical conditions.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'تغذیه', en: "feeding"),
      en: "feeding",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'شستن دست‌ها و نگهداری درست مواد غذایی، بخش مهمی از سلامت تغذیه است.',
        en: "Washing hands and storing food properly is an important part of healthy nutrition.",
      ),
      en: "Washing hands and storing food properly is an important part of healthy nutrition.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'حرکت', en: "movement"),
      en: "movement",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'چند دقیقه راه‌رفتن در طول روز هم از بی‌تحرکی کامل بهتر است.',
        en: "A few minutes of walking during the day is better than complete inactivity.",
      ),
      en: "A few minutes of walking during the day is better than complete inactivity.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'حرکت', en: "movement"),
      en: "movement",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'فعالیتی را انتخاب کنید که از آن لذت می‌برید؛ تداوم از شدت مقطعی مهم‌تر است.',
        en: "Choose an activity that you enjoy; Continuity is more important than intermittent intensity.",
      ),
      en: "Choose an activity that you enjoy; Continuity is more important than intermittent intensity.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'حرکت', en: "movement"),
      en: "movement",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'گرم‌کردن تدریجی پیش از فعالیت و سردکردن پس از آن، به سازگاری بدن کمک می‌کند.',
        en: "Gradual warming up before activity and cooling down afterwards helps the body adapt.",
      ),
      en: "Gradual warming up before activity and cooling down afterwards helps the body adapt.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'حرکت', en: "movement"),
      en: "movement",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'تمرین قدرتی متناسب با توان فرد می‌تواند به حفظ عضله و عملکرد روزمره کمک کند.',
        en: "Strength training according to a person's strength can help maintain muscle and daily performance.",
      ),
      en: "Strength training according to a person's strength can help maintain muscle and daily performance.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'حرکت', en: "movement"),
      en: "movement",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'تمرین تعادل برای سالمندان می‌تواند بخشی از برنامه پیشگیری از زمین‌خوردن باشد.',
        en: "Balance training for seniors can be part of a fall prevention program.",
      ),
      en: "Balance training for seniors can be part of a fall prevention program.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'حرکت', en: "movement"),
      en: "movement",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'نشستن طولانی را با وقفه‌های کوتاه ایستادن یا کشش ملایم قطع کنید.',
        en: "Break up long periods of sitting with short breaks of standing or gentle stretching.",
      ),
      en: "Break up long periods of sitting with short breaks of standing or gentle stretching.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'حرکت', en: "movement"),
      en: "movement",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'کفش مناسب و سطح امن، احتمال آسیب هنگام پیاده‌روی را کمتر می‌کند.',
        en: "Appropriate shoes and a safe surface will reduce the possibility of injury while walking.",
      ),
      en: "Appropriate shoes and a safe surface will reduce the possibility of injury while walking.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'حرکت', en: "movement"),
      en: "movement",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'افزایش فعالیت بهتر است تدریجی باشد، مخصوصاً پس از یک دوره کم‌تحرکی.',
        en: "Increasing activity is best done gradually, especially after a period of inactivity.",
      ),
      en: "Increasing activity is best done gradually, especially after a period of inactivity.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'حرکت', en: "movement"),
      en: "movement",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'درد قفسه سینه، تنگی نفس غیرعادی یا سرگیجه هنگام ورزش نیازمند توقف و ارزیابی است.',
        en: "Chest pain, unusual shortness of breath, or dizziness during exercise requires stopping and evaluation.",
      ),
      en: "Chest pain, unusual shortness of breath, or dizziness during exercise requires stopping and evaluation.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'حرکت', en: "movement"),
      en: "movement",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'کارهای روزمره مثل پله، خرید و باغبانی هم می‌توانند بخشی از فعالیت روزانه باشند.',
        en: "Daily tasks such as stairs, shopping and gardening can also be part of the daily activity.",
      ),
      en: "Daily tasks such as stairs, shopping and gardening can also be part of the daily activity.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'حرکت', en: "movement"),
      en: "movement",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'یک قرار پیاده‌روی خانوادگی، هم حرکت و هم ارتباط عاطفی را تقویت می‌کند.',
        en: "A family walking date promotes both movement and emotional connection.",
      ),
      en: "A family walking date promotes both movement and emotional connection.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'حرکت', en: "movement"),
      en: "movement",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'کشش نباید با درد تیز همراه باشد؛ دامنه راحت و کنترل‌شده را انتخاب کنید.',
        en: "Stretching should not be accompanied by sharp pain; Choose a comfortable and controlled domain.",
      ),
      en: "Stretching should not be accompanied by sharp pain; Choose a comfortable and controlled domain.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'قلب و عروق', en: "Cardiovascular"),
      en: "Cardiovascular",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'اندازه‌گیری فشار خون باید در حالت آرام و با کاف مناسب بازو انجام شود.',
        en: "Blood pressure measurement should be done in a relaxed state with a suitable arm cuff.",
      ),
      en: "Blood pressure measurement should be done in a relaxed state with a suitable arm cuff.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'قلب و عروق', en: "Cardiovascular"),
      en: "Cardiovascular",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'ثبت زمان و شرایط اندازه‌گیری فشار خون، تفسیر روند را برای پزشک آسان‌تر می‌کند.',
        en: "Recording the time and conditions of blood pressure measurement makes it easier for the doctor to interpret the process.",
      ),
      en: "Recording the time and conditions of blood pressure measurement makes it easier for the doctor to interpret the process.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'قلب و عروق', en: "Cardiovascular"),
      en: "Cardiovascular",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'کاهش مصرف نمک برای بسیاری از افراد بخشی از مراقبت از فشار خون است.',
        en: "For many people, reducing salt intake is part of taking care of their blood pressure.",
      ),
      en: "For many people, reducing salt intake is part of taking care of their blood pressure.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'قلب و عروق', en: "Cardiovascular"),
      en: "Cardiovascular",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'ترک دخانیات از مهم‌ترین قدم‌ها برای سلامت قلب و ریه است.',
        en: "Quitting smoking is one of the most important steps for heart and lung health.",
      ),
      en: "Quitting smoking is one of the most important steps for heart and lung health.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'قلب و عروق', en: "Cardiovascular"),
      en: "Cardiovascular",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'درد جدید قفسه سینه یا علائم شدید و ناگهانی را نباید با توصیه‌های عمومی مدیریت کرد؛ کمک فوری بگیرید.',
        en: "New chest pain or sudden, severe symptoms should not be managed with general advice; Get immediate help.",
      ),
      en: "New chest pain or sudden, severe symptoms should not be managed with general advice; Get immediate help.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'قلب و عروق', en: "Cardiovascular"),
      en: "Cardiovascular",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'فعالیت منظم، خواب کافی و تغذیه متعادل در کنار درمان پزشکی از سلامت قلب حمایت می‌کنند.',
        en: "Regular activity, adequate sleep and balanced diet along with medical treatment support heart health.",
      ),
      en: "Regular activity, adequate sleep and balanced diet along with medical treatment support heart health.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'دارو', en: "Medication"),
      en: "medicine",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'دارو را دقیقاً طبق دستور پزشک یا داروساز مصرف کنید و دوز را خودسرانه تغییر ندهید.',
        en: "Take the medicine exactly as prescribed by the doctor or pharmacist and do not change the dose arbitrarily.",
      ),
      en: "Take the medicine exactly as prescribed by the doctor or pharmacist and do not change the dose arbitrarily.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'دارو', en: "Medication"),
      en: "medicine",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'فهرست به‌روز داروها، مکمل‌ها و حساسیت‌ها را همراه داشته باشید.',
        en: "Carry an up-to-date list of medications, supplements, and allergies.",
      ),
      en: "Carry an up-to-date list of medications, supplements, and allergies.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'دارو', en: "Medication"),
      en: "medicine",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'برای هر دارو بدانید چرا مصرف می‌شود، چه زمانی باید خورده شود و عارضه مهم آن چیست.',
        en: "For each drug, know why it is used, when it should be taken and what is its important side effect.",
      ),
      en: "For each drug, know why it is used, when it should be taken and what is its important side effect.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'دارو', en: "Medication"),
      en: "medicine",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'داروها را دور از دسترس کودکان و مطابق شرایط درج‌شده روی بسته نگهداری کنید.',
        en: "Keep medicines out of the reach of children and according to the conditions listed on the package.",
      ),
      en: "Keep medicines out of the reach of children and according to the conditions listed on the package.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'دارو', en: "Medication"),
      en: "medicine",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'داروی تاریخ‌گذشته یا بدون برچسب مشخص را مصرف نکنید.',
        en: "Do not use expired or unlabeled medicine.",
      ),
      en: "Do not use expired or unlabeled medicine.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'دارو', en: "Medication"),
      en: "medicine",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'پیش از افزودن مکمل یا داروی بدون نسخه، احتمال تداخل را با پزشک یا داروساز بررسی کنید.',
        en: "Before adding an over-the-counter supplement or medication, check with your doctor or pharmacist for possible interactions.",
      ),
      en: "Before adding an over-the-counter supplement or medication, check with your doctor or pharmacist for possible interactions.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'دارو', en: "Medication"),
      en: "medicine",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'اگر یک نوبت دارو فراموش شد، دستور همان دارو را بررسی کنید؛ دوبرابرکردن دوز همیشه درست نیست.',
        en: "If a dose of medicine is forgotten, check the prescription of the same medicine; Doubling the dose is not always correct.",
      ),
      en: "If a dose of medicine is forgotten, check the prescription of the same medicine; Doubling the dose is not always correct.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'دارو', en: "Medication"),
      en: "medicine",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'جعبه هفتگی دارو برای بعضی افراد مفید است، به شرطی که دارو برای نگهداری خارج بسته مناسب باشد.',
        en: "A weekly medicine box is useful for some people, provided that the medicine is suitable for storage outside the package.",
      ),
      en: "A weekly medicine box is useful for some people, provided that the medicine is suitable for storage outside the package.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'دارو', en: "Medication"),
      en: "medicine",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'یادآور زمانی زمانی مؤثرتر است که با یک عادت ثابت روزانه پیوند بخورد.',
        en: "A reminder is most effective when it is linked to a consistent daily habit.",
      ),
      en: "A reminder is most effective when it is linked to a consistent daily habit.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'دارو', en: "Medication"),
      en: "medicine",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'در مراجعه پزشکی، همه داروهای تجویزی، بدون نسخه و گیاهی را اعلام کنید.',
        en: "Declare all prescription, non-prescription and herbal medicines at the medical visit.",
      ),
      en: "Declare all prescription, non-prescription and herbal medicines at the medical visit.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'چکاپ', en: "checkup"),
      en: "checkup",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'برنامه چکاپ به سن، جنس، سابقه خانوادگی و وضعیت پزشکی هر فرد بستگی دارد.',
        en: "The checkup schedule depends on the age, sex, family history and medical condition of each person.",
      ),
      en: "The checkup schedule depends on the age, sex, family history and medical condition of each person.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'چکاپ', en: "checkup"),
      en: "checkup",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'تاریخ واکسن‌ها را ثبت کنید تا یادآوری نوبت‌های بعدی آسان‌تر شود.',
        en: "Record the date of vaccinations to make it easier to remember the next appointments.",
      ),
      en: "Record the date of vaccinations to make it easier to remember the next appointments.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'چکاپ', en: "checkup"),
      en: "checkup",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'غربالگری‌ها زمانی ارزشمندترند که طبق توصیه معتبر و متناسب با ریسک فرد انجام شوند.',
        en: "Screenings are most valuable when performed according to valid recommendations and appropriate to the individual's risk.",
      ),
      en: "Screenings are most valuable when performed according to valid recommendations and appropriate to the individual's risk.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'چکاپ', en: "checkup"),
      en: "checkup",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'نتایج آزمایش را همراه تاریخ و محدوده مرجع نگهداری کنید تا روندها قابل مقایسه باشند.',
        en: "Keep test results with dates and reference ranges so trends can be compared.",
      ),
      en: "Keep test results with dates and reference ranges so trends can be compared.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'چکاپ', en: "checkup"),
      en: "checkup",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'تغییرات پایدار و غیرعادی بدن را ثبت و در زمان مناسب با پزشک مطرح کنید.',
        en: "Record stable and unusual changes in the body and discuss them with the doctor at the right time.",
      ),
      en: "Record stable and unusual changes in the body and discuss them with the doctor at the right time.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'چکاپ', en: "checkup"),
      en: "checkup",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'معاینه دندان و مراقبت منظم دهان بخشی از سلامت عمومی است.',
        en: "Dental examination and regular oral care are part of general health.",
      ),
      en: "Dental examination and regular oral care are part of general health.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'چکاپ', en: "checkup"),
      en: "checkup",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'بررسی بینایی و شنوایی برای حفظ استقلال و ایمنی سالمندان اهمیت دارد.',
        en: "Checking vision and hearing is important to maintain the independence and safety of the elderly.",
      ),
      en: "Checking vision and hearing is important to maintain the independence and safety of the elderly.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'چکاپ', en: "checkup"),
      en: "checkup",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'پیش از ویزیت، سه سؤال اصلی خود را بنویسید تا چیزی فراموش نشود.',
        en: "Before the visit, write down your three main questions so that nothing is forgotten.",
      ),
      en: "Before the visit, write down your three main questions so that nothing is forgotten.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'چکاپ', en: "checkup"),
      en: "checkup",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'یک همراه مورد اعتماد می‌تواند در ویزیت‌های پیچیده به یادداشت‌برداری کمک کند.',
        en: "A trusted companion can help take notes during complex visits.",
      ),
      en: "A trusted companion can help take notes during complex visits.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'چکاپ', en: "checkup"),
      en: "checkup",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'توصیه‌های پزشکی را با تاریخ، مقدار و زمان پیگیری در یک برنامه روشن ثبت کنید.',
        en: "Record medical advice with date, amount and time of follow-up in a clear schedule.",
      ),
      en: "Record medical advice with date, amount and time of follow-up in a clear schedule.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'سلامت روان', en: "mental health"),
      en: "mental health",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'چند نفس آهسته و عمیق می‌تواند در لحظه‌های تنش به آرام‌ترشدن کمک کند.',
        en: "A few slow, deep breaths can help calm you down in tense moments.",
      ),
      en: "A few slow, deep breaths can help calm you down in tense moments.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'سلامت روان', en: "mental health"),
      en: "mental health",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'ارتباط منظم با یک فرد قابل اعتماد، از احساس تنهایی کم می‌کند.',
        en: "Regular communication with a trusted person reduces the feeling of loneliness.",
      ),
      en: "Regular communication with a trusted person reduces the feeling of loneliness.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'سلامت روان', en: "mental health"),
      en: "mental health",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'استراحت کوتاه مراقب، بخشی از مراقبت مسئولانه است و نشانه کم‌کاری نیست.',
        en: "Caregiver taking short breaks is part of responsible caregiving and is not a sign of inefficiency.",
      ),
      en: "Caregiver taking short breaks is part of responsible caregiving and is not a sign of inefficiency.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'سلامت روان', en: "mental health"),
      en: "mental health",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'نوشتن نگرانی‌ها می‌تواند ذهن را برای تصمیم‌گیری منظم‌تر کند.',
        en: "Writing down your worries can make your mind more organized for decision-making.",
      ),
      en: "Writing down your worries can make your mind more organized for decision-making.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'سلامت روان', en: "mental health"),
      en: "mental health",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'اگر غم، اضطراب یا بی‌انگیزگی پایدار بر زندگی روزمره اثر گذاشته، کمک تخصصی ارزشمند است.',
        en: "If persistent sadness, anxiety, or lack of motivation affects daily life, professional help is valuable.",
      ),
      en: "If persistent sadness, anxiety, or lack of motivation affects daily life, professional help is valuable.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'سلامت روان', en: "mental health"),
      en: "mental health",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'مقایسه مداوم خود با تصاویر ایده‌آل شبکه‌های اجتماعی می‌تواند حال روانی را ضعیف کند.',
        en: "Constantly comparing yourself with ideal images on social networks can weaken your mental state.",
      ),
      en: "Constantly comparing yourself with ideal images on social networks can weaken your mental state.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'سلامت روان', en: "mental health"),
      en: "mental health",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'یک فعالیت کوچک لذت‌بخش را از قبل در برنامه روزانه قرار دهید.',
        en: "Incorporate a small, enjoyable activity into your daily routine.",
      ),
      en: "Incorporate a small, enjoyable activity into your daily routine.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'سلامت روان', en: "mental health"),
      en: "mental health",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'تقسیم یک کار بزرگ به قدم‌های بسیار کوچک، شروع‌کردن را آسان‌تر می‌کند.',
        en: "Breaking down a big task into very small steps makes it easier to get started.",
      ),
      en: "Breaking down a big task into very small steps makes it easier to get started.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'سلامت روان', en: "mental health"),
      en: "mental health",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'بیان روشن نیازها و مرزها از فرسودگی در روابط مراقبتی پیشگیری می‌کند.',
        en: "Clear expression of needs and boundaries prevents burnout in caring relationships.",
      ),
      en: "Clear expression of needs and boundaries prevents burnout in caring relationships.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'سلامت روان', en: "mental health"),
      en: "mental health",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'در بحران روانی یا خطر آسیب، از خدمات فوری و افراد قابل اعتماد کمک بگیرید.',
        en: "In a mental crisis or risk of harm, seek help from emergency services and trusted people.",
      ),
      en: "In a mental crisis or risk of harm, seek help from emergency services and trusted people.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'مراقبت خانوادگی',
        en: "Family care",
      ),
      en: "Family care",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'مسئولیت‌های مراقبت را شفاف تقسیم کنید تا همه بدانند چه کاری بر عهده چه کسی است.',
        en: "Clearly divide caregiving responsibilities so that everyone knows what is done by whom.",
      ),
      en: "Clearly divide caregiving responsibilities so that everyone knows what is done by whom.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'مراقبت خانوادگی',
        en: "Family care",
      ),
      en: "Family care",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'یک فهرست مشترک از داروها، شماره پزشکان و تماس‌های ضروری آماده کنید.',
        en: "Prepare a shared list of medications, doctors' numbers, and emergency contacts.",
      ),
      en: "Prepare a shared list of medications, doctors' numbers, and emergency contacts.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'مراقبت خانوادگی',
        en: "Family care",
      ),
      en: "Family care",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'پرسیدن «چه کمکی برایت مفید است؟» معمولاً بهتر از حدس‌زدن نیاز فرد است.',
        en: "Asking, \"What kind of help is useful to you?\" It is usually better than guessing one's needs.",
      ),
      en: "Asking, \"What kind of help is useful to you?\" It is usually better than guessing one's needs.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'مراقبت خانوادگی',
        en: "Family care",
      ),
      en: "Family care",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'استقلال فرد را تا حد امن حفظ کنید و کارهایی را که می‌تواند انجام دهد از او نگیرید.',
        en: "Keep the person's independence as safe as possible and don't take away from them what they can do.",
      ),
      en: "Keep the person's independence as safe as possible and don't take away from them what they can do.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'مراقبت خانوادگی',
        en: "Family care",
      ),
      en: "Family care",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'در کنار پیگیری درمان، زمانی برای گفت‌وگوی عادی و بدون موضوع پزشکی بگذارید.',
        en: "In addition to pursuing treatment, leave time for a normal conversation without medical issues.",
      ),
      en: "In addition to pursuing treatment, leave time for a normal conversation without medical issues.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'مراقبت خانوادگی',
        en: "Family care",
      ),
      en: "Family care",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'تغییر ناگهانی رفتار، هوشیاری یا توانایی انجام کارهای روزمره را جدی بگیرید.',
        en: "Take seriously a sudden change in behavior, alertness, or ability to perform daily activities.",
      ),
      en: "Take seriously a sudden change in behavior, alertness, or ability to perform daily activities.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'مراقبت خانوادگی',
        en: "Family care",
      ),
      en: "Family care",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'برنامه جایگزین برای زمانی که مراقب اصلی در دسترس نیست، اضطراب را کمتر می‌کند.',
        en: "A substitute schedule for when the primary caregiver is not available reduces anxiety.",
      ),
      en: "A substitute schedule for when the primary caregiver is not available reduces anxiety.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'مراقبت خانوادگی',
        en: "Family care",
      ),
      en: "Family care",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'داده سلامت را فقط با رضایت فرد و در محدوده لازم به اشتراک بگذارید.',
        en: "Share health data only with the consent of the individual and within the necessary limits.",
      ),
      en: "Share health data only with the consent of the individual and within the necessary limits.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'مراقبت خانوادگی',
        en: "Family care",
      ),
      en: "Family care",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'تشویق صادقانه پس از انجام برنامه درمانی می‌تواند از سرزنش مؤثرتر باشد.',
        en: "Sincere encouragement after a treatment program can be more effective than blame.",
      ),
      en: "Sincere encouragement after a treatment program can be more effective than blame.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'مراقبت خانوادگی',
        en: "Family care",
      ),
      en: "Family care",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'برای سالمند، نوشته درشت، کنتراست مناسب و دستورهای کوتاه استفاده را آسان‌تر می‌کند.',
        en: "For the elderly, large text, good contrast and short instructions make it easier to use.",
      ),
      en: "For the elderly, large text, good contrast and short instructions make it easier to use.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'عادت‌های سالم',
        en: "Healthy habits",
      ),
      en: "Healthy habits",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'یک عادت جدید را به کاری که همیشه انجام می‌دهید وصل کنید؛ مثلاً دارو بعد از مسواک.',
        en: "Attach a new habit to something you always do; For example, medicine after brushing.",
      ),
      en: "Attach a new habit to something you always do; For example, medicine after brushing.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'عادت‌های سالم',
        en: "Healthy habits",
      ),
      en: "Healthy habits",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'هدف‌های کوچک و قابل اندازه‌گیری معمولاً پایدارتر از تصمیم‌های بسیار بزرگ هستند.',
        en: "Small, measurable goals are usually more sustainable than very big decisions.",
      ),
      en: "Small, measurable goals are usually more sustainable than very big decisions.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'عادت‌های سالم',
        en: "Healthy habits",
      ),
      en: "Healthy habits",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'محیط را طوری بچینید که انتخاب سالم، ساده‌ترین انتخاب باشد.',
        en: "Arrange the environment so that the healthy choice is the easiest choice.",
      ),
      en: "Arrange the environment so that the healthy choice is the easiest choice.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'عادت‌های سالم',
        en: "Healthy habits",
      ),
      en: "Healthy habits",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'پیشرفت را هفتگی بررسی کنید؛ نوسان یک روز به‌تنهایی تصویر کاملی نمی‌دهد.',
        en: "Check progress weekly; A single day's swing does not give a complete picture.",
      ),
      en: "Check progress weekly; A single day's swing does not give a complete picture.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'عادت‌های سالم',
        en: "Healthy habits",
      ),
      en: "Healthy habits",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'جشن‌گرفتن قدم‌های کوچک به تداوم رفتار کمک می‌کند.',
        en: "Celebrating small steps helps maintain behavior.",
      ),
      en: "Celebrating small steps helps maintain behavior.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'عادت‌های سالم',
        en: "Healthy habits",
      ),
      en: "Healthy habits",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'روزهای ناموفق بخشی از مسیرند؛ به‌جای رهاکردن، از نوبت بعدی ادامه دهید.',
        en: "Unsuccessful days are part of the path; Instead of giving up, continue from the next turn.",
      ),
      en: "Unsuccessful days are part of the path; Instead of giving up, continue from the next turn.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'عادت‌های سالم',
        en: "Healthy habits",
      ),
      en: "Healthy habits",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'یادآور خوب باید در زمان، مکان و با متن روشن به کاربر کمک کند.',
        en: "A good reminder should help the user in time, place and with clear text.",
      ),
      en: "A good reminder should help the user in time, place and with clear text.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'عادت‌های سالم',
        en: "Healthy habits",
      ),
      en: "Healthy habits",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'برای تصمیم‌های تکراری مثل وعده صبحانه یا زمان پیاده‌روی، الگوی ثابت بسازید.',
        en: "Create a consistent pattern for repetitive decisions like what to eat or when to go for a walk.",
      ),
      en: "Create a consistent pattern for repetitive decisions like what to eat or when to go for a walk.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'ایمنی', en: "safety"),
      en: "safety",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'راهروها و مسیرهای رفت‌وآمد خانه را روشن و بدون مانع نگه دارید.',
        en: "Keep the corridors and paths of the house clear and unobstructed.",
      ),
      en: "Keep the corridors and paths of the house clear and unobstructed.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'ایمنی', en: "safety"),
      en: "safety",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'شماره‌های ضروری و اطلاعات پزشکی مهم را در جایی قابل دسترس نگه دارید.',
        en: "Keep essential numbers and important medical information within easy reach.",
      ),
      en: "Keep essential numbers and important medical information within easy reach.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'ایمنی', en: "safety"),
      en: "safety",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'علائم شدید، ناگهانی یا رو به بدترشدن نیازمند ارزیابی حرفه‌ای هستند، نه جست‌وجوی طولانی در اینترنت.',
        en: "Severe, sudden, or worsening symptoms require professional evaluation, not lengthy Internet searches.",
      ),
      en: "Severe, sudden, or worsening symptoms require professional evaluation, not lengthy Internet searches.",
    ),
  ),
  LifeMateHealthFact(
    category: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(fa: 'ایمنی', en: "safety"),
      en: "safety",
    ),
    text: LifeMateRuntimeLocale.select(
      fa: LifeMateRuntimeLocale.select(
        fa: 'برای توصیه‌های سلامت آنلاین، منبع، تاریخ و تناسب آن با شرایط خود را بررسی کنید.',
        en: "For online health advice, check the source, date and suitability for your situation.",
      ),
      en: "For online health advice, check the source, date and suitability for your situation.",
    ),
  ),
];
