import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/story_service.dart';
import '../../models/story.dart';

class StoryCreationScreen extends StatefulWidget {
  const StoryCreationScreen({super.key});

  @override
  State<StoryCreationScreen> createState() => _StoryCreationScreenState();
}

class _StoryCreationScreenState extends State<StoryCreationScreen> {
  File? _mediaFile;
  StoryMediaType? _mediaType;
  final TextEditingController _captionController = TextEditingController();
  bool _publishing = false;

  Future<void> _pickMedia(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked != null) {
      setState(() {
        _mediaFile = File(picked.path);
        _mediaType = StoryMediaType.image;
      });
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickVideo(source: source);
    if (picked != null) {
      setState(() {
        _mediaFile = File(picked.path);
        _mediaType = StoryMediaType.video;
      });
    }
  }

  void _showPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickMedia(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickMedia(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Record Video'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickVideo(ImageSource.camera);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _publish() async {
    if (_mediaFile == null || _mediaType == null) return;
    setState(() => _publishing = true);
    try {
      await StoryService.instance.publishStory(
        mediaPath: _mediaFile!.path,
        mediaType: _mediaType!,
        caption: _captionController.text.trim().isEmpty
            ? null
            : _captionController.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Story'),
        actions: [
          if (_mediaFile != null)
            TextButton(
              onPressed: _publishing ? null : _publish,
              child: _publishing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Share'),
            ),
        ],
      ),
      body: _mediaFile == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 80,
                    color: cs.primary,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _showPicker,
                    icon: const Icon(Icons.add),
                    label: const Text('Choose Photo or Video'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _showPicker,
                    child: Container(
                      width: double.infinity,
                      color: Colors.black,
                      child: _mediaType == StoryMediaType.image
                          ? Image.file(_mediaFile!, fit: BoxFit.contain)
                          : const Center(
                              child: Icon(
                                Icons.videocam,
                                size: 64,
                                color: Colors.white54,
                              ),
                            ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _captionController,
                    decoration: InputDecoration(
                      hintText: 'Add a caption...',
                      prefixIcon: const Icon(Icons.text_fields),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    maxLength: 150,
                  ),
                ),
              ],
            ),
      floatingActionButton: _mediaFile == null
          ? FloatingActionButton(
              onPressed: _showPicker,
              child: const Icon(Icons.add_a_photo),
            )
          : null,
    );
  }
}
