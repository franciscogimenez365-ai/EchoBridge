import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class DownloadTask {
  final String name;
  final Uri uri;
  final String destinationPath;
  final bool isTarBz2;

  DownloadTask({
    required this.name,
    required this.uri,
    required this.destinationPath,
    this.isTarBz2 = false,
  });
}

class ModelManager {
  static Uri _ghUri(String subPath) =>
      Uri.https('github.com', '/k2-fsa/sherpa-onnx/releases/download/$subPath');

  static Uri _hfUri(String subPath) =>
      Uri.https('huggingface.co', '/Xenova/$subPath');


  Future<String> getModelsBaseDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${appDir.path}/models');
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir.path;
  }

  Future<bool> areModelsReady() async {
    final base = await getModelsBaseDir();
    final requiredFiles = [
      '$base/whisper/base-encoder.int8.onnx',
      '$base/whisper/base-decoder.int8.onnx',
      '$base/whisper/base-tokens.txt',
      '$base/translation/opus-mt-es-en/encoder_model_quantized.onnx',
      '$base/translation/opus-mt-es-en/decoder_model_quantized.onnx',
      '$base/translation/opus-mt-es-en/vocab.json',
      '$base/translation/opus-mt-en-es/encoder_model_quantized.onnx',
      '$base/translation/opus-mt-en-es/decoder_model_quantized.onnx',
      '$base/translation/opus-mt-en-es/vocab.json',
    ];

    for (final path in requiredFiles) {
      if (!await File(path).exists()) return false;
    }
    return true;
  }

  Future<void> downloadAllModels({
    required void Function(double progress, String statusText) onProgress,
  }) async {
    final base = await getModelsBaseDir();

    final tasks = <DownloadTask>[
      DownloadTask(
        name: 'Reconocimiento de voz (Whisper Base)',
        uri: _ghUri('asr-models/sherpa-onnx-whisper-base.tar.bz2'),
        destinationPath: '$base/whisper',
        isTarBz2: true,
      ),
      DownloadTask(
        name: 'Traductor ES->EN (Encoder)',
        uri: _hfUri('opus-mt-es-en/resolve/main/onnx/encoder_model_quantized.onnx'),
        destinationPath: '$base/translation/opus-mt-es-en/encoder_model_quantized.onnx',
      ),
      DownloadTask(
        name: 'Traductor ES->EN (Decoder)',
        uri: _hfUri('opus-mt-es-en/resolve/main/onnx/decoder_model_quantized.onnx'),
        destinationPath: '$base/translation/opus-mt-es-en/decoder_model_quantized.onnx',
      ),
      DownloadTask(
        name: 'Traductor ES->EN (Vocabulario)',
        uri: _hfUri('opus-mt-es-en/resolve/main/vocab.json'),
        destinationPath: '$base/translation/opus-mt-es-en/vocab.json',
      ),
      DownloadTask(
        name: 'Traductor EN->ES (Encoder)',
        uri: _hfUri('opus-mt-en-es/resolve/main/onnx/encoder_model_quantized.onnx'),
        destinationPath: '$base/translation/opus-mt-en-es/encoder_model_quantized.onnx',
      ),
      DownloadTask(
        name: 'Traductor EN->ES (Decoder)',
        uri: _hfUri('opus-mt-en-es/resolve/main/onnx/decoder_model_quantized.onnx'),
        destinationPath: '$base/translation/opus-mt-en-es/decoder_model_quantized.onnx',
      ),
      DownloadTask(
        name: 'Traductor EN->ES (Vocabulario)',
        uri: _hfUri('opus-mt-en-es/resolve/main/vocab.json'),
        destinationPath: '$base/translation/opus-mt-en-es/vocab.json',
      ),
    ];

    for (int i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      final stepProgressBase = i / tasks.length;
      final stepWeight = 1.0 / tasks.length;

      if (!task.isTarBz2 && await File(task.destinationPath).exists()) {
        continue;
      }

      onProgress(stepProgressBase, 'Descargando ${task.name}...');

      final request = http.Request('GET', task.uri);
      request.followRedirects = true;
      final response = await request.send();

      if (response.statusCode != 200) {
        throw Exception('Error descargando ${task.name}: HTTP ${response.statusCode}');
      }

      final contentType = response.headers['content-type'] ?? '';
      if (contentType.contains('text/html')) {
        throw Exception('El servidor devolvió HTML en lugar del archivo para ${task.name}');
      }

      final tempFile = File('${task.destinationPath}.tmp');
      await tempFile.parent.create(recursive: true);
      final sink = tempFile.openWrite();

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          final taskPercent = receivedBytes / totalBytes;
          onProgress(
            stepProgressBase + (taskPercent * stepWeight),
            'Descargando ${task.name} (${(taskPercent * 100).toStringAsFixed(0)}%)',
          );
        }
      }
      await sink.close();

      if (task.isTarBz2) {
        onProgress(
          stepProgressBase + stepWeight * 0.95,
          'Descomprimiendo ${task.name}...',
        );
        await _extractTarBz2FromFile(tempFile, task.destinationPath);
        if (await tempFile.exists()) await tempFile.delete();
      } else {
        final finalFile = File(task.destinationPath);
        if (await finalFile.exists()) await finalFile.delete();
        await tempFile.rename(task.destinationPath);
      }
    }

    onProgress(1.0, '¡Modelos listos!');
  }

  Future<void> _extractTarBz2FromFile(File tarBz2File, String targetDir) async {
    final filePath = tarBz2File.path;
    await Isolate.run(() {
      final bytes = File(filePath).readAsBytesSync();
      final bz2Decoded = BZip2Decoder().decodeBytes(bytes);
      final archive = TarDecoder().decodeBytes(bz2Decoded);

      for (final file in archive) {
        if (!file.isFile) continue;

        String relativePath = file.name;
        if (relativePath.startsWith('sherpa-onnx-whisper-base/')) {
          relativePath = relativePath.replaceFirst('sherpa-onnx-whisper-base/', '');
        }

        final outFile = File('$targetDir/$relativePath');
        outFile.parent.createSync(recursive: true);
        outFile.writeAsBytesSync(file.content as List<int>);
      }
    });
  }
}
