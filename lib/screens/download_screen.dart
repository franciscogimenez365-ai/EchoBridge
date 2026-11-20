import 'package:flutter/material.dart';
import '../services/model_manager.dart';

class DownloadScreen extends StatefulWidget {
  final ModelManager modelManager;
  final VoidCallback onDownloadComplete;

  const DownloadScreen({
    super.key,
    required this.modelManager,
    required this.onDownloadComplete,
  });

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';

  Future<void> _startModelDownload() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadStatus = 'Preparando descarga...';
    });

    try {
      await widget.modelManager.downloadAllModels(
        onProgress: (progress, status) {
          if (!mounted) return;
          setState(() {
            _downloadProgress = progress;
            _downloadStatus = status;
          });
        },
      );

      if (!mounted) return;
      widget.onDownloadComplete();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _downloadStatus = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EchoBridge Setup')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.offline_bolt_rounded, size: 72, color: Colors.tealAccent),
            const SizedBox(height: 20),
            const Text(
              'Traducción de voz 100% Offline',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Para funcionar sin internet, EchoBridge necesita descargar los modelos locales de voz y traducción (~210 MB) una única vez.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 32),
            if (_isDownloading) ...[
              LinearProgressIndicator(value: _downloadProgress, minHeight: 8),
              const SizedBox(height: 12),
              Text(
                _downloadStatus,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.tealAccent),
              ),
            ] else ...[
              if (_downloadStatus.startsWith('Error'))
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _downloadStatus,
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                ),
              FilledButton.icon(
                onPressed: _startModelDownload,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Descargar Modelos (ES ↔ EN)'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
