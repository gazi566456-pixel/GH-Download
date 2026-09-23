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
      debugShowCheckedModeBanner: false,
      title: 'Video Downloader',
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: const DownloaderHomePage(),
    );
  }
}

class DownloaderHomePage extends StatefulWidget {
  const DownloaderHomePage({super.key});

  @override
  State<DownloaderHomePage> createState() => _DownloaderHomePageState();
}

class _DownloaderHomePageState extends State<DownloaderHomePage> {
  static const MethodChannel _channel = MethodChannel('video_downloader/ytdlp');

  final TextEditingController _urlController = TextEditingController();

  bool _loading = false;
  bool _downloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';
  String? _error;
  Map<String, dynamic>? _video;
  int? _selectedFormatIndex;

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'downloadProgress') return;
      final data = Map<String, dynamic>.from(call.arguments as Map);
      if (!mounted) return;
      setState(() {
        _downloadProgress = (data['progress'] as num?)?.toDouble() ?? 0.0;
        _downloadStatus = data['line']?.toString() ?? '';
      });
    });
  }

  Future<void> _analyzeUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _error = 'أدخل رابط الفيديو أولاً';
        _video = null;
      });
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _video = null;
      _selectedFormatIndex = null;
    });

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'analyzeUrl',
        {'url': url},
      );
      if (!mounted) return;
      if (result != null) {
        setState(() => _video = Map<String, dynamic>.from(result));
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message ?? 'حدث خطأ أثناء تحليل الرابط');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'حدث خطأ غير متوقع: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadVideo(Map<String, dynamic> format) async {
    if (_video == null || _downloading) return;

    final url = _video!['url']?.toString() ?? '';
    final formatId = format['format_id']?.toString() ?? '';
    final title = _video!['title']?.toString() ?? 'video';
    final acodec = format['acodec']?.toString() ?? '';

    if (url.isEmpty || formatId.isEmpty) {
      setState(() => _error = 'الرابط أو الجودة غير صالحين');
      return;
    }

    setState(() {
      _downloading = true;
      _downloadProgress = 0.0;
      _downloadStatus = 'جاري بدء التنزيل...';
      _error = null;
    });

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'downloadVideo',
        {
          'url': url,
          'formatId': formatId,
          'title': title,
          'hasAudio': acodec.isNotEmpty && acodec != 'none',
        },
      );

      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadProgress = 1.0;
        _downloadStatus =
            result?['message']?.toString() ?? 'تم التنزيل بنجاح';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result?['message']?.toString() ?? 'تم تنزيل الفيديو بنجاح',
          ),
        ),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadStatus = e.message ?? 'فشل التنزيل';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'فشل التنزيل')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadStatus = 'حدث خطأ أثناء التنزيل';
      });
    }
  }

  String _formatDuration(dynamic seconds) {
    final value = double.tryParse(seconds?.toString() ?? '');
    if (value == null || value <= 0) return '--:--';
    final duration = Duration(seconds: value.round());
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _formatFileSize(dynamic bytes) {
    final size = double.tryParse(bytes?.toString() ?? '') ?? 0;
    if (size <= 0) return 'الحجم غير معروف';
    if (size < 1024) return '${size.toStringAsFixed(0)} B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _qualityName(Map<String, dynamic> format) {
    final height = int.tryParse(format['height']?.toString() ?? '');
    if (height != null && height > 0) return '${height}p';
    final note = format['format_note']?.toString() ?? '';
    if (note.isNotEmpty) return note;
    return format['format_id']?.toString() ?? 'جودة غير معروفة';
  }

  String _codecDescription(Map<String, dynamic> format) {
    final vcodec = format['vcodec']?.toString() ?? '';
    final acodec = format['acodec']?.toString() ?? '';
    final parts = <String>[];
    if (vcodec.isNotEmpty && vcodec != 'none') parts.add(vcodec);
    if (acodec.isNotEmpty && acodec != 'none') parts.add(acodec);
    return parts.join(' + ');
  }

  List<Map<String, dynamic>> _getFormats() {
    final raw = _video?['formats'];
    if (raw is! List) return [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  List<Map<String, dynamic>> _getVideoFormats() {
    final formats = _getFormats().where((format) {
      final vcodec = format['vcodec']?.toString() ?? '';
      final height = int.tryParse(format['height']?.toString() ?? '') ?? 0;
      return vcodec.isNotEmpty && vcodec != 'none' && height > 0;
    }).toList();

    formats.sort((a, b) {
      final ah = int.tryParse(a['height']?.toString() ?? '') ?? 0;
      final bh = int.tryParse(b['height']?.toString() ?? '') ?? 0;
      return bh.compareTo(ah);
    });
    return formats;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Downloader', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              const Icon(Icons.download_rounded, size: 70),
              const SizedBox(height: 15),
              const Text('تحميل الفيديو', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('الصق رابط الفيديو لتحليله', textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
              const SizedBox(height: 30),
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  hintText: 'https://example.com/video',
                  prefixIcon: const Icon(Icons.link),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  filled: true,
                ),
                onSubmitted: (_) => _analyzeUrl(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 55,
                child: FilledButton.icon(
                  onPressed: _loading || _downloading ? null : _analyzeUrl,
                  icon: _loading
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search_rounded),
                  label: Text(_loading ? 'جاري التحليل...' : 'تحليل الرابط',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 25),
              if (_error != null) _buildError(),
              if (_video != null) _buildVideoInfo(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.redAccent),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, color: Colors.redAccent),
        const SizedBox(width: 12),
        Expanded(child: Text(_error!, textDirection: TextDirection.rtl)),
      ]),
    );
  }

  Widget _buildVideoInfo() {
    final title = _video!['title']?.toString() ?? 'بدون عنوان';
    final uploader = _video!['uploader']?.toString() ?? '';
    final thumbnail = _video!['thumbnail']?.toString() ?? '';
    final duration = _formatDuration(_video!['duration']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        const Text('معلومات الفيديو', textDirection: TextDirection.rtl,
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        if (thumbnail.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(thumbnail, height: 210, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _thumbnailPlaceholder()),
          )
        else
          _thumbnailPlaceholder(),
        const SizedBox(height: 15),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, textDirection: TextDirection.rtl,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              if (uploader.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(children: [
                  const Icon(Icons.person_outline, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(uploader, textDirection: TextDirection.rtl)),
                ]),
              ],
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.timer_outlined, size: 20),
                const SizedBox(width: 8),
                Text(duration),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        _buildQualitySection(_getVideoFormats()),
      ],
    );
  }

  Widget _thumbnailPlaceholder() {
    return Container(
      height: 210,
      alignment: Alignment.center,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.white10),
      child: const Icon(Icons.video_library_outlined, size: 60),
    );
  }

  Widget _buildQualitySection(List<Map<String, dynamic>> formats) {
    if (formats.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(children: [
            Icon(Icons.video_settings_outlined, size: 40),
            SizedBox(height: 10),
            Text('لم يتم العثور على جودات فيديو قابلة للعرض', textAlign: TextAlign.center,
                textDirection: TextDirection.rtl),
          ]),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('اختر جودة الفيديو', textDirection: TextDirection.rtl,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        ...List.generate(formats.length, (index) {
          final format = formats[index];
          final size = format['filesize'] ?? format['filesize_approx'];
          final selected = _selectedFormatIndex == index;
          final hasAudio = (format['acodec']?.toString() ?? '') != 'none' &&
              (format['acodec']?.toString() ?? '').isNotEmpty;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _downloading ? null : () => setState(() => _selectedFormatIndex = index),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Radio<int>(
                    value: index,
                    groupValue: _selectedFormatIndex,
                    onChanged: _downloading ? null : (value) => setState(() => _selectedFormatIndex = value),
                  ),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_qualityName(format), textDirection: TextDirection.rtl,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    if (size != null) Text(_formatFileSize(size), style: TextStyle(color: Colors.grey.shade400)),
                    Text(hasAudio ? 'فيديو + صوت' : 'فيديو فقط — بدون صوت',
                        style: TextStyle(color: hasAudio ? Colors.grey.shade400 : Colors.orange.shade300, fontSize: 12)),
                    if (_codecDescription(format).isNotEmpty)
                      Text(_codecDescription(format), maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                  ])),
                  if (selected) const Icon(Icons.check_circle),
                ]),
              ),
            ),
          );
        }),
        const SizedBox(height: 10),
        SizedBox(
          height: 54,
          child: FilledButton.icon(
            onPressed: _selectedFormatIndex == null || _downloading
                ? null
                : () => _downloadVideo(formats[_selectedFormatIndex!]),
            icon: _downloading
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_rounded),
            label: Text(
              _downloading ? 'جاري التنزيل ${(_downloadProgress * 100).toStringAsFixed(0)}%' : 'تحميل الفيديو',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        if (_downloading) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _downloadProgress > 0 ? _downloadProgress : null),
          const SizedBox(height: 8),
          Text(_downloadStatus, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ],
    );
  }
}
