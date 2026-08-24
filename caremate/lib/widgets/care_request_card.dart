import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../core/constants/app_colors.dart';

typedef PhoneCareRequestSubmit = Future<void> Function(String phone);

class CareRequestCard extends StatefulWidget {
  const CareRequestCard({
    required this.loading,
    required this.pendingRequests,
    required this.onRequest,
    required this.onCancel,
    this.phoneRequestSubmit,
    super.key,
  });

  final bool loading;
  final List<Map<String, dynamic>> pendingRequests;
  final VoidCallback? onRequest;
  final ValueChanged<Map<String, dynamic>> onCancel;
  final PhoneCareRequestSubmit? phoneRequestSubmit;

  @override
  State<CareRequestCard> createState() => _CareRequestCardState();
}

class _CareRequestCardState extends State<CareRequestCard> {
  bool _phoneSubmitting = false;
  bool _phoneRequestSubmitted = false;

  Future<void> _showPhoneRequest() async {
    if (_phoneSubmitting) return;
    final controller = TextEditingController();
    var consent = false;
    final phone = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final valid = _looksLikeIranMobile(controller.text);
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      LifeMateRuntimeLocale.select(
                        fa: 'درخواست مراقبت با شماره تلفن',
                        en: 'Request care by phone number',
                      ),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      LifeMateRuntimeLocale.select(
                        fa: 'شماره موبایل فرد را وارد کنید. برای حفظ حریم خصوصی، نتیجه مشخص نمی‌کند این شماره عضو LifeMate هست یا نه. دسترسی فقط بعد از تأیید خود فرد فعال می‌شود.',
                        en: 'Enter the person’s mobile number. For privacy, the result never confirms whether the number belongs to a LifeMate account. Access starts only after their approval.',
                      ),
                      style: const TextStyle(
                        height: 1.6,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('phone-care-request-input'),
                      controller: controller,
                      keyboardType: TextInputType.phone,
                      textDirection: TextDirection.ltr,
                      autocorrect: false,
                      enableSuggestions: false,
                      inputFormatters: const [LifeMateLocaleDigitInputFormatter()],
                      onChanged: (_) => setSheetState(() {}),
                      decoration: InputDecoration(
                        labelText: LifeMateRuntimeLocale.select(
                          fa: 'شماره موبایل',
                          en: 'Mobile number',
                        ),
                        hintText: '0912 123 4567',
                        prefixIcon: const Icon(Icons.phone_iphone_rounded),
                        filled: true,
                        fillColor: const Color(0xFFF3F7FC),
                        errorText: controller.text.isNotEmpty && !valid
                            ? LifeMateRuntimeLocale.select(
                                fa: 'شماره موبایل ایران را درست وارد کنید.',
                                en: 'Enter a valid Iranian mobile number.',
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    CheckboxListTile(
                      value: consent,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (value) =>
                          setSheetState(() => consent = value ?? false),
                      title: Text(
                        LifeMateRuntimeLocale.select(
                          fa: 'می‌دانم درخواست فقط برای تأیید به خود فرد نمایش داده می‌شود و تا قبل از رضایت او هیچ اطلاعات سلامتی در دسترس من نیست.',
                          en: 'I understand the request is shown only for the person’s approval and gives me no health access before consent.',
                        ),
                        style: const TextStyle(fontSize: 12.5, height: 1.55),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const Key('phone-care-request-submit'),
                        onPressed: consent && valid
                            ? () => Navigator.pop(
                                sheetContext,
                                controller.text.trim(),
                              )
                            : null,
                        icon: const Icon(Icons.send_rounded),
                        label: Text(
                          LifeMateRuntimeLocale.select(
                            fa: 'ارسال درخواست',
                            en: 'Submit request',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    controller.dispose();
    if (phone == null || !mounted) return;

    setState(() {
      _phoneSubmitting = true;
      _phoneRequestSubmitted = false;
    });
    try {
      final submit = widget.phoneRequestSubmit;
      if (submit != null) {
        await submit(phone);
      } else {
        await PhoneCareRequestApi.fromEnvironment().create(phone: phone);
      }
      if (!mounted) return;
      setState(() => _phoneRequestSubmitted = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LifeMateRuntimeLocale.select(
              fa: 'درخواست ثبت شد. اگر این شماره واجد شرایط باشد، درخواست داخل WellMate برای تأیید نمایش داده می‌شود.',
              en: 'Request submitted. If eligible, it will appear in WellMate for approval.',
            ),
          ),
        ),
      );
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      final message = switch (error.code) {
        'invalid_phone' || 'invalid_contact' => LifeMateRuntimeLocale.select(
            fa: 'شماره موبایل معتبر نیست. آن را بررسی و دوباره تلاش کنید.',
            en: 'The mobile number is invalid. Check it and try again.',
          ),
        'self_care_request_not_allowed' => LifeMateRuntimeLocale.select(
            fa: 'نمی‌توانید برای حساب خودتان درخواست مراقبت بفرستید.',
            en: 'You cannot request care for your own account.',
          ),
        'network_timeout' || 'network_unavailable' => LifeMateRuntimeLocale.select(
            fa: 'ارتباط برقرار نشد. اینترنت را بررسی و دوباره تلاش کنید.',
            en: 'Could not connect. Check your internet and try again.',
          ),
        _ => LifeMateRuntimeLocale.select(
            fa: 'درخواست ثبت نشد. کمی بعد دوباره تلاش کنید.',
            en: 'The request could not be submitted. Please try again shortly.',
          ),
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _phoneSubmitting = false);
    }
  }

  static bool _looksLikeIranMobile(String input) {
    try {
      LifeMateIranPhone.normalizeE164(input);
      return true;
    } on FormatException {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.loading || _phoneSubmitting;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFEAF5FF), Color(0xFFF6F1FF)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white),
        boxShadow: const [
          BoxShadow(
            color: Color(0x115A78A8),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.volunteer_activism_rounded,
                  color: AppColors.primaryBlue,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      LifeMateRuntimeLocale.select(
                        fa: 'می‌خواهی مراقب کسی باشی؟',
                        en: 'Do you want to take care of someone?',
                      ),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      LifeMateRuntimeLocale.select(
                        fa: 'با شماره موبایل یا ایمیل درخواست بفرست. دسترسی فقط بعد از تأیید خود فرد فعال می‌شود.',
                        en: 'Request by mobile number or email. Access starts only after the person approves.',
                      ),
                      style: const TextStyle(
                        height: 1.55,
                        fontSize: 12.5,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('request-care-by-phone'),
              onPressed: busy ? null : _showPhoneRequest,
              icon: _phoneSubmitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.phone_iphone_rounded),
              label: Text(
                LifeMateRuntimeLocale.select(
                  fa: 'درخواست با شماره تلفن',
                  en: 'Request by phone',
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('request-care-by-email'),
              onPressed: busy ? null : widget.onRequest,
              icon: const Icon(Icons.alternate_email_rounded),
              label: Text(
                LifeMateRuntimeLocale.select(
                  fa: 'درخواست با ایمیل',
                  en: 'Request by email',
                ),
              ),
            ),
          ),
          if (_phoneRequestSubmitted) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              label: LifeMateRuntimeLocale.select(
                fa: 'درخواست تلفنی ثبت شد و منتظر تأیید است.',
                en: 'Phone care request submitted and awaiting approval.',
              ),
              child: Container(
                key: const Key('phone-care-request-success'),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.primaryBlue.withValues(alpha: 0.12),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.schedule_send_rounded,
                      color: AppColors.primaryBlue,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        LifeMateRuntimeLocale.select(
                          fa: 'درخواست تلفنی ثبت شد و منتظر تأیید است. دسترسی هنوز فعال نشده.',
                          en: 'Phone care request submitted and awaiting approval. Access is not active yet.',
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: AppColors.secondaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (widget.pendingRequests.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text(
              LifeMateRuntimeLocale.select(
                fa: 'درخواست‌های در انتظار',
                en: 'Pending requests',
              ),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.primaryText,
              ),
            ),
            const SizedBox(height: 8),
            ...widget.pendingRequests.map((request) {
              final isPhone =
                  request['contactType']?.toString().toLowerCase() == 'phone';
              return Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: const Color(0xFFEAF4FF),
                        child: Icon(
                          isPhone
                              ? Icons.phone_iphone_rounded
                              : Icons.alternate_email_rounded,
                          size: 18,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              LifeMateRuntimeLocale.select(
                                fa: 'در انتظار تأیید',
                                en: 'Awaiting confirmation',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              request['contactHint']?.toString() ?? '',
                              textDirection: TextDirection.ltr,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: LifeMateRuntimeLocale.select(
                          fa: 'لغو درخواست',
                          en: 'Cancel request',
                        ),
                        onPressed: () => widget.onCancel(request),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
