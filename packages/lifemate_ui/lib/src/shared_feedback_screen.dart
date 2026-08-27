import 'package:flutter/material.dart';
import 'package:lifemate_client/lifemate_client.dart';

class LifeMateFeedbackScreen extends StatefulWidget {
  const LifeMateFeedbackScreen({
    super.key,
    required this.productCode,
    required this.appVersion,
    required this.accent,
    required this.background,
    required this.isPersian,
    this.buildNumber,
    this.fontFamily,
    this.api,
  });

  final String productCode;
  final String appVersion;
  final String? buildNumber;
  final Color accent;
  final Color background;
  final bool isPersian;
  final String? fontFamily;
  final LifeMateFeedbackApi? api;

  @override
  State<LifeMateFeedbackScreen> createState() => _LifeMateFeedbackScreenState();
}

class _LifeMateFeedbackScreenState extends State<LifeMateFeedbackScreen> {
  final _messageController = TextEditingController();
  late final LifeMateFeedbackApi _api;
  late final bool _ownsApi;
  LifeMateFeedbackKind _kind = LifeMateFeedbackKind.feedback;
  int? _npsScore;
  bool _advocacyOptIn = false;
  bool _sending = false;
  bool _sent = false;
  String? _requestId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ownsApi = widget.api == null;
    _api = widget.api ?? LifeMateFeedbackApi.fromEnvironment();
  }

  @override
  void dispose() {
    if (_ownsApi) _api.close();
    _messageController.dispose();
    super.dispose();
  }

  String _t(String fa, String en) => widget.isPersian ? fa : en;

  void _changeKind(LifeMateFeedbackKind kind) {
    if (_sending) return;
    setState(() {
      _kind = kind;
      _npsScore = null;
      _advocacyOptIn = false;
      _requestId = null;
      _error = null;
      _sent = false;
    });
  }

  Future<void> _submit() async {
    if (_sending) return;
    final message = _messageController.text.trim();
    if (_kind != LifeMateFeedbackKind.nps && message.isEmpty) {
      setState(() => _error = _t('لطفاً توضیح کوتاهی بنویسید.', 'Please add a short description.'));
      return;
    }
    if (_kind == LifeMateFeedbackKind.nps && _npsScore == null) {
      setState(() => _error = _t('یک امتیاز از ۰ تا ۱۰ انتخاب کنید.', 'Choose a score from 0 to 10.'));
      return;
    }
    if (_kind == LifeMateFeedbackKind.advocacy && !_advocacyOptIn) {
      setState(() => _error = _t('برای ارسال این مورد، رضایت داوطلبانه را تأیید کنید.', 'Confirm voluntary participation before submitting this item.'));
      return;
    }

    final requestId = _requestId ?? lifeMateFeedbackRequestId();
    setState(() {
      _sending = true;
      _error = null;
      _requestId = requestId;
    });
    try {
      await _api.submit(
        LifeMateFeedbackSubmission(
          kind: _kind,
          productCode: widget.productCode,
          appVersion: widget.appVersion,
          buildNumber: widget.buildNumber,
          idempotencyKey: requestId,
          npsScore: _npsScore,
          message: message.isEmpty ? null : message,
          advocacyOptIn: _advocacyOptIn,
        ),
      );
      if (!mounted) return;
      setState(() {
        _sent = true;
        _requestId = null;
      });
    } on LifeMateApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = _errorMessage(error.code));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = _t('ارسال انجام نشد. دوباره تلاش کنید.', 'Submission failed. Try again.'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _newSubmission() {
    setState(() {
      _sent = false;
      _requestId = null;
      _error = null;
      _npsScore = null;
      _advocacyOptIn = false;
      _messageController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.background,
      appBar: AppBar(
        backgroundColor: widget.background,
        title: Text(
          _t('نظر و پیشنهاد', 'Feedback'),
          style: TextStyle(fontFamily: widget.fontFamily),
        ),
      ),
      body: SafeArea(
        child: _sent ? _success() : _form(),
      ),
    );
  }

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        Text(
          _t('چه چیزی می‌خواهید با ما در میان بگذارید؟', 'What would you like to share?'),
          style: TextStyle(
            fontFamily: widget.fontFamily,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _t(
            'ارسال نظر اختیاری است. اطلاعات سلامت شما به‌صورت خودکار به این فرم اضافه نمی‌شود.',
            'Feedback is optional. Your health information is not attached to this form automatically.',
          ),
          style: TextStyle(fontFamily: widget.fontFamily, height: 1.5),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: LifeMateFeedbackKind.values
              .map(
                (kind) => ChoiceChip(
                  label: Text(_kindLabel(kind)),
                  selected: _kind == kind,
                  onSelected: _sending ? null : (_) => _changeKind(kind),
                  selectedColor: widget.accent.withValues(alpha: .16),
                  labelStyle: TextStyle(
                    fontFamily: widget.fontFamily,
                    fontWeight: _kind == kind ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 22),
        if (_kind == LifeMateFeedbackKind.nps) ...[
          Text(
            _t('چقدر احتمال دارد LifeMate را به دیگران پیشنهاد کنید؟', 'How likely are you to recommend LifeMate?'),
            style: TextStyle(fontFamily: widget.fontFamily, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(
              11,
              (score) => ChoiceChip(
                key: ValueKey('feedback-nps-$score'),
                label: Text('$score'),
                selected: _npsScore == score,
                onSelected: _sending ? null : (_) => setState(() {
                  _npsScore = score;
                  _requestId = null;
                  _error = null;
                }),
                selectedColor: widget.accent.withValues(alpha: .18),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_t('بعید است', 'Not likely'), style: TextStyle(fontFamily: widget.fontFamily, fontSize: 12)),
              Text(_t('خیلی محتمل', 'Very likely'), style: TextStyle(fontFamily: widget.fontFamily, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 20),
        ],
        TextField(
          controller: _messageController,
          enabled: !_sending,
          minLines: 4,
          maxLines: 8,
          maxLength: 2000,
          onChanged: (_) {
            if (_requestId != null) setState(() => _requestId = null);
          },
          decoration: InputDecoration(
            labelText: _kind == LifeMateFeedbackKind.nps
                ? _t('توضیح بیشتر (اختیاری)', 'More details (optional)')
                : _t('توضیحات', 'Details'),
            hintText: _hint(),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
          ),
          style: TextStyle(fontFamily: widget.fontFamily),
        ),
        if (_kind == LifeMateFeedbackKind.advocacy) ...[
          const SizedBox(height: 10),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _advocacyOptIn,
            onChanged: _sending
                ? null
                : (value) => setState(() {
                      _advocacyOptIn = value == true;
                      _requestId = null;
                      _error = null;
                    }),
            title: Text(
              _t(
                'داوطلبانه می‌خواهم در برنامه‌های معرفی LifeMate مشارکت کنم.',
                'I voluntarily want to participate in LifeMate advocacy programs.',
              ),
              style: TextStyle(fontFamily: widget.fontFamily, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              _t(
                'این گزینه هیچ دسترسی خودکاری به شبکه‌های اجتماعی شما نمی‌دهد.',
                'This does not give LifeMate automatic access to your social accounts.',
              ),
              style: TextStyle(fontFamily: widget.fontFamily),
            ),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: TextStyle(
                fontFamily: widget.fontFamily,
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const ValueKey('feedback-submit'),
          onPressed: _sending ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: widget.accent,
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          icon: _sending
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.send_rounded),
          label: Text(
            _t('ارسال', 'Submit'),
            style: TextStyle(fontFamily: widget.fontFamily, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  Widget _success() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: widget.accent.withValues(alpha: .14),
              child: Icon(Icons.check_rounded, color: widget.accent, size: 36),
            ),
            const SizedBox(height: 18),
            Text(
              _t('ممنون که کمک می‌کنید LifeMate بهتر شود.', 'Thanks for helping LifeMate improve.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: widget.fontFamily, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _newSubmission,
              child: Text(_t('ارسال نظر دیگر', 'Send another')),
            ),
          ],
        ),
      ),
    );
  }

  String _kindLabel(LifeMateFeedbackKind kind) => switch (kind) {
        LifeMateFeedbackKind.feedback => _t('نظر', 'Feedback'),
        LifeMateFeedbackKind.nps => _t('امتیاز', 'NPS'),
        LifeMateFeedbackKind.bugReport => _t('گزارش مشکل', 'Bug'),
        LifeMateFeedbackKind.featureRequest => _t('پیشنهاد قابلیت', 'Feature request'),
        LifeMateFeedbackKind.advocacy => _t('همراهی در معرفی', 'Advocacy'),
      };

  String _hint() => switch (_kind) {
        LifeMateFeedbackKind.feedback => _t('چه چیزی خوب بود یا بهتر می‌تواند باشد؟', 'What worked well or could be better?'),
        LifeMateFeedbackKind.nps => _t('اگر دوست دارید دلیل امتیازتان را بنویسید…', 'Optionally tell us why you chose this score…'),
        LifeMateFeedbackKind.bugReport => _t('مشکل چه زمانی و در کدام بخش رخ داد؟ اطلاعات حساس سلامت را ننویسید.', 'What happened and where? Please avoid sensitive health details.'),
        LifeMateFeedbackKind.featureRequest => _t('چه قابلیتی برایتان مفید است؟', 'What feature would be useful to you?'),
        LifeMateFeedbackKind.advocacy => _t('چطور دوست دارید در معرفی LifeMate همراه شوید؟', 'How would you like to help introduce LifeMate?'),
      };

  String _errorMessage(String code) => switch (code) {
        'network_timeout' || 'network_unavailable' => _t('اتصال برقرار نشد. همان ارسال را دوباره امتحان کنید.', 'Connection failed. Retry the same submission.'),
        'feedback_nps_score_invalid' => _t('امتیاز باید عددی بین ۰ تا ۱۰ باشد.', 'NPS score must be between 0 and 10.'),
        'feedback_advocacy_opt_in_required' => _t('برای مشارکت در معرفی، رضایت داوطلبانه لازم است.', 'Voluntary opt-in is required for advocacy.'),
        'feedback_message_required' => _t('لطفاً توضیح کوتاهی بنویسید.', 'Please add a short description.'),
        _ => _t('ارسال انجام نشد. دوباره تلاش کنید.', 'Submission failed. Try again.'),
      };
}
