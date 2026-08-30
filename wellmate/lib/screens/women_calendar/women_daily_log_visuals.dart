import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const womenLogInk = Color(0xFF3D3542);
const womenLogMuted = Color(0xFF756B77);
const womenLogPrimary = Color(0xFFC83B60);
const womenLogLilac = Color(0xFF8765B4);
const womenLogSoftPink = Color(0xFFFCE5EC);
const womenLogBorder = Color(0xFFEAD7E2);
const womenLogSurfaceAlt = Color(0xFFF6EEFA);

class WomenDailyLogDraft {
  const WomenDailyLogDraft({
    required this.loggedOn,
    this.version = 0,
    this.periodFlow,
    this.bloodAppearance,
    this.bloodTexture,
    this.painLevel,
    this.symptoms = const <String>{},
    this.privateNotes,
  });

  final DateTime loggedOn;
  final int version;
  final String? periodFlow;
  final String? bloodAppearance;
  final String? bloodTexture;
  final int? painLevel;
  final Set<String> symptoms;
  final String? privateNotes;

  Map<String, dynamic> toApiBody() => <String, dynamic>{
    'loggedOn': '${loggedOn.year.toString().padLeft(4, '0')}-${loggedOn.month.toString().padLeft(2, '0')}-${loggedOn.day.toString().padLeft(2, '0')}',
    'version': version,
    'periodFlow': periodFlow,
    'bloodAppearance': bloodAppearance,
    'bloodTexture': bloodTexture,
    'painLevel': painLevel,
    'symptoms': symptoms.toList(growable: false),
    'privateNotes': privateNotes?.trim().isEmpty == true ? null : privateNotes?.trim(),
  };
}

class WomenSymptomOption {
  const WomenSymptomOption(this.id, this.fa, this.en, this.asset);
  final String id;
  final String fa;
  final String en;
  final String asset;
}

const womenSymptomCatalog = <WomenSymptomOption>[
  WomenSymptomOption('cramps', 'گرفتگی', 'Cramps', 'cramps'),
  WomenSymptomOption('headache', 'سردرد', 'Headache', 'headache'),
  WomenSymptomOption('migraine', 'میگرن', 'Migraine', 'migraine'),
  WomenSymptomOption('lower_back_pain', 'کمردرد', 'Lower-back pain', 'lower-back-pain'),
  WomenSymptomOption('bloating', 'نفخ', 'Bloating', 'bloating'),
  WomenSymptomOption('fatigue', 'خستگی', 'Fatigue', 'fatigue'),
  WomenSymptomOption('nausea', 'تهوع', 'Nausea', 'nausea'),
  WomenSymptomOption('breast_tenderness', 'حساسیت سینه', 'Breast tenderness', 'breast-tenderness'),
  WomenSymptomOption('mood_changes', 'تغییرات خلق', 'Mood changes', 'mood-changes'),
  WomenSymptomOption('sleep_changes', 'تغییرات خواب', 'Sleep changes', 'sleep-changes'),
  WomenSymptomOption('appetite_changes', 'تغییر اشتها', 'Appetite changes', 'appetite-changes'),
  WomenSymptomOption('no_symptom', 'بدون علامت', 'No symptom', 'no-symptom'),
  WomenSymptomOption('other', 'سایر', 'Other', 'other'),
];

class PartnerAvatarBadge extends StatelessWidget {
  const PartnerAvatarBadge({super.key, required this.child, this.isPartner = false, this.semanticLabel});
  final Widget child;
  final bool isPartner;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final avatar = SizedBox(width: 48, height: 48, child: ClipOval(child: child));
    if (!isPartner) return avatar;
    return Semantics(
      label: semanticLabel ?? 'شریک',
      image: true,
      child: SizedBox(
        width: 54,
        height: 54,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(left: 0, top: 0, child: avatar),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 22,
                height: 22,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: womenLogBorder, width: 1.5),
                  boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 6, offset: Offset(0, 2))],
                ),
                child: SvgPicture.asset('feature_assets/women_cycle/visual_v1/svg/partner/partner-heart.svg'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<WomenDailyLogDraft?> showWomenDailyLogSheet(
  BuildContext context, {
  required DateTime loggedOn,
  WomenDailyLogDraft? initial,
}) {
  return showModalBottomSheet<WomenDailyLogDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WomenDailyLogSheet(loggedOn: loggedOn, initial: initial),
  );
}

class _WomenDailyLogSheet extends StatefulWidget {
  const _WomenDailyLogSheet({required this.loggedOn, this.initial});
  final DateTime loggedOn;
  final WomenDailyLogDraft? initial;

  @override
  State<_WomenDailyLogSheet> createState() => _WomenDailyLogSheetState();
}

class _WomenDailyLogSheetState extends State<_WomenDailyLogSheet> {
  String? flow;
  String? appearance;
  String? texture;
  int? pain;
  late Set<String> symptoms;
  late TextEditingController notes;

  @override
  void initState() {
    super.initState();
    final value = widget.initial;
    flow = value?.periodFlow;
    appearance = value?.bloodAppearance;
    texture = value?.bloodTexture;
    pain = value?.painLevel;
    symptoms = {...?value?.symptoms};
    notes = TextEditingController(text: value?.privateNotes ?? '');
  }

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  void toggleSymptom(String id) {
    setState(() {
      if (id == 'no_symptom') {
        symptoms = symptoms.contains(id) ? <String>{} : <String>{id};
        return;
      }
      symptoms.remove('no_symptom');
      symptoms.contains(id) ? symptoms.remove(id) : symptoms.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .92),
        decoration: const BoxDecoration(color: Color(0xFFFFF9F4), borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 44, height: 5, decoration: BoxDecoration(color: womenLogBorder, borderRadius: BorderRadius.circular(9))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(rtl ? 'ثبت روزانه پریود' : 'Daily period log', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: womenLogInk)),
                  const SizedBox(height: 4),
                  Text(rtl ? 'همه موارد اختیاری‌اند؛ فقط چیزی را ثبت کن که می‌خواهی.' : 'Every field is optional. Record only what you want.', style: const TextStyle(color: womenLogMuted, height: 1.4)),
                ])),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  _section(rtl ? 'شدت خون‌ریزی' : 'Flow'),
                  _choiceRow([
                    _Choice('light', rtl ? 'کم' : 'Light', const Color(0xFFF3A6B7)),
                    _Choice('medium', rtl ? 'متوسط' : 'Medium', const Color(0xFFD75C8D)),
                    _Choice('heavy', rtl ? 'زیاد' : 'Heavy', const Color(0xFF9E2F57)),
                  ], flow, (v) => setState(() => flow = flow == v ? null : v)),
                  _section(rtl ? 'ظاهر خون' : 'Blood appearance'),
                  _choiceRow([
                    _Choice('bright_red', rtl ? 'قرمز روشن' : 'Bright red', const Color(0xFFE94B5F)),
                    _Choice('red', rtl ? 'قرمز' : 'Red', const Color(0xFFC93B4A)),
                    _Choice('dark_red', rtl ? 'قرمز تیره' : 'Dark red', const Color(0xFF852D3E)),
                    _Choice('brown', rtl ? 'قهوه‌ای' : 'Brown', const Color(0xFF8A5A4A)),
                  ], appearance, (v) => setState(() => appearance = appearance == v ? null : v)),
                  _section(rtl ? 'بافت / قوام' : 'Texture'),
                  _choiceRow([
                    _Choice('usual', rtl ? 'معمول' : 'Usual', womenLogLilac),
                    _Choice('watery', rtl ? 'آبکی' : 'Watery', womenLogLilac),
                    _Choice('thick', rtl ? 'غلیظ' : 'Thick', womenLogLilac),
                    _Choice('clot_observed', rtl ? 'لخته مشاهده شد' : 'Clot observed', womenLogLilac),
                  ], texture, (v) => setState(() => texture = texture == v ? null : v)),
                  _section(rtl ? 'درد' : 'Pain'),
                  Semantics(
                    label: pain == null ? (rtl ? 'شدت درد، ثبت نشده' : 'Pain intensity, not recorded') : (rtl ? 'شدت درد، $pain از ۵' : 'Pain intensity, $pain of 5'),
                    child: Row(children: [
                      IconButton(onPressed: () => setState(() => pain = null), tooltip: rtl ? 'پاک کردن درد' : 'Clear pain', icon: const Icon(Icons.close_rounded, size: 18)),
                      Expanded(child: Slider(value: (pain ?? 0).toDouble(), min: 0, max: 5, divisions: 5, label: pain?.toString() ?? '—', activeColor: womenLogPrimary, onChanged: (v) => setState(() => pain = v.round()))),
                      SizedBox(width: 34, child: Text(pain?.toString() ?? '—', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900))),
                    ]),
                  ),
                  _section(rtl ? 'علائم' : 'Symptoms'),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: womenSymptomCatalog.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisExtent: 96, crossAxisSpacing: 8, mainAxisSpacing: 8),
                    itemBuilder: (context, index) {
                      final item = womenSymptomCatalog[index];
                      final selected = symptoms.contains(item.id);
                      return Semantics(
                        button: true,
                        selected: selected,
                        label: '${rtl ? item.fa : item.en}${selected ? (rtl ? '، انتخاب‌شده' : ', selected') : ''}',
                        child: InkWell(
                          onTap: () => toggleSymptom(item.id),
                          borderRadius: BorderRadius.circular(16),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: selected ? womenLogSoftPink : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: selected ? womenLogPrimary : womenLogBorder, width: selected ? 2 : 1),
                            ),
                            child: Stack(children: [
                              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                SvgPicture.asset('feature_assets/women_cycle/visual_v1/svg/symptoms/${item.asset}.svg', width: 34, height: 34),
                                const SizedBox(height: 6),
                                Text(rtl ? item.fa : item.en, maxLines: 2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: womenLogInk)),
                              ]),
                              if (selected) const Positioned(left: 0, top: 0, child: Icon(Icons.check_circle_rounded, size: 17, color: womenLogPrimary)),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
                  _section(rtl ? 'یادداشت خصوصی' : 'Private note'),
                  TextField(
                    controller: notes,
                    maxLength: 500,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: rtl ? 'فقط برای خودت…' : 'Only for you…',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: womenLogBorder)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: womenLogBorder)),
                    ),
                  ),
                  Text(rtl ? 'این‌ها مشاهده‌های شخصی هستند و تشخیص پزشکی محسوب نمی‌شوند.' : 'These are personal observations, not medical diagnoses.', style: const TextStyle(fontSize: 11, color: womenLogMuted, height: 1.5)),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.viewInsetsOf(context).bottom > 0 ? 8 : 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: womenLogPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: () => Navigator.pop(context, WomenDailyLogDraft(loggedOn: widget.loggedOn, version: widget.initial?.version ?? 0, periodFlow: flow, bloodAppearance: appearance, bloodTexture: texture, painLevel: pain, symptoms: symptoms, privateNotes: notes.text)),
                    child: Text(rtl ? 'ذخیره ثبت روزانه' : 'Save daily log', style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String text) => Padding(padding: const EdgeInsets.only(top: 18, bottom: 8), child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: womenLogInk)));

  Widget _choiceRow(List<_Choice> items, String? selected, ValueChanged<String> onTap) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: items.map((item) {
      final active = item.id == selected;
      return Semantics(
        button: true,
        selected: active,
        label: '${item.label}${active ? '، انتخاب‌شده' : ''}',
        child: InkWell(
          onTap: () => onTap(item.id),
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: const BoxConstraints(minWidth: 76, minHeight: 54),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: active ? womenLogSoftPink : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: active ? womenLogPrimary : womenLogBorder, width: active ? 2 : 1)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 15, height: 15, decoration: BoxDecoration(color: item.color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 2)])),
              const SizedBox(width: 7),
              Text(item.label, style: const TextStyle(fontWeight: FontWeight.w800, color: womenLogInk)),
              if (active) ...[const SizedBox(width: 5), const Icon(Icons.check_circle_rounded, size: 16, color: womenLogPrimary)],
            ]),
          ),
        ),
      );
    }).toList(growable: false),
  );
}

class _Choice {
  const _Choice(this.id, this.label, this.color);
  final String id;
  final String label;
  final Color color;
}
