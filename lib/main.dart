import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/download_screen.dart';
import 'services/bridge_service.dart';
import 'services/model_manager.dart';

void main() {
  runApp(const EchoBridgeApp());
}

class EchoBridgeApp extends StatelessWidget {
  const EchoBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EchoBridge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const TranslatorHomePage(),
    );
  }
}

class ChatMessage {
  final String originalText;
  String translatedText;
  ChatMessage({required this.originalText, this.translatedText = 'Traduciendo...'});
}

class TranslatorHomePage extends StatefulWidget {
  const TranslatorHomePage({super.key});

  @override
  State<TranslatorHomePage> createState() => _TranslatorHomePageState();
}

class _TranslatorHomePageState extends State<TranslatorHomePage> {
  final _bridge = BridgeService();
  final _modelManager = ModelManager();
  final _scrollController = ScrollController();

  bool _isCheckingModels = true;
  bool _modelsReady = false;
  bool _isInitializingEngine = false;
  bool _isListening = false;
  String _sourceLang = 'es';
  String _targetLang = 'en';

  final List<ChatMessage> _messages = [];
  StreamSubscription<BridgeEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    _checkInitialState();
    _listenToBridgeEvents();
  }

  Future<void> _checkInitialState() async {
    final ready = await _modelManager.areModelsReady();
    setState(() {
      _modelsReady = ready;
      _isCheckingModels = false;
    });
    if (ready) await _initNativeEngine();
  }

  void _listenToBridgeEvents() {
    _eventSub = _bridge.events.listen((event) {
      if (!mounted) return;
      if (event.type == 'transcription') {
        setState(() => _messages.add(ChatMessage(originalText: event.data)));
        _scrollToBottom();
      } else if (event.type == 'translation') {
        setState(() {
          if (_messages.isNotEmpty) _messages.last.translatedText = event.data;
        });
        _scrollToBottom();
      } else if (event.type == 'status') {
        setState(() => _isListening = event.data == 'listening');
      }
    });
  }

  Future<void> _initNativeEngine() async {
    setState(() => _isInitializingEngine = true);
    final dir = await _modelManager.getModelsBaseDir();
    final ok = await _bridge.initModels(
      modelsDir: dir,
      sourceLang: _sourceLang,
      targetLang: _targetLang,
    );
    if (!mounted) return;
    setState(() => _isInitializingEngine = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron cargar los modelos de IA.')),
      );
    }
  }

  Future<void> _toggleListening() async {
    if (_isInitializingEngine) return;
    if (_isListening) {
      await _bridge.stopListening();
    } else {
      final status = await Permission.microphone.request();
      if (!status.isGranted) return;
      await _bridge.startListening();
    }
  }

  Future<void> _swapLanguages() async {
    if (_isListening) await _bridge.stopListening();
    setState(() {
      final temp = _sourceLang;
      _sourceLang = _targetLang;
      _targetLang = temp;
    });
    await _initNativeEngine();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingModels) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_modelsReady) {
      return DownloadScreen(
        modelManager: _modelManager,
        onDownloadComplete: () {
          setState(() => _modelsReady = true);
          _initNativeEngine();
        },
      );
    }

    final sourceLabel = _sourceLang == 'es' ? 'Español' : 'Inglés';
    final targetLabel = _targetLang == 'es' ? 'Español' : 'Inglés';

    return Scaffold(
      appBar: AppBar(
        title: const Text('EchoBridge'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(() => _messages.clear()),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.black26,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text(sourceLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton.filledTonal(
                  onPressed: _isInitializingEngine ? null : _swapLanguages,
                  icon: const Icon(Icons.swap_horiz_rounded),
                ),
                Text(targetLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          if (_isInitializingEngine) const LinearProgressIndicator(minHeight: 3),
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'Tocá el micrófono y empezá a hablar.\nTodo se procesa offline en tu teléfono.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(msg.originalText, style: const TextStyle(fontSize: 14, color: Colors.white70)),
                              const Divider(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      msg.translatedText,
                                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.tealAccent),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.volume_up_rounded),
                                    onPressed: () => _bridge.speakText(msg.translatedText),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: GestureDetector(
                onTap: _toggleListening,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isListening ? Colors.redAccent : Colors.teal,
                  ),
                  child: Icon(
                    _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                    size: 38,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
