import 'package:flutter/material.dart';
import 'package:lifemate/living_camp/camp_avatar_fallback.dart';
import 'package:lifemate/living_camp/camp_vector_avatar.dart';

void main() => runApp(const AvatarMotionPreview());

/// Local review harness. Run with `flutter run -t tool/avatar_motion_preview.dart`.
class AvatarMotionPreview extends StatefulWidget {
  const AvatarMotionPreview({super.key});

  @override
  State<AvatarMotionPreview> createState() => _AvatarMotionPreviewState();
}

class _AvatarMotionPreviewState extends State<AvatarMotionPreview> {
  CampAvatarAction action = CampAvatarAction.idle;
  bool motionEnabled = true;
  Color skinTone = const Color(0xFFC99572);
  int command = 0;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LifeMate avatar motion preview',
    home: Scaffold(
      appBar: AppBar(title: const Text('Living Camp avatar motions')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                children: [
                  for (final candidate in CampAvatarAction.values)
                    FilledButton.tonal(
                      onPressed: () => setState(() {
                        action = candidate;
                        command++;
                      }),
                      child: Text(candidate.name),
                    ),
                ],
              ),
              SwitchListTile(
                title: const Text('Motion enabled'),
                value: motionEnabled,
                onChanged: (value) => setState(() => motionEnabled = value),
              ),
              Wrap(
                spacing: 12,
                children: [
                  for (final tone in const [
                    Color(0xFFE9BC98),
                    Color(0xFFC99572),
                    Color(0xFF9B654B),
                    Color(0xFF684634),
                  ])
                    IconButton.filledTonal(
                      onPressed: () => setState(() => skinTone = tone),
                      tooltip: 'Select skin tone',
                      icon: Icon(Icons.circle, color: tone),
                    ),
                ],
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final family in CampAvatarFamily.values)
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 210,
                            height: 310,
                            child: CampVectorAvatar(
                              family: family,
                              action: action,
                              motionEnabled: motionEnabled,
                              skinTone: skinTone,
                              commandId: '$command',
                            ),
                          ),
                          Text(family.name),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
