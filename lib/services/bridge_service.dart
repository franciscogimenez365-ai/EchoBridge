import 'dart:async';
import 'package:flutter/services.dart';

class BridgeEvent {
  final String type; // "status", "transcription", "translation"
  final String data;

  BridgeEvent({required this.type, required this.data});
}

class BridgeService {
  static const _methodChannel =
      MethodChannel('com.franciscogimenez365_ai.echo_bridge/methods');
  static const _eventChannel =
      EventChannel('com.franciscogimenez365_ai.echo_bridge/events');

  Stream<BridgeEvent>? _eventStream;

  Stream<BridgeEvent> get events {
    _eventStream ??= _eventChannel.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event as Map);
      return BridgeEvent(
        type: map['type'] as String? ?? '',
        data: map['data'] as String? ?? '',
      );
    });
    return _eventStream!;
  }

  Future<bool> initModels({
    required String modelsDir,
    required String sourceLang,
    required String targetLang,
  }) async {
    final result = await _methodChannel.invokeMethod<bool>('initModels', {
      'modelsDir': modelsDir,
      'sourceLang': sourceLang,
      'targetLang': targetLang,
    });
    return result ?? false;
  }

  Future<void> startListening() async {
    await _methodChannel.invokeMethod('startListening');
  }

  Future<void> stopListening() async {
    await _methodChannel.invokeMethod('stopListening');
  }

  Future<void> speakText(String text) async {
    await _methodChannel.invokeMethod('speakText', {'text': text});
  }
}
