// main.dart repeatia
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'logger.dart';
import 'dart:async';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Repeatia',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final FlutterTts flutterTts = FlutterTts();

  double _pitch = 0.5; // デフォルトのピッチ
  double _speed = 0.5; // デフォルトのスピード

  final TextEditingController textController = TextEditingController(text: 'I told my wife she should embrace her mistakes. She gave me a hug.');

  static const platform = MethodChannel('com.shirasumaguro.repeatia/beep');
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool isRecording = false;
  bool isPlaying = false;
  Logger logger = Logger();
  String? filePath;
  List<String> _languages = [];

  List<Map<String, dynamic>> _voices = [];
  bool isStopped = false;

  static const int silenceThreshold = 1500; // 3 seconds in milliseconds
  StreamSubscription? _recorderSubscription;
  Completer<void>? _recordingCompleter;

  @override
  void initState() {
    super.initState();
    _initializeRecorder();
    logger.initializeLogFilePath();
    _initializePlayer();
    _loadLanguages();
    _loadVoices();
    _checkPermissions();
  }

  Future<void> _loadLanguages() async {
    var languages = await flutterTts.getLanguages;
    if (languages != null) {
      setState(() {
        _languages = List<String>.from(languages)
            .where((lang) => lang.startsWith('en-')) // Filter languages to those starting with 'en-'
            .toList();
      });
    }
  }

  Future<void> _loadVoices() async {
    var voices = await flutterTts.getVoices;
    if (voices != null) {
      try {
        List<Map<String, dynamic>> formattedVoices = voices.map<Map<String, dynamic>>((voice) {
          return Map<String, dynamic>.from(voice as Map); // キャストを確実に行います
        }).toList();

        setState(() {
          _voices = formattedVoices
              .where((voice) => voice['locale'].startsWith(_selectedLanguage ?? 'en-') // 初期フィルターまたは選択された言語でフィルター
                  )
              .toList();
        });

        // ログに音声の詳細を出力
        print("Available Voices:");
        for (var voice in formattedVoices) {
          print("Voice Name: ${voice['name']}, Locale: ${voice['locale']}");
          if (voice.containsKey('quality')) {
            print("  Quality: ${voice['quality']}");
          }
          if (voice.containsKey('gender')) {
            print("  Gender: ${voice['gender']}");
          }
          if (voice.containsKey('identifier')) {
            print("  Identifier: ${voice['identifier']}");
          }
        }
      } catch (e) {
        print('Error parsing voices: $e');
      }
    }
  }

  Future<void> _initializePlayer() async {
    await _player.openPlayer();
  }

  Future<void> _checkPermissions() async {
    PermissionStatus microphoneStatus = await Permission.microphone.request();
    PermissionStatus storageStatus = await Permission.storage.request();

    if (microphoneStatus.isGranted && storageStatus.isGranted) {
      print("All permissions granted");
    } else {
      print("Permissions not granted $microphoneStatus $storageStatus");
      openAppSettings(); // ユーザーにアプリの設定を開かせて手動で権限を付与させる
    }
  }

  Future<void> _initializeRecorder() async {
    await _recorder.openRecorder();
    _recorder.setSubscriptionDuration(Duration(milliseconds: 100)); // 100ミリ秒ごとに監視
  }

  Future<void> _startRecording() async {
    int silenceDuration = 0;
    int lasttimeduration = 0;

    logger.logWithTimestamp("AAA    _startRecording 1");
    Directory appDirectory = await getApplicationDocumentsDirectory();
    filePath = '${appDirectory.path}/${DateTime.now().millisecondsSinceEpoch}.aac';
    logger.logWithTimestamp("AAA    _startRecording 2 filePath $filePath");

    // 権限が付与されているかを再確認
    print("Microphone permission status before starting recorder: ${await Permission.microphone.status}");

    if (await Permission.microphone.isGranted) {
      _recordingCompleter = Completer<void>();
      await _recorder.startRecorder(toFile: filePath, codec: Codec.aacADTS);

      _recorderSubscription = _recorder.onProgress!.listen((e) {
        logger.logWithTimestamp("AAA    _startRecording e: $e");
        logger.logWithTimestamp("AAA    _startRecording e.decibels ${e.decibels} e.duration.inMilliseconds ${e.duration.inMilliseconds} lasttimeduration $lasttimeduration");
        if (e != null && e.decibels != null && e.decibels! < 22) {
          silenceDuration = e.duration.inMilliseconds - lasttimeduration;
          if (silenceDuration >= silenceThreshold) {
            _stopRecording();
          }
        } else {
          lasttimeduration = e.duration.inMilliseconds;
        }
      });
      logger.logWithTimestamp("AAA    _startRecording 3");
      setState(() {
        isRecording = true;
      });

      // 録音が完了するのを待つ
      await _recordingCompleter!.future;
      logger.logWithTimestamp("AAA    _startRecording 4");
    } else {
      print('Recording permission is not granted');
    }
  }

  Future<void> _stopRecording() async {
    logger.logWithTimestamp("_stopRecording 1");
    await _recorder.stopRecorder();
    _recorderSubscription?.cancel();
    setState(() {
      isRecording = false;
    });
    _recordingCompleter?.complete();
  }

  Future<void> _playRecording() async {
    logger.logWithTimestamp("AAA _playRecording 1 filePath $filePath");
    if (filePath != null) {
      Completer<void> completer = Completer<void>(); // 再生が完了するのを待つためのCompleter

      await _player.setVolume(1.0); // 音量を設定
      await _player.startPlayer(
        fromURI: filePath,
        whenFinished: () {
          logger.logWithTimestamp("AAA _playRecording Playback Finished");
          setState(() {
            isPlaying = false;
          });
          completer.complete(); // 再生が完了したらCompleterを完了させる
        },
      );
      setState(() {
        isPlaying = true;
      });

      await completer.future; // 再生が完了するまでここで待機
    } else {
      print('No recording found!');
    }
  }

  Future<void> _speakAndRecord() async {
    String text = textController.text;
    String? locale = _selectedLanguage;

    //if (locale!.isNotEmpty) {
//      await flutterTts.setLanguage(locale);
//    }

    logger.logWithTimestamp("AAA _speakAndRecord 1");
    await platform.invokeMethod('playBeepok');
    await flutterTts.setVolume(0.001);
    await flutterTts.speak("a");
    await flutterTts.awaitSpeakCompletion(true); // 発声完了を待つ
    await flutterTts.setVolume(1.0);
    await flutterTts.speak(text);
    await flutterTts.awaitSpeakCompletion(true);
    logger.logWithTimestamp("AAA _speakAndRecord 2");
    await platform.invokeMethod('playBeepok');
    await _startRecording();
    logger.logWithTimestamp("AAA _speakAndRecord 3");
    await Future.delayed(Duration(seconds: 1));
    logger.logWithTimestamp("AAA _speakAndRecord 4");
    await platform.invokeMethod('playBeepok');
    //await _stopRecording();
    logger.logWithTimestamp("AAA _speakAndRecord 5");
    await platform.invokeMethod('playBeepok');
    await _playRecording();
    logger.logWithTimestamp("AAA _speakAndRecord 6");
    await platform.invokeMethod('playBeepok');
  }

  Future<void> _startLoop() async {
    isStopped = false;
    while (!isStopped) {
      //isStopped = true;
      await _speakAndRecord();
      await Future.delayed(Duration(seconds: 1)); // Optional delay between loops
    }
  }

  void _stopLoop() {
    setState(() {
      isStopped = true;
    });
  }

  @override
  void dispose() {
    textController.dispose();

    _recorder.closeRecorder();
    _player.closePlayer();
    _recorderSubscription?.cancel();
    super.dispose();
  }

  String? _selectedLanguage;
  Map<String, dynamic>? _selectedVoice;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Repeatia'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            DropdownButton<String>(
              value: _selectedLanguage,
              hint: Text("Select Language"),
              items: _languages.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _selectedLanguage = newValue;
                    flutterTts.setLanguage(newValue);
                  });

                  // 言語が変更された時に適切な音声リストを再ロード
                  _loadVoices().then((_) {
                    setState(() {
                      var newVoice = _voices.firstWhere(
                        (voice) => voice['locale'].startsWith(newValue),
                        orElse: () => <String, dynamic>{}, // 空の Map<String, dynamic> を返す
                      );
                      _selectedVoice = newVoice.isNotEmpty ? newVoice : null; // 空でない場合のみ設定
                    });
                  });
                }
              },
            ),
            if (_voices.isNotEmpty)
              DropdownButton<Map<String, dynamic>>(
                value: _selectedVoice,
                hint: Text("Select Voice"),
                items: _voices.map((Map<String, dynamic> voice) {
                  return DropdownMenuItem<Map<String, dynamic>>(
                    value: voice,
                    child: Text("${voice['name']} (${voice['locale']})"),
                  );
                }).toList(),
                onChanged: (Map<String, dynamic>? newValue) {
                  if (newValue != null) {
                    setState(() {
                      // リスト内のオブジェクトとの一致を保証するために、_selectedVoiceを直接設定します。
                      _selectedVoice = _voices.firstWhere((voice) => voice == newValue, orElse: () => _voices.first);
                    });
                    Map<String, String> voiceMap = newValue.map(
                      (key, value) => MapEntry(key, value.toString()),
                    );
                    flutterTts.setVoice(voiceMap).then((_) {
                      print("Voice set successfully");
                    }).catchError((error) {
                      print("Error setting voice: $error");
                    });
                  }
                },
              ),
            Slider(
              min: 0.1,
              max: 1.0,
              divisions: 10,
              label: 'Pitch $_pitch',
              value: _pitch,
              onChanged: (double value) {
                setState(() {
                  _pitch = value;
                  flutterTts.setPitch(_pitch);
                });
              },
            ),
            Slider(
              min: 0.1,
              max: 1.0,
              divisions: 10,
              label: 'Speed $_speed',
              value: _speed,
              onChanged: (double value) {
                setState(() {
                  _speed = value;
                  flutterTts.setSpeechRate(_speed);
                });
              },
            ),
            TextField(
              controller: textController,
              decoration: InputDecoration(
                labelText: 'Enter text',
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: isRecording ? _stopRecording : _startRecording,
              child: Text(isRecording ? 'Stop Recording' : 'Start Recording'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _playRecording,
              child: Text('Play Recording'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _startLoop,
              child: Text('Speak, Record and Play'),
            ),
            Spacer(),
            ElevatedButton(
              onPressed: _stopLoop,
              child: Text('Stop Loop'),
            ),
          ],
        ),
      ),
    );
  }
}
