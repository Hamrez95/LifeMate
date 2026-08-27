class LifeMateCompanionGuidanceHistoryItem {
  const LifeMateCompanionGuidanceHistoryItem({required this.guidanceId, required this.shownAtUtc});
  final String guidanceId;
  final DateTime shownAtUtc;
}

class LifeMateCompanionSupportActionHistoryItem {
  const LifeMateCompanionSupportActionHistoryItem({required this.actionType, required this.performedAtUtc});
  final String actionType;
  final DateTime performedAtUtc;
}

class LifeMateCompanionGuidance {
  const LifeMateCompanionGuidance({required this.id,required this.category,required this.contentVersion,required this.locale,required this.title,required this.message,required this.cooldown,this.supportActionType,this.supportActionLabel});
  final String id, category, contentVersion, locale, title, message;
  final Duration cooldown;
  final String? supportActionType, supportActionLabel;
}

class LifeMateCompanionCareEngine {
  const LifeMateCompanionCareEngine();
  static const contentVersion='companion-care-v1';
  static const _globalCooldown=Duration(hours:18);
  static const _actionCooldown=Duration(hours:36);

  LifeMateCompanionGuidance? select({required bool phaseAllowed,required bool wellbeingAllowed,required int? cycleDay,required String? mood,required int? energyLevel,required List<LifeMateCompanionGuidanceHistoryItem> guidanceHistory,required List<LifeMateCompanionSupportActionHistoryItem> supportActions,required String locale,required DateTime nowUtc}) {
    if(!phaseAllowed&&!wellbeingAllowed)return null;
    final now=nowUtc.toUtc();
    if(guidanceHistory.any((x)=>now.difference(x.shownAtUtc.toUtc())<_globalCooldown))return null;
    final language=locale.toLowerCase().startsWith('fa')?'fa':'en';
    final candidates=<LifeMateCompanionGuidance>[];
    if(wellbeingAllowed&&energyLevel!=null&&energyLevel<=2)candidates.add(_lowEnergy(language));
    final normalized=mood?.trim().toLowerCase();
    if(wellbeingAllowed&&(normalized=='low'||normalized=='overwhelmed'))candidates.add(_gentleCheckIn(language));
    if(phaseAllowed&&cycleDay!=null&&cycleDay>0)candidates.add(_phaseAware(language));
    if(candidates.isEmpty)candidates.add(_general(language));
    for(final candidate in candidates){
      if(guidanceHistory.any((x)=>x.guidanceId==candidate.id&&now.difference(x.shownAtUtc.toUtc())<candidate.cooldown))continue;
      final action=candidate.supportActionType;
      if(action!=null&&supportActions.any((x)=>_normalizeAction(x.actionType)==action&&now.difference(x.performedAtUtc.toUtc())<_actionCooldown))continue;
      return candidate;
    }
    return null;
  }
  static String _normalizeAction(String value)=>value.trim().toLowerCase().replaceAll('checkin','check_in');
  LifeMateCompanionGuidance _lowEnergy(String l)=>LifeMateCompanionGuidance(id:'energy.give_space',category:'energy',contentVersion:contentVersion,locale:l,title:l=='fa'?'یک همراهی سبک':'A lighter kind of support',message:l=='fa'?'انرژیِ به‌اشتراک‌گذاشته‌شده امروز پایین‌تر است. بدون حدس‌زدن علت، می‌توانی بپرسی آیا سبک‌تر کردن یک کار روزمره کمک‌کننده است یا نه.':'Shared energy is lower today. Without guessing why, you can ask whether making one everyday task lighter would help.',cooldown:const Duration(hours:48),supportActionType:'chores',supportActionLabel:l=='fa'?'کمک در کارها':'Help with chores');
  LifeMateCompanionGuidance _gentleCheckIn(String l)=>LifeMateCompanionGuidance(id:'mood.gentle_check_in',category:'mood',contentVersion:contentVersion,locale:l,title:l=='fa'?'یک احوال‌پرسی آرام':'A gentle check-in',message:l=='fa'?'حالِ به‌اشتراک‌گذاشته‌شده امروز سخت‌تر است. یک پیام کوتاه و بدون فشار می‌تواند فضای همراهی ایجاد کند.':'The shared mood is harder today. A short, no-pressure check-in can create room for support.',cooldown:const Duration(hours:48),supportActionType:'check_in',supportActionLabel:l=='fa'?'احوال‌پرسی کردم':'I checked in');
  LifeMateCompanionGuidance _phaseAware(String l)=>LifeMateCompanionGuidance(id:'phase.be_present',category:'phase',contentVersion:contentVersion,locale:l,title:l=='fa'?'حضور بدون پیش‌فرض':'Be present without assumptions',message:l=='fa'?'خلاصه فاز چرخه با رضایت به اشتراک گذاشته شده است. به‌جای نتیجه‌گیری درباره حال او، می‌توانی فقط آماده شنیدن و همراهی باشی.':'A cycle-phase summary was shared with consent. Rather than assuming how your partner feels, stay available to listen and support.',cooldown:const Duration(hours:72),supportActionType:'check_in',supportActionLabel:l=='fa'?'احوال‌پرسی کردم':'I checked in');
  LifeMateCompanionGuidance _general(String l)=>LifeMateCompanionGuidance(id:'general.ask_first',category:'general',contentVersion:contentVersion,locale:l,title:l=='fa'?'اول بپرس، بعد کمک کن':'Ask first, then help',message:l=='fa'?'اگر می‌خواهی همراهی کنی، یک سؤال ساده مثل «امروز چه کمکی از من می‌خواهی؟» انتخاب را دست خود او نگه می‌دارد.':'If you want to help, a simple “What would be useful from me today?” keeps the choice with your partner.',cooldown:const Duration(hours:72),supportActionType:'check_in',supportActionLabel:l=='fa'?'پرسیدم':'I asked');
}
