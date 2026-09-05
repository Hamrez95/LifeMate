import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lifemate_client/lifemate_client.dart';

import '../../core/theme/app_style.dart';

const _maxAttachmentBytes = 15 * 1024 * 1024;
const _maxAttachmentCount = 5;

/// Local, in-memory draft only. The selected file name is deliberately not
/// retained or sent to the Health Record API; only normalized bytes, media
/// type and category are later uploaded through the reviewed endpoint.
class HealthDocumentAttachmentDraft {
  const HealthDocumentAttachmentDraft({
    required this.bytes,
    required this.contentType,
    required this.category,
  });

  final Uint8List bytes;
  final String contentType;
  final LifeMateHealthDocumentCategory category;
}

class HealthDocumentAttachmentSection extends StatelessWidget {
  const HealthDocumentAttachmentSection({
    required this.category,
    required this.attachments,
    required this.onChanged,
    super.key,
    this.enabled = true,
  });

  final LifeMateHealthDocumentCategory category;
  final List<HealthDocumentAttachmentDraft> attachments;
  final ValueChanged<List<HealthDocumentAttachmentDraft>> onChanged;
  final bool enabled;

  Future<void> _add(BuildContext context) async {
    if (!enabled) return;
    if (attachments.length >= _maxAttachmentCount) {
      _notice(context, _fa('برای هر مورد حداکثر ۵ فایل می‌توانی اضافه کنی.', 'You can add up to 5 files for each item.'));
      return;
    }
    final source = await showModalBottomSheet<_DocumentSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _AttachmentSourceSheet(category: category),
    );
    if (source == null || !context.mounted) return;
    try {
      final draft = switch (source) {
        _DocumentSource.camera => await _pickImage(ImageSource.camera),
        _DocumentSource.gallery => await _pickImage(ImageSource.gallery),
        _DocumentSource.file => await _pickFile(),
      };
      if (draft == null || !context.mounted) return;
      if (draft.bytes.lengthInBytes > _maxAttachmentBytes) {
        _notice(context, _fa('حجم هر فایل باید کمتر از ۱۵ مگابایت باشد.', 'Each file must be under 15 MB.'));
        return;
      }
      onChanged([...attachments, draft]);
    } on PlatformException {
      if (context.mounted) {
        _notice(context, _fa('انتخاب فایل انجام نشد. دوباره تلاش کن.', 'The file could not be selected. Please try again.'));
      }
    }
  }

  Future<HealthDocumentAttachmentDraft?> _pickImage(ImageSource source) async {
    final image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 2200,
      maxHeight: 2200,
    );
    if (image == null) return null;
    return _draftFromBytes(await image.readAsBytes(), _typeForPath(image.path));
  }

  Future<HealthDocumentAttachmentDraft?> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'],
      withData: true,
    );
    final files = result?.files;
    final file = files == null || files.isEmpty ? null : files.first;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return null;
    return _draftFromBytes(bytes, _typeForPath(file.extension ?? ''));
  }

  HealthDocumentAttachmentDraft _draftFromBytes(Uint8List bytes, String contentType) {
    if (!const <String>{'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'application/pdf'}.contains(contentType)) {
      throw const PlatformException(code: 'health_document_type_invalid');
    }
    return HealthDocumentAttachmentDraft(bytes: bytes, contentType: contentType, category: category);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE0EEE7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: const Color(0xFFE8F8F1), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.attach_file_rounded, color: AppColors.primary),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_fa('نسخه و مدارک مرتبط', 'Prescription and related documents'), style: AppTextStyles.body(context).copyWith(fontWeight: FontWeight.w900, color: AppColors.darkBlue)),
                    const SizedBox(height: 2),
                    Text(_fa('اختیاری • تصویر یا PDF تا ۱۵ مگابایت', 'Optional • image or PDF up to 15 MB'), style: AppTextStyles.body(context).copyWith(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Text('${attachments.length}/$_maxAttachmentCount', style: AppTextStyles.body(context).copyWith(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 12),
          if (attachments.isEmpty)
            Text(_fa('تصویرها پیش از ارسال سبک می‌شوند؛ نام فایل در پرونده ذخیره نمی‌شود.', 'Images are reduced before upload; file names are not saved.'), style: AppTextStyles.body(context).copyWith(fontSize: 12, height: 1.7, color: AppColors.textSecondary))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var index = 0; index < attachments.length; index++)
                  _AttachmentChip(
                    draft: attachments[index],
                    onDelete: enabled ? () => onChanged([...attachments]..removeAt(index)) : null,
                  ),
              ],
            ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: enabled && attachments.length < _maxAttachmentCount ? () => _add(context) : null,
            icon: const Icon(Icons.add_rounded),
            label: Text(_fa('افزودن فایل', 'Add file')),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: Color(0xFF9EDCC4)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.draft, this.onDelete});
  final HealthDocumentAttachmentDraft draft;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final pdf = draft.contentType == 'application/pdf';
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 6, 8),
      decoration: BoxDecoration(color: const Color(0xFFF3F8F5), borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(pdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded, color: pdf ? const Color(0xFFCF5560) : AppColors.primary, size: 18),
          const SizedBox(width: 6),
          Text('${pdf ? _fa('PDF', 'PDF') : _fa('تصویر', 'Image')} • ${_sizeLabel(draft.bytes.lengthInBytes)}', style: AppTextStyles.body(context).copyWith(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          if (onDelete != null) ...[
            const SizedBox(width: 2),
            IconButton(iconSize: 17, visualDensity: VisualDensity.compact, tooltip: _fa('حذف فایل', 'Remove file'), onPressed: onDelete, icon: const Icon(Icons.close_rounded)),
          ],
        ],
      ),
    );
  }
}

enum _DocumentSource { camera, gallery, file }

class _AttachmentSourceSheet extends StatelessWidget {
  const _AttachmentSourceSheet({required this.category});
  final LifeMateHealthDocumentCategory category;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: const Color(0xFFD6E3DC), borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 20),
          Text(_fa('افزودن مدرک', 'Add a document'), style: AppTextStyles.heading(context).copyWith(fontSize: 20, color: AppColors.darkBlue)),
          const SizedBox(height: 4),
          Text(_fa('تصویر یا PDF را انتخاب کن.', 'Choose an image or PDF.'), style: AppTextStyles.body(context).copyWith(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 18),
          _SourceTile(icon: Icons.photo_camera_rounded, title: _fa('گرفتن عکس', 'Take photo'), subtitle: _fa('برای نسخه یا برگهٔ آزمایش', 'For a prescription or lab sheet'), onTap: () => Navigator.pop(context, _DocumentSource.camera)),
          _SourceTile(icon: Icons.photo_library_rounded, title: _fa('انتخاب از گالری', 'Choose from gallery'), subtitle: _fa('تصویرهای ذخیره‌شده', 'Saved images'), onTap: () => Navigator.pop(context, _DocumentSource.gallery)),
          _SourceTile(icon: Icons.picture_as_pdf_rounded, title: _fa('انتخاب فایل یا PDF', 'Choose file or PDF'), subtitle: _fa('PDF، PNG، JPG، WebP یا HEIC', 'PDF, PNG, JPG, WebP or HEIC'), onTap: () => Navigator.pop(context, _DocumentSource.file)),
        ],
      ),
    ),
  );
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0xFFE8F8F1), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: AppColors.primary)),
    title: Text(title, style: AppTextStyles.body(context).copyWith(fontWeight: FontWeight.w800, color: AppColors.darkBlue)),
    subtitle: Text(subtitle, style: AppTextStyles.body(context).copyWith(fontSize: 12, color: AppColors.textSecondary)),
    trailing: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
    onTap: onTap,
  );
}

String _typeForPath(String value) {
  final extension = value.toLowerCase().split('.').last;
  return switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'pdf' => 'application/pdf',
    _ => '',
  };
}

String _sizeLabel(int bytes) => bytes < 1024 * 1024 ? '${(bytes / 1024).ceil()} KB' : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
String _fa(String fa, String en) => LifeMateRuntimeLocale.select(fa: LifeMateRuntimeLocale.select(fa: fa, en: en), en: en);
void _notice(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
