import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lifemate_client/lifemate_client.dart';

class LifeMateSupportChatScreen extends StatefulWidget {
  const LifeMateSupportChatScreen({
    super.key,
    required this.productCode,
    required this.accent,
    required this.background,
    required this.isPersian,
    this.fontFamily,
    this.api,
  });

  final String productCode;
  final Color accent;
  final Color background;
  final bool isPersian;
  final String? fontFamily;
  final LifeMateSupportApi? api;

  @override
  State<LifeMateSupportChatScreen> createState() =>
      _LifeMateSupportChatScreenState();
}

class _LifeMateSupportChatScreenState extends State<LifeMateSupportChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _picker = ImagePicker();
  late final LifeMateSupportApi _api;
  late final bool _ownsApi;
  Timer? _poller;
  String? _conversationId;
  List<LifeMateSupportMessage> _messages = const [];
  XFile? _pendingImage;
  String? _pendingAttachmentMessageId;
  String? _retryBody;
  String? _retryClientMessageId;
  bool _resuming = true;
  bool _loading = false;
  bool _sending = false;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ownsApi = widget.api == null;
    _api = widget.api ?? LifeMateSupportApi.fromEnvironment();
    unawaited(_resumeConversation());
    _poller = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_conversationId != null && !_loading && !_sending) {
        unawaited(_loadMessages(silent: true));
      }
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    if (_ownsApi) _api.close();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _t(String fa, String en) => widget.isPersian ? fa : en;

  Future<void> _resumeConversation() async {
    try {
      final conversation = await _api.current(
        productCode: widget.productCode,
        category: 'general',
      );
      if (!mounted) return;
      if (conversation == null) {
        setState(() => _resuming = false);
        return;
      }
      setState(() {
        _conversationId = conversation.id;
        _resuming = false;
      });
      await _loadMessages();
    } on LifeMateSupportException catch (error) {
      if (!mounted) return;
      setState(() {
        _resuming = false;
        _error = _supportError(error.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resuming = false;
        _error = _t(
          'گفت‌وگوی قبلی دریافت نشد. می‌توانید دوباره تلاش کنید یا پیام جدید بفرستید.',
          'Your previous conversation could not be loaded. Retry or send a new message.',
        );
      });
    }
  }

  Future<void> _pickImage() async {
    if (_uploading || _sending) return;
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    if (!mounted || file == null) return;
    setState(() {
      _pendingImage = file;
      _pendingAttachmentMessageId = null;
      _error = null;
    });
  }

  Future<void> _send() async {
    if (_sending || _uploading) return;
    final body = _controller.text.trim();
    if (body.isEmpty) {
      setState(() {
        _error = _t(
          'برای ارسال، یک پیام بنویسید.',
          'Write a message before sending.',
        );
      });
      return;
    }

    final clientMessageId =
        _retryBody == body && _retryClientMessageId != null
            ? _retryClientMessageId!
            : _newUuid();
    setState(() {
      _sending = true;
      _error = null;
      _retryBody = body;
      _retryClientMessageId = clientMessageId;
    });

    try {
      final result = _conversationId == null
          ? await _api.open(
              productCode: widget.productCode,
              category: 'general',
              body: body,
              clientMessageId: clientMessageId,
            )
          : await _api.send(
              _conversationId!,
              body: body,
              clientMessageId: clientMessageId,
            );
      final ticketId = result['ticketId']?.toString();
      final messageId = result['messageId']?.toString();
      if (ticketId == null ||
          ticketId.isEmpty ||
          messageId == null ||
          messageId.isEmpty) {
        throw const LifeMateSupportException(502, 'support_response_invalid');
      }

      _conversationId = ticketId;
      _controller.clear();
      _retryBody = null;
      _retryClientMessageId = null;

      if (_pendingImage != null) {
        _pendingAttachmentMessageId = messageId;
        await _uploadPendingAttachment();
      }
      await _loadMessages(silent: true);
    } on LifeMateSupportException catch (error) {
      if (mounted) setState(() => _error = _supportError(error.code));
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = _t(
            'ارسال انجام نشد. اتصال اینترنت را بررسی و دوباره تلاش کنید.',
            'Message was not sent. Check your connection and try again.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _uploadPendingAttachment() async {
    final image = _pendingImage;
    final messageId = _pendingAttachmentMessageId;
    final conversationId = _conversationId;
    if (image == null ||
        messageId == null ||
        conversationId == null ||
        _uploading) {
      return;
    }

    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final bytes = await image.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        throw const LifeMateSupportException(
          413,
          'support_attachment_too_large',
        );
      }
      final result = await _api.upload(
        conversationId,
        messageId,
        fileName: image.name,
        contentType: _imageContentType(image.name),
        bytes: bytes,
      );
      final scanStatus = result['scanStatus']?.toString();
      if (scanStatus != 'Available') {
        throw LifeMateSupportException(
          422,
          scanStatus == 'Rejected'
              ? 'support_attachment_rejected'
              : 'support_attachment_scan_failed',
        );
      }
      if (!mounted) return;
      setState(() {
        _pendingImage = null;
        _pendingAttachmentMessageId = null;
      });
    } on LifeMateSupportException catch (error) {
      if (mounted) setState(() => _error = _supportError(error.code));
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = _t(
            'پیام ارسال شد اما تصویر بارگذاری نشد. بارگذاری را دوباره امتحان کنید.',
            'The message was sent, but the image upload failed. Retry the upload.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _loadMessages({bool silent = false}) async {
    final conversationId = _conversationId;
    if (conversationId == null || _loading) return;
    if (!silent) setState(() => _loading = true);
    try {
      final items = await _api.messages(conversationId, limit: 100);
      final sorted = [...items]
        ..sort((a, b) => a.createdAtUtc.compareTo(b.createdAtUtc));
      if (!mounted) return;
      setState(() {
        _messages = sorted;
        _error = null;
      });
      final staffMessages =
          sorted.where((item) => !item.fromUser).toList(growable: false);
      if (staffMessages.isNotEmpty) {
        await _api.markRead(conversationId, staffMessages.last.id);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    } on LifeMateSupportException catch (error) {
      if (mounted && !silent) {
        setState(() => _error = _supportError(error.code));
      }
    } catch (_) {
      if (mounted && !silent) {
        setState(() {
          _error = _t(
            'گفت‌وگو دریافت نشد. دوباره تلاش کنید.',
            'Conversation could not be loaded. Try again.',
          );
        });
      }
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: widget.background,
      appBar: AppBar(
        title: Text(
          _t('پشتیبانی آنلاین', 'Online support'),
          style: TextStyle(fontFamily: widget.fontFamily),
        ),
        backgroundColor: widget.background,
        actions: [
          if (_conversationId != null)
            IconButton(
              tooltip: _t('به‌روزرسانی', 'Refresh'),
              onPressed: _loading ? null : () => _loadMessages(),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _resuming
                  ? const Center(child: CircularProgressIndicator())
                  : _conversationId == null
                      ? _EmptySupportState(
                          accent: widget.accent,
                          isPersian: widget.isPersian,
                          fontFamily: widget.fontFamily,
                        )
                      : _loading && _messages.isEmpty
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) => _MessageBubble(
                                message: _messages[index],
                                accent: widget.accent,
                                fontFamily: widget.fontFamily,
                                isPersian: widget.isPersian,
                              ),
                            ),
            ),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(fontFamily: widget.fontFamily),
                        ),
                      ),
                      if (_pendingImage != null &&
                          _pendingAttachmentMessageId != null)
                        TextButton(
                          onPressed: _uploadPendingAttachment,
                          child: Text(_t('تلاش دوباره', 'Retry')),
                        ),
                    ],
                  ),
                ),
              ),
            if (_pendingImage != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.image_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _pendingImage!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: _t('حذف تصویر', 'Remove image'),
                      onPressed: _uploading
                          ? null
                          : () => setState(() {
                                _pendingImage = null;
                                _pendingAttachmentMessageId = null;
                              }),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 12,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: _t('افزودن تصویر', 'Attach image'),
                    onPressed: _sending || _uploading ? null : _pickImage,
                    icon: const Icon(Icons.attach_file_rounded),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 4000,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: _t(
                          'پیامتان را بنویسید…',
                          'Write your message…',
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                      ),
                      style: TextStyle(fontFamily: widget.fontFamily),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    label: _t('ارسال پیام', 'Send message'),
                    child: IconButton.filled(
                      onPressed: _sending || _uploading ? null : _send,
                      style: IconButton.styleFrom(
                        backgroundColor: widget.accent,
                      ),
                      icon: _sending
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _supportError(String code) => switch (code) {
        'support_attachment_too_large' => _t(
            'حجم تصویر باید کمتر از ۱۰ مگابایت باشد.',
            'Image must be smaller than 10 MB.',
          ),
        'support_attachment_rejected' => _t(
            'این تصویر به دلایل امنیتی پذیرفته نشد.',
            'This image was rejected by the security scan.',
          ),
        'support_attachment_scan_failed' ||
        'support_attachment_runtime_unavailable' =>
          _t(
            'بررسی امنیتی تصویر فعلاً در دسترس نیست. بعداً دوباره تلاش کنید.',
            'Image security scanning is temporarily unavailable. Try again later.',
          ),
        'support_ticket_closed' => _t(
            'این گفت‌وگو بسته شده است. یک گفت‌وگوی جدید شروع کنید.',
            'This conversation is closed. Start a new conversation.',
          ),
        _ => _t(
            'درخواست پشتیبانی انجام نشد. دوباره تلاش کنید.',
            'Support request failed. Try again.',
          ),
      };
}

class _EmptySupportState extends StatelessWidget {
  const _EmptySupportState({
    required this.accent,
    required this.isPersian,
    this.fontFamily,
  });

  final Color accent;
  final bool isPersian;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    String t(String fa, String en) => isPersian ? fa : en;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: accent.withValues(alpha: .12),
              child: Icon(
                Icons.support_agent_rounded,
                color: accent,
                size: 34,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              t('چطور می‌توانیم کمک کنیم؟', 'How can we help?'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t(
                'پیام شما مستقیماً به تیم پشتیبانی LifeMate ارسال می‌شود. اطلاعات سلامت خصوصی به‌صورت خودکار ضمیمه نمی‌شود.',
                'Your message goes directly to LifeMate support. Private health information is not attached automatically.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: fontFamily, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.accent,
    required this.isPersian,
    this.fontFamily,
  });

  final LifeMateSupportMessage message;
  final Color accent;
  final bool isPersian;
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    final mine = message.fromUser;
    return Semantics(
      label: mine
          ? (isPersian ? 'پیام شما' : 'Your message')
          : (isPersian ? 'پاسخ پشتیبانی' : 'Support reply'),
      child: Align(
        alignment: mine
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: mine
                ? accent
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.body,
                style: TextStyle(
                  fontFamily: fontFamily,
                  color: mine ? Colors.white : null,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                TimeOfDay.fromDateTime(message.createdAtUtc.toLocal())
                    .format(context),
                style: TextStyle(
                  fontFamily: fontFamily,
                  fontSize: 10,
                  color: mine
                      ? Colors.white70
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _imageContentType(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

String _newUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
