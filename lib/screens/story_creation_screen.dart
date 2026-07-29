import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';
import '../providers/story_provider.dart';
import '../services/api_client.dart';
import 'package:http/http.dart' as http;

class StoryCreationScreen extends ConsumerStatefulWidget {
  final File mediaFile;
  final bool isVideo;
  
  const StoryCreationScreen({super.key, required this.mediaFile, required this.isVideo});
  
  @override
  ConsumerState<StoryCreationScreen> createState() => _StoryCreationScreenState();
}

class _StoryCreationScreenState extends ConsumerState<StoryCreationScreen> {
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _boostAmountController = TextEditingController();
  bool _isUploading = false;
  bool _linkToStore = false;
  
  @override
  void dispose() {
    _captionController.dispose();
    _boostAmountController.dispose();
    super.dispose();
  }
  
  Future<void> _uploadStory() async {
    setState(() { _isUploading = true; });
    
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiClient.baseUrl}/stories'),
      );
      
      request.files.add(await http.MultipartFile.fromPath('file', widget.mediaFile.path));
      
      if (_captionController.text.isNotEmpty) {
        request.fields['caption'] = _captionController.text;
      }
      
      if (_linkToStore) {
         // request.fields['linkedBizId'] = userProfile.businessProfileId;
      }
      
      final response = await apiClient.multipart('/stories', request);
      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = response.body;
        final boostAmount = int.tryParse(_boostAmountController.text) ?? 0;
        
        if (boostAmount > 0) {
          // Parse storyId from responseData if needed
          // await ref.read(storyFeedProvider.notifier).boost(storyId, boostAmount);
        }
        
        ref.invalidate(storyFeedProvider);
        if (mounted) Navigator.pop(context);
      } else {
        throw Exception('Failed to upload story');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() { _isUploading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ref.watch(themeProvider).colors;
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Media Preview
          widget.isVideo 
            ? const Center(child: Text('Video Preview Placeholder', style: TextStyle(color: Colors.white)))
            : Image.file(widget.mediaFile, fit: BoxFit.cover),
          
          SafeArea(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Spacer(),
                
                // Caption Bottom Sheet Overlay
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: _captionController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Add a caption...',
                          hintStyle: TextStyle(color: Colors.white70),
                          border: InputBorder.none,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.store, color: Colors.white70),
                          const SizedBox(width: 8),
                          const Text('Link to my store', style: TextStyle(color: Colors.white)),
                          const Spacer(),
                          Switch(
                            value: _linkToStore,
                            onChanged: (v) => setState(() => _linkToStore = v),
                            activeThumbColor: colors.accent,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.bolt, color: Colors.amberAccent),
                          const SizedBox(width: 8),
                          const Text('Boost (AZM)', style: TextStyle(color: Colors.white)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _boostAmountController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: '0',
                                hintStyle: TextStyle(color: Colors.white70),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.accent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _isUploading ? null : _uploadStory,
                          child: _isUploading 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Post Story', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
