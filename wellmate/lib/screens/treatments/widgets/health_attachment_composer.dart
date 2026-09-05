import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_style.dart';

/// A privacy-first draft attachment composer. Files remain in the picker
/// result until the owning care record is created and the health-record upload
/// contract accepts them; it never writes medical files to shared app storage.
class HealthAttachmentComposer extends StatefulWidget {
  const HealthAttachmentComposer({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<List<PlatformFile>> onChanged;

  @override
  State<HealthAttachmentComposer> createState() => _HealthAttachmentComposerState();
}

class _HealthAttachmentComposerState extends State<HealthAttachmentComposer> {
  static const _maximumFiles = 10;
  static const _maximumImageBytes = 12 * 1024 * 1024;
  static const _maximumPdfBytes = 15 * 1024 * 1024;
  final List<PlatformFile> _files = [];
  String? _message;
  bool _picking = false;

  Future<void> _pick() async {
    if (_picking || !widget.enabled || _files.length >= _maximumFiles) return;
    setState(() => _picking = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'],
      );
      if (!mounted || picked == null) return;
      final additions = <PlatformFile>[];
      String? validationMessage;
      for (final file in picked.files) {
        final extension = file.extension?.toLowerCase() ?? '';
        final isPdf = extension == 'pdf';
        final limit = isPdf ? _maximumPdfBytes : _maximumImageBytes;
        final duplicate = _files.any((item) =>
            item.name == file.name && item.size == file.size);
        if (duplicate) {
          validationMessage = 'این فایل قبلاً انتخاب شده است.';
        } else if (file.size <= 0 || file.size > limit) {
          validationMessage = isPdf
              ? 'حجم هر PDF حداکثر ۱۵ مگابایت است.'
              : 'حجم هر تصویر حداکثر ۱۲ مگابایت است.';
        } else if (_files.length + additions.length >= _maximumFiles) {
          validationMessage = 'برای هر مورد حداکثر ۱۰ فایل می‌توانید اضافه کنید.';
          break;
        } else {
          additions.add(file);
        }
      }
      if (additions.isNotEmpty) {
        setState(() {
          _files.addAll(additions);
          _message = validationMessage;
        });
        widget.onChanged(List.unmodifiable(_files));
      } else if (validationMessage != null) {
        setState(() => _message = validationMessage);
      }
    } on Exception {
      if (mounted) setState(() => _message = 'انتخاب فایل انجام نشد؛ دوباره تلاش کنید.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _remove(PlatformFile file) {
    setState(() {
      _files.remove(file);
      _message = null;
    });
    widget.onChanged(List.unmodifiable(_files));
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'مدارک و فایل‌های مرتبط',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FCFA),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.primary.withValues(alpha: .14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.attach_file_rounded, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('مدارک و فایل‌های مرتبط', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.darkBlue)),
                      SizedBox(height: 2),
                      Text('نسخه، آزمایش، تصویر یا PDF', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Text('${_files.length}/$_maximumFiles', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textSecondary)),
              ],
            ),
            if (_files.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final file in _files) _AttachmentTile(file: file, onRemove: widget.enabled ? () => _remove(file) : null),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: widget.enabled && !_picking && _files.length < _maximumFiles ? _pick : null,
              icon: _picking
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: Text(_picking ? 'در حال آماده‌سازی…' : 'افزودن فایل'),
            ),
            const SizedBox(height: 7),
            Text(
              _message ?? 'JPG، PNG، WEBP، HEIC یا PDF · تصویر تا ۱۲ و PDF تا ۱۵ مگابایت',
              style: TextStyle(fontSize: 10.5, height: 1.45, color: _message == null ? AppColors.textSecondary : Theme.of(context).colorScheme.error),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.file, this.onRemove});
  final PlatformFile file;
  final VoidCallback? onRemove;
  @override
  Widget build(BuildContext context) {
    final isPdf = file.extension?.toLowerCase() == 'pdf';
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Container(
        padding: const EdgeInsetsDirectional.only(start: 9, end: 4, top: 6, bottom: 6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13)),
        child: Row(children: [
          Icon(isPdf ? Icons.picture_as_pdf_rounded : Icons.image_outlined, color: isPdf ? const Color(0xFFE8655B) : AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
          Text(_sizeLabel(file.size), style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
          IconButton(tooltip: 'حذف فایل', onPressed: onRemove, icon: const Icon(Icons.close_rounded, size: 19)),
        ]),
      ),
    );
  }

  String _sizeLabel(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(bytes / 1024).ceil()} KB';
}
