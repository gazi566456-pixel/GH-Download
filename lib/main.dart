import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const VideoDownloaderApp());
}

class VideoDownloaderApp extends StatelessWidget {
  const VideoDownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Downloader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const DownloadHomeScreen(),
    );
  }
}

class DownloadHomeScreen extends StatefulWidget {
  const DownloadHomeScreen({super.key});

  @override
  State<DownloadHomeScreen> createState() => _DownloadHomeScreenState();
}

class _DownloadHomeScreenState extends State<DownloadHomeScreen> {
  static const platform = MethodChannel('com.example.video_downloader/bridge');

  final TextEditingController _urlController = TextEditingController();
  bool _isAnalyzing = false;
  String _statusMessage = '';

  Future<void> _analyzeUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال رابط صحيح'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _statusMessage = 'جاري تحليل الرابط...';
    });

    try {
      final String result = await platform.invokeMethod('analyzeUrl', {'url': url});
      setState(() {
        _statusMessage = 'تم التحليل بنجاح: $result';
        _isAnalyzing = false;
      });
    } on PlatformException catch (e) {
      setState(() {
        _statusMessage = 'خطأ في التحليل: ${e.message}';
        _isAnalyzing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Downloader'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'أدخل رابط الفيديو هنا',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isAnalyzing ? null : _analyzeUrl,
              icon: _isAnalyzing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(_isAnalyzing ? 'جاري التحليل...' : 'تحليل الرابط'),
            ),
            const SizedBox(height: 20),
            Text(
              _statusMessage,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
