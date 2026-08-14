import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';

import '../widgets/sticker_widget.dart';

final stickerStories = [
  Story(
    name: 'Stickers/StickerWidget - Loading',
    builder: (context) => const Center(
      child: StickerWidget(
        url: '/uploads/stickers/animation.tgs',
        width: 160,
        height: 160,
      ),
    ),
  ),
  Story(
    name: 'Stickers/StickerWidget - Broken Image',
    builder: (context) => const Center(
      child: StickerWidget(
        url: '/uploads/stickers/nonexistent.png',
        width: 160,
        height: 160,
      ),
    ),
  ),
  Story(
    name: 'Stickers/StickerThumb - Loading',
    builder: (context) => const Center(
      child: StickerThumb(
        url: '/uploads/stickers/animation.tgs',
        size: 80,
      ),
    ),
  ),
  Story(
    name: 'Stickers/StickerThumb - Broken',
    builder: (context) => const Center(
      child: StickerThumb(
        url: '/uploads/stickers/nonexistent.png',
        size: 80,
      ),
    ),
  ),
];
