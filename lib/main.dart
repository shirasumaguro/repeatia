import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:convert';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:audio_session/audio_session.dart' as audio_session;
import 'package:audioplayers/audioplayers.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'logger.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'TtsService.dart';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';

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
        debugShowCheckedModeBanner: false, // バッジを非表示にする
        home: MyHomePage());
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TtsService ttsService = TtsService();
  List<String> _sentences = [];
  String displaytext = "";
  String displaytext2 = "";
  Completer<void>? nextCompleter;
  late Completer<void> _recognitionCompleter;
  late stt.SpeechToText _speech; // 'late' キーワードを使用
  bool _isListening = false;
  bool gonext = false;
  List<String> _textList = []; // テキストを保持するリスト
  double _pitch = 0.5; // デフォルトのピッチ
  double _speed = 0.5; // デフォルトのスピード
  double _speedvid = 0.5; // デフォルトの動画再生速度
  SharedPreferences? prefs;
  bool textedited = false;
  Timer? _timeoutTimer; // タイムアウトを管理するTimer

  bool answershowing = false;
  bool inflash = false;
  String? _selectedSentence;
  final TextEditingController textController = TextEditingController(
      text:
          "(英語圏旅行フレーズ) [こんにちは] Hello /[ありがとう] Thank you /[すみません] Excuse me /[はい] Yes /[いいえ] No /[お願いします] Please /[トイレどこですか？] Where is the restroom? /[これ下さい] I'd like this /[理解できません] I don't understand /[大丈夫です] No problem /[最高です] Excellent /[ちょっと待って] Wait a minute /[止まって] Stop /[お先にどうぞ] Go ahead /[要りません] I don't need it /[結構です] No, thank you /[見てもいいですか？] Can I take a look? /[どういたしまして] You're welcome /[ごめんなさい] I'm sorry /[ゴミ箱どこですか？] Where is the trash can? /[店内で] For here /[お持ち帰りで] To go /[1名] One person /[2名] Two people /[熱い] Hot /[冷たい] Cold /[お釣りを下さい。] Please give me my change /[お釣りはいりません。] Keep the change /[メニューをください] May I have the menu? /[おすすめは？] What do you recommend? /[いくらですか？] How much is this? /[以上です] That's all /[ビールください] A beer, please /[水を下さい] Water, please /[小皿を下さい] A small plate, please /[お箸はありますか？] Do you have chopsticks? /[パクチーはいれないで] No cilantro, please /[辛くして] Make it spicy /[大きい] Large /[中くらい] Medium /[小さい] Small /[急いでください] Please hurry /[どのくらいかかりますか？] How long will it take? /[おいしいです。] It's delicious /[包んでください] Please wrap it up /[お会計をお願いします] Check, please /[駅まで行ってください。] Please take me to the station /[英語話せますか？] Do you speak English? /[日本人です] I'm a Japanese /[英語話せません] I don't speak English /[私はアメリカ人ではありません] I'm not an American");

  static const platform = MethodChannel('com.shirasumaguro.repeatia/beep');
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  bool isRecording = false;
  bool isPlaying = false;
  bool isSpeaking = false;
  bool pausing = false;
  bool _speedset = false;
  Map<String, Map<String, String>> _voiceMap = {};
  String _recogtext = "";
  Logger logger = Logger();
  String? filePath;

  bool _speak1Checked = true;
  bool _recordChecked = true;
  bool _speak2Checked = false;
  bool _playChecked = true;
  List<String> _languages = [];
  String? _selectedFilePath;
  int selectedindex = 0;
  VideoPlayerController? _videoController;
  String? _selectedFileName;
  List<Map<String, dynamic>> _voices = [];

  String? _selectedLanguage = 'en-US';
  String? _selectedVoice; // 型を String? に変更

  bool isStopped = true;
  bool inLoop = false;

  static const int silenceThreshold = 800; // 3秒の無音判定
  StreamSubscription? _recorderSubscription;
  Completer<void>? _recordingCompleter;
  //String? selectedLanguage;
  Map<String, dynamic>? selectedVoice;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText(); // ここで初期化
    _initializeSpeech();
    _initializeRecorder();
    logger.initializeLogFilePath();
    _initializePlayer();
    // Wake Lockを有効化して、アプリがアクティブな間画面をスリープさせない
    WakelockPlus.enable();
    logger.logWithTimestamp("AAA before _initialize _selectedlanguage $_selectedLanguage");
    _initialize();

    _checkPermissions();

    ttsService.onTextChanged = (String newText) {
      setState(() {
        ttsService.chosentext = newText;
      });
    };
    // TtsService にコールバックを渡す
    ttsService.onSentencesLoaded = (List<String> sentences) {
      setState(() {
        _sentences = sentences;
      });
    };

    // センテンスのロードを開始
    ttsService.loadSentences();
  }

  Future<void> _initializeSpeech() async {
    bool available = await _speech.initialize(
      onStatus: (val) {
        logger.logWithTimestamp("AAA onStatus: $val");
        /*// リスニングが終了した場合、Completerを完了させる
        if (val == 'done' || val == 'notListening') {
          if (!_recognitionCompleter.isCompleted) {
            _recognitionCompleter.complete();
          }
        }
         */
      },
      onError: (val) {
        logger.logWithTimestamp("AAA onError: $val");
        _isListening = false;
        // エラーが発生した場合、Completerを完了させる
        if (!_recognitionCompleter.isCompleted) {
          _recognitionCompleter.complete();
        }
      },
    );

    if (!available) {
      print('The user has denied the use of speech recognition.');
    } else {
      print('Speech recognition available');
    }
  }

  Future<void> _listen() async {
    _recogtext = "";
    logger.logWithTimestamp("AAA in _listen 1 $_selectedLanguage $_recogtext _isListening $_isListening");

    if (!_isListening) {
      setState(() => _isListening = true);

      _speech.listen(
        onResult: (result) {
          logger.logWithTimestamp("AAA in _listen onResult result.finalResult ${result.finalResult} $result.recognizedWords");
          setState(() {
            // IOSの場合はfinalResultがfalseで終わる
            if (result.finalResult && Platform.isIOS || Platform.isAndroid) {
              _recogtext = result.recognizedWords;
              logger.logWithTimestamp("AAA in _listen onResult in if block result.finalResult ${result.finalResult} $_recogtext");
              _isListening = false;
              _recognitionCompleter.complete(); // 認識が完了したことをCompleterに通知
            }
          });
        },
        localeId: _selectedLanguage, // 言語コードを指定
        listenFor: Duration(seconds: 5), // リスニングの時間を指定
        pauseFor: Duration(seconds: 2), // 無音検出後の一時停止
        partialResults: true, // 部分的な結果も受け取る
      );
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }

    logger.logWithTimestamp("AAA in _listen 2 $_recogtext");
  }

  Future<void> _initialize() async {
    await _loadLanguages();

    await _loadVoices();

    await loadSettings();

    setState(() {});
    logger.logWithTimestamp("AAA 1 _selectedLanguage $_selectedLanguage");

    _checkPermissions();
    ttsService.onSentencesLoaded = (List<String> sentences) {
      setState(() {
        _sentences = sentences;
      });
    };
    ttsService.loadSentences();

    // TTS設定の適用
    if (_selectedLanguage != null) {
      ttsService.setLanguage(_selectedLanguage!);
    }
    if (_selectedVoice != null) {
      Map<String, String>? voiceDetails = _voiceMap[_selectedVoice!];
      if (voiceDetails != null) {
        ttsService.setVoice(voiceDetails);
      }
    }
  }

  Future<void> saveSettings(String language, String voiceIdentifier) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', language);
    await prefs.setString('voiceIdentifier', voiceIdentifier);
    await prefs.setString('currentText', textController.text);
    await prefs.setBool('speak1', _speak1Checked);
    await prefs.setBool('speak2', _speak2Checked);
    await prefs.setBool('record', _recordChecked);
    await prefs.setBool('play', _playChecked);
    print("Settings saved: $language, $voiceIdentifier");
  }

  Future<void> loadSettings() async {
    prefs = await SharedPreferences.getInstance();
    String? language = prefs?.getString('language') ?? "en-US";
    String? voiceIdentifier = prefs?.getString('voiceIdentifier');

    // currentTextが存在しない場合にはデフォルトのテキストを指定する
    String defaultText =
        "(英語圏旅行フレーズ) [こんにちは] Hello /[ありがとう] Thank you /[すみません] Excuse me /[はい] Yes /[いいえ] No /[お願いします] Please /[トイレどこですか？] Where is the restroom? /[これ下さい] I'd like this /[理解できません] I don't understand /[大丈夫です] No problem /[最高です] Excellent /[ちょっと待って] Wait a minute /[止まって] Stop /[お先にどうぞ] Go ahead /[要りません] I don't need it /[結構です] No, thank you /[見てもいいですか？] Can I take a look? /[どういたしまして] You're welcome /[ごめんなさい] I'm sorry /[ゴミ箱どこですか？] Where is the trash can? /[店内で] For here /[お持ち帰りで] To go /[1名] One person /[2名] Two people /[熱い] Hot /[冷たい] Cold /[お釣りを下さい。] Please give me my change /[お釣りはいりません。] Keep the change /[メニューをください] May I have the menu? /[おすすめは？] What do you recommend? /[いくらですか？] How much is this? /[以上です] That's all /[ビールください] A beer, please /[水を下さい] Water, please /[小皿を下さい] A small plate, please /[お箸はありますか？] Do you have chopsticks? /[パクチーはいれないで] No cilantro, please /[辛くして] Make it spicy /[大きい] Large /[中くらい] Medium /[小さい] Small /[急いでください] Please hurry /[どのくらいかかりますか？] How long will it take? /[おいしいです。] It's delicious /[包んでください] Please wrap it up /[お会計をお願いします] Check, please /[駅まで行ってください。] Please take me to the station /[英語話せますか？] Do you speak English? /[日本人です] I'm a Japanese /[英語話せません] I don't speak English /[私はアメリカ人ではありません] I'm not an American";

    // textControllerがnullでないか確認し、currentTextを取得
    textController.text = prefs?.getString('currentText') ?? defaultText;
    _speak1Checked = prefs?.getBool('speak1') ?? true;
    _speak2Checked = prefs?.getBool('speak2') ?? false;
    _recordChecked = prefs?.getBool('record') ?? true;
    _playChecked = prefs?.getBool('play') ?? true;

    logger.logWithTimestamp("AAA loadSetting start - language: $language, voiceIdentifier: $voiceIdentifier");

    try {
      if (language != null) {
        _selectedLanguage = language;
        ttsService.setLanguage(language);
        logger.logWithTimestamp("AAA loadSetting set language - $_selectedLanguage");
      }

      if (voiceIdentifier != null) {
        _selectedVoice = voiceIdentifier;
        Map<String, String>? voiceDetails = _voiceMap[voiceIdentifier];
        if (voiceDetails != null) {
          ttsService.setVoice(voiceDetails);
          logger.logWithTimestamp("AAA loadSetting set voice to TTS: $voiceDetails");
        }
      }
    } catch (e) {
      logger.logWithTimestamp("Error in processing voices: $e");
      // エラー処理をここに追加
    }
  }

  Future<void> _loadLanguages() async {
    var languages = await ttsService.getLanguages();
    if (languages != null) {
      setState(() {
        _languages = List<String>.from(languages)
            .where((lang) =>
                    lang.startsWith('en-') || // 英語
                    lang.startsWith('ja-') || // 日本語
                    lang.startsWith('zh-') || // 中国語
                    lang.startsWith('es-') || // スペイン語
                    lang.startsWith('de-') || // ドイツ語
                    lang.startsWith('th-') || // タイ語
                    lang.startsWith('vi-') || // ベトナム語
                    lang.startsWith('pt-') || // フランス語
                    lang.startsWith('fr-') || // フランス語
                    lang.startsWith('ko-') //韓国語
                )
            .toList();
      });
    }
  }

  Future<void> _chooseFile() async {
    _videoController?.dispose();
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
      );

      if (result != null) {
        setState(() async {
          _selectedFilePath = result.files.first.path;
          _selectedFileName = result.files.first.name;

          final file = File(_selectedFilePath!);
          int fileSize = await file.length(); // ファイルサイズをバイト単位で取得

          logger.logWithTimestamp("AAA _selectedFilePath: $_selectedFilePath _selectedFileName: $_selectedFileName ファイルサイズ: ${fileSize / (1024 * 1024)} MB");

          if (_selectedFileName!.endsWith('mp4') || _selectedFileName!.endsWith('mov')) {
            _videoController = VideoPlayerController.file(File(_selectedFilePath!))
              ..initialize().then((_) {
                setState(() {});
              });
          } else {
            _videoController?.dispose();
            _videoController = null;
          }
        });
      } else {
        print('File selection canceled');
      }
    } catch (e) {
      print('Failed to pick file: $e');
    }
  }

  void _clearSelectedFile() {
    setState(() {
      _selectedFilePath = null;
      _selectedFileName = null;
      _videoController?.dispose();
      _videoController = null;
    });
  }

  Future<void> _loadVoices() async {
    logger.logWithTimestamp("AAA _loadVoices start");
    var voices = await ttsService.getVoices();
    logger.logWithTimestamp("AAA _loadVoices 1");
    if (voices != null) {
      logger.logWithTimestamp("AAA _loadVoices 2");
      try {
        List<Map<String, String>> formattedVoices = voices.map<Map<String, String>>((voice) {
          return {
            "name": voice["name"].toString(),
            "locale": voice["locale"].toString(),
            // identifier が null なので、name と locale を使って代わりに一意なIDを生成
            "uniqueKey": "${voice["name"]}-${voice["locale"]}",
          };
        }).toList();
        logger.logWithTimestamp("AAA _loadVoices 3");
        setState(() {
          _voices = formattedVoices;
          _voiceMap = {for (var voice in _voices) voice['uniqueKey']!: voice.map<String, String>((key, value) => MapEntry(key, value.toString()))};
        });
        logger.logWithTimestamp("AAA _loadVoices - voice list: $_voices");
        logger.logWithTimestamp("AAA _loadVoices 4");
      } catch (e) {
        logger.logWithTimestamp('Error parsing voices: $e');
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
    } else if (microphoneStatus.isPermanentlyDenied) {
      print("Microphone permission is permanently denied.");
      // 設定画面にユーザーを誘導
      _showSettingsDialog();
    } else {
      print("Permissions not granted $microphoneStatus $storageStatus");
    }
  }

// 設定画面に誘導するダイアログ
  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text("マイクのアクセスが拒否されています"),
        content: Text("アプリが正しく動作するためには、マイクのアクセス許可が必要です。設定画面で許可を与えてください。"),
        actions: <Widget>[
          TextButton(
            child: Text("キャンセル"),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
          TextButton(
            child: Text("設定に移動"),
            onPressed: () {
              openAppSettings(); // 設定画面を開く
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _initializeRecorder() async {
    final session = await audio_session.AudioSession.instance;
    await session.configure(audio_session.AudioSessionConfiguration(
      avAudioSessionCategory: audio_session.AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions: audio_session.AVAudioSessionCategoryOptions.allowBluetooth | audio_session.AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode: audio_session.AVAudioSessionMode.spokenAudio,
      avAudioSessionRouteSharingPolicy: audio_session.AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions: audio_session.AVAudioSessionSetActiveOptions.none,
      androidAudioAttributes: const audio_session.AndroidAudioAttributes(
        contentType: audio_session.AndroidAudioContentType.speech,
        flags: audio_session.AndroidAudioFlags.none,
        usage: audio_session.AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: audio_session.AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));
    await _recorder.openRecorder();
    _recorder.setSubscriptionDuration(Duration(milliseconds: 100)); // 100ミリ秒ごとに監視
  }

  Future<void> _startRecording() async {
    int silenceDuration = 0;
    int lasttimeduration = 0;
    bool waitspeak = true;
    _initializeRecorder();
    logger.logWithTimestamp("AAA    _startRecording 1");
    Directory appDirectory = await getApplicationDocumentsDirectory();
    filePath = '${appDirectory.path}/${DateTime.now().millisecondsSinceEpoch}.aac';
    logger.logWithTimestamp("AAA    _startRecording 2 filePath $filePath");

    if (await Permission.microphone.isGranted) {
      _recordingCompleter = Completer<void>();
      try {
        await _recorder.startRecorder(toFile: filePath, codec: Codec.aacADTS);
        logger.logWithTimestamp("Recorder started successfully");
      } catch (e) {
        logger.logWithTimestamp("Error while starting recorder: $e");
      }

      _recorderSubscription = _recorder.onProgress!.listen((e) {
        logger.logWithTimestamp("AAA    _startRecording e.decibels ${e.decibels} e.duration.inMilliseconds ${e.duration.inMilliseconds} lasttimeduration $lasttimeduration waitspeak $waitspeak");
        if (e != null && e.decibels != null && e.decibels! > 30) {
          waitspeak = false;
          lasttimeduration = e.duration.inMilliseconds;
        } else {
          if (!waitspeak) {
            silenceDuration = e.duration.inMilliseconds - lasttimeduration;
            if (silenceDuration >= silenceThreshold) {
              _stopRecording();
            }
          }
        }
      });
      logger.logWithTimestamp("AAA    _startRecording 3");
      setState(() {
        isRecording = true;
      });

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

    if (filePath != null) {
      final file = File(filePath!);
      if (await file.exists()) {
        logger.logWithTimestamp("Recording file exists at $filePath");
      } else {
        logger.logWithTimestamp("Recording file does not exist at $filePath");
      }

      if (await file.exists()) {
        print('Recording saved at $filePath');
        print('File size: ${await file.length()} bytes');
      } else {
        print('Recording file does not exist at $filePath');
      }
    }
  }

  Future<void> _playRecording() async {
    logger.logWithTimestamp("AAA _playRecording 1 filePath $filePath");
    if (filePath != null) {
      Completer<void> completer = Completer<void>();

      await _player.setVolume(1.0);
      await _player.startPlayer(
        fromURI: filePath,
        whenFinished: () {
          logger.logWithTimestamp("AAA _playRecording Playback Finished");
          setState(() {
            isPlaying = false;
          });
          completer.complete();
        },
      );
      setState(() {
        isPlaying = true;
      });

      await completer.future;
    } else {
      print('No recording found!');
    }
  }

  Future<void> _speakAndRecord() async {
    logger.logWithTimestamp("AAA _speakAndRecord start");
    if (_speak1Checked) {
      setState(() {
        isSpeaking = true;
        isRecording = false;
        isPlaying = false;
      });
      logger.logWithTimestamp("AAA _speakAndRecord before speaksum");
      await speaksum();
      logger.logWithTimestamp("AAA _speakAndRecord after speaksum");
    }
    if (!inLoop) {
      setState(() {
        isSpeaking = false;
        isRecording = false;
        isPlaying = false;
      });
      return;
    }
    if (_recordChecked) {
      logger.logWithTimestamp("AAA _speakAndRecord 1.2");
      logger.logWithTimestamp("AAA _speakAndRecord 2");
      await Future.delayed(Duration(milliseconds: 100));

      platform.invokeMethod('playBeepng');
      await Future.delayed(Duration(milliseconds: 100));
      setState(() {
        isSpeaking = false;
        isRecording = true;
        isPlaying = false;
      });
      await _startRecording();
    }
    if (!inLoop) {
      setState(() {
        isSpeaking = false;
        isRecording = false;
        isPlaying = false;
      });
      return;
    }
    if (_speak2Checked) {
      setState(() {
        isSpeaking = true;
        isRecording = false;
        isPlaying = false;
      });
      ttsService.speak2nd = true;
      await speaksum();
    }
    if (!inLoop) {
      setState(() {
        isSpeaking = false;
        isRecording = false;
        isPlaying = false;
      });
      return;
    }
    if (_playChecked) {
      setState(() {
        isSpeaking = false;
        isRecording = false;
        isPlaying = true;
      });
      logger.logWithTimestamp("AAA _speakAndRecord 3");
      await Future.delayed(Duration(seconds: 1));
      logger.logWithTimestamp("AAA _speakAndRecord 4");
      logger.logWithTimestamp("AAA _speakAndRecord 5");
      await _playRecording();
    }

    setState(() {
      isSpeaking = false;
      isRecording = false;
      isPlaying = false;
    });
    logger.logWithTimestamp("AAA _speakAndRecord 6");
  }

  Future<void> speaksum() async {
    String text = textController.text;
    String? locale = _selectedLanguage;
    _speedset = false;
    logger.logWithTimestamp("AAA speaksum started");

    if (_selectedFilePath != null) {
      logger.logWithTimestamp("AAA speaksum - Playing selected file _selectedFileName $_selectedFileName");

      if (_selectedFileName!.endsWith('mp4') || _selectedFileName!.endsWith('mov')) {
        _videoController = VideoPlayerController.file(File(_selectedFilePath!));

        await _videoController!.initialize();

        if (_videoController!.value.isInitialized) {
          Completer<void> completer = Completer<void>();

          _videoController!.addListener(() {
            if (!_videoController!.value.isPlaying && _videoController!.value.position == _videoController!.value.duration) {
              logger.logWithTimestamp("AAA speaksum - calling completer.complete()");
              completer.complete();
            }

            if (_videoController!.value.isPlaying) {
              _speedvid = _speed * 2;
              _videoController!.setPlaybackSpeed(_speedvid);
              logger.logWithTimestamp("_speedset $_speedset _speedvid $_speedvid ${_videoController!.value.playbackSpeed}");
            }
          });

          print("Playback speed before play: ${_videoController!.value.playbackSpeed}");
          await _videoController!.play();

          print("Playback speed after play: ${_videoController!.value.playbackSpeed}");

          await completer.future;

          logger.logWithTimestamp("AAA speaksum - Video playback completed");
        } else {
          logger.logWithTimestamp("AAA speaksum - VideoController not initialized");
        }
      } else if (_selectedFileName!.endsWith('mp3')) {
        logger.logWithTimestamp("AAA speaksum - Attempting to play MP3");
        try {
          AudioPlayer audioPlayer = AudioPlayer();
          await audioPlayer.play(DeviceFileSource(_selectedFilePath!));

          await audioPlayer.onPlayerComplete.first;
          logger.logWithTimestamp("AAA speaksum - MP3 playback completed");
        } catch (e) {
          logger.logWithTimestamp("AAA speaksum - Error during MP3 playback: $e");
        }
      } else {
        logger.logWithTimestamp("AAA speaksum - Attempting to play audio");
        try {
          AudioPlayer audioPlayer = AudioPlayer();
          await audioPlayer.play(DeviceFileSource(_selectedFilePath!));
          logger.logWithTimestamp("AAA speaksum - Audio playback completed");
        } catch (e) {
          logger.logWithTimestamp("AAA speaksum - Error during audio playback: $e");
        }
      }
    } else {
      logger.logWithTimestamp("AAA speaksum 1");

      ttsService.isSpeaking = true;
      await ttsService.setVolume(0.001);
      await ttsService.speak("h");
      await ttsService.waitForCompletion();
      logger.logWithTimestamp("AAA speaksum 1.1");
      await ttsService.setVolume(1.0);
      ttsService.isSpeaking = true;
      await ttsService.speakNext();
      await ttsService.waitForCompletion();

      setState(() {});
    }
  }

  void extractAndSetLanguage() {
    // textController.text から (LANG:en-US) の形式の文字列を探す
    RegExp regExp = RegExp(r'\(LANG:([a-zA-Z\-]+)\)');
    RegExpMatch? match = regExp.firstMatch(textController.text);

    // マッチが見つかった場合、その中の言語コードを _selectedLanguage に代入
    if (match != null) {
      _selectedLanguage = match.group(1); // "en-US" の部分を抽出
      logger.logWithTimestamp("Extracted language: $_selectedLanguage");
    } else {
      logger.logWithTimestamp("No language code found");
    }

    ttsService.setLanguage(_selectedLanguage!);

    // 新しい言語に応じて声の一覧をロード
    _loadVoices().then((_) {
      logger.logWithTimestamp("AAA _selectedLanguage _loadVoices finished");

      // firstWhereのorElseで空のMap<String, String>を返すように修正
      var newVoice = _voices.firstWhere(
        (voice) => voice['locale']!.startsWith(_selectedLanguage),
        orElse: () => <String, String>{}, // 空のMap<String, String>を返す
      );

      logger.logWithTimestamp("AAA _selectedLanguage newVoice $newVoice");

      if (newVoice.isNotEmpty) {
        // identifier が null か確認し、null であればデフォルトの identifier を設定
        if (newVoice['identifier'] != null && newVoice['identifier']!.isNotEmpty) {
          setState(() {
            _selectedVoice = newVoice['identifier'];
            logger.logWithTimestamp("AAA _selectedVoice updated to $_selectedVoice");
          });
        } else {
          // identifier が null または空の場合、デフォルト値を設定
          setState(() {
            _selectedVoice = "${newVoice['name']}-${newVoice['locale']}"; // デフォルトの identifier を設定
            logger.logWithTimestamp("AAA newVoice['identifier'] is null or empty, setting _selectedVoice to default $_selectedVoice");
          });
        }
      } else {
        setState(() {
          _selectedVoice = null;
          logger.logWithTimestamp("AAA _selectedVoice set to null");
        });
      }
    });
  }

  Future<void> _startflash() async {
    extractAndSetLanguage();
    ttsService.chosentext = "";
    if (_selectedLanguage != null && _selectedVoice != null) {
      saveSettings(_selectedLanguage!, _selectedVoice!);
    }

    inflash = true;
    String question = "";

    _textList = textController.text.split('/').map((t) => t.trim()).toList(); // "/"で分割し、トリムしてリストに格納

    Random random = Random(); // Randomインスタンスを作成

    while (inflash) {
      logger.logWithTimestamp("AAA in _startflash $question"); // 実際のアプリケーションではここに何かしらの処理が入る
      nextCompleter = Completer<void>();

      // リストからランダムに選択
      if (_textList.isNotEmpty) {
        selectedindex = random.nextInt(_textList.length);
        String selectedText = _textList[selectedindex];
        // 選択した文字列から[]内のテキストを抜き出す
        RegExp regExp = RegExp(r'\[(.*?)\]');
        var matches = regExp.allMatches(selectedText);
        if (matches.isNotEmpty) {
          // 最初に見つかったマッチの中身をquestion変数に格納
          String question = matches.first.group(1)!;
          displaytext = question;
          setState(() {});

          // ユーザーの答え入力
          logger.logWithTimestamp("AAA in _startflash loop $question");
          if (_recordChecked) {
            await Future.delayed(Duration(milliseconds: 100));
            if (Platform.isIOS) {
              await Future.delayed(Duration(milliseconds: 100));
              platform.invokeMethod('playBeepng');
            }
            setState(() {});
            //await _startRecording();
            _recogtext = "";
            displaytext2 = "Tell the answer!";

            while (!gonext && _recogtext == "") {
              logger.logWithTimestamp("AAA in _startflash _listen loop1 1　recogtext $_recogtext");
              await Future.delayed(Duration(milliseconds: 200));
              _recognitionCompleter = Completer<void>();
              await _listen();
              await _recognitionCompleter.future;
              logger.logWithTimestamp("AAA in _startflash _listen loop1 2 recogtext $_recogtext");
            }
            gonext = false;
            logger.logWithTimestamp("AAA in _startflash _listen end1");
          } else {
            await nextCompleter?.future;
          }
          logger.logWithTimestamp("AAA in _startflash showing answer");
          answershowing = true;
          nextCompleter = Completer<void>();
          displaytext = "$selectedText ";
          displaytext2 = "Detected: $_recogtext";
          setState(() {});
          if (_speak1Checked) {
            String matches = displaytext.replaceAll(RegExp(r'\(.*?\)'), '');
            matches = matches.replaceAll(RegExp(r'\[.*?\]'), '');
            logger.logWithTimestamp("AAA in _startflash speak $matches"); // 実際のアプリケーションではここに何かしらの処理が入る

            await ttsService.speak(matches);
            await ttsService.waitForCompletion();
          }
        }
      }
      //await Future.delayed(Duration(seconds: 1)); // 1秒待機

      if (_recordChecked) {
        await Future.delayed(Duration(milliseconds: 100));
        if (Platform.isIOS) {
          await Future.delayed(Duration(milliseconds: 100));
          platform.invokeMethod('playBeepng');
        }
        setState(() {});
        //await _startRecording();
        _recognitionCompleter = Completer<void>();
        _recogtext = "";
        String nextword = "next";
        String skipword = "skip";

        if (_selectedLanguage!.startsWith('en-')) {
          nextword = "next";
          skipword = "skip";
        } else if (_selectedLanguage!.startsWith('ja-')) {
          nextword = "次";
          skipword = "スキップ";
        } else if (_selectedLanguage!.startsWith('zh-')) {
          nextword = "下一个"; // 中国語 (簡体字) - "xià yī bù"
          skipword = "跳过";
        } else if (_selectedLanguage!.startsWith('es-')) {
          nextword = "siguiente"; // スペイン語
          skipword = "Saltar";
        } else if (_selectedLanguage!.startsWith('ko-')) {
          nextword = "다음"; // 韓国語 - "다음" (da-eum)
          skipword = "건너뛰기";
        } else if (_selectedLanguage!.startsWith('fr-')) {
          nextword = "suivant"; // フランス語
          skipword = "Sauter";
        } else if (_selectedLanguage!.startsWith('de-')) {
          nextword = "weiter"; // ドイツ語
          skipword = "Überspringen";
        } else if (_selectedLanguage!.startsWith('pt-')) {
          nextword = "próximo"; // ポルトガル語
          skipword = "Pular";
        } else if (_selectedLanguage!.startsWith('th-')) {
          nextword = "ถัดไป"; // タイ語 - "thạ̀tpị"
          skipword = "ข้าม";
        } else if (_selectedLanguage!.startsWith('vi-')) {
          nextword = "tiếp theo"; // ベトナム語
          skipword = "Bỏ qua";
        } else {
          nextword = "next"; // デフォルトは英語にする場合
        }
        displaytext2 = "$displaytext2 \n To go next, say \"$nextword\". \nTo skip it, say \"$skipword\".";
        while (!gonext && ((_recogtext.toLowerCase() != skipword.toLowerCase() || _recogtext.toLowerCase() != nextword.toLowerCase()) && inflash)) {
          logger.logWithTimestamp("AAA in _startflash loop2 recogtext  $_recogtext ");

          await Future.delayed(Duration(milliseconds: 200));
          _recognitionCompleter = Completer<void>();
          await _listen();
          await _recognitionCompleter.future;
          if (_recogtext != "") {
            displaytext2 = "$_recogtext \n To go next, say \"$nextword\". \nTo skip it, say \"$skipword\".";
          }

          setState(() {});
          logger.logWithTimestamp("AAA in _startflash loop2 recogtext 2 $_recogtext ");
        }
        if (_recogtext.toLowerCase() != skipword.toLowerCase()) {
          skipflash();
        }
        gonext = false;
        logger.logWithTimestamp("AAA in _startflash _listen end2");
      } else {
        await nextCompleter?.future;
      }

      displaytext2 = "";
      answershowing = false;
    }
  }

  Future<void> skipflash() async {
    if (_textList.length > 2 && selectedindex >= 0 && selectedindex < _textList.length) {
      // 残り2個以下は削除しない
      _textList.removeAt(selectedindex);
    }
    gonext = true;
    if (!nextCompleter!.isCompleted) {
      nextCompleter?.complete();
    }
  }

  Future<void> _startLoop() async {
    pausing = false;
    inLoop = true;
    displaytext = "";
    answershowing = false;
    inflash = false;

    if (textedited) {
      ttsService.saveText(textController.text);
      textedited = false;
    }
    ttsService.setText(textController.text);
    if (_selectedLanguage != null && _selectedVoice != null) {
      saveSettings(_selectedLanguage!, _selectedVoice!);
    }

    while (inLoop) {
      await _speakAndRecord();
      await Future.delayed(Duration(seconds: 1));
    }
  }

  Future<void> setting() async {}
  Future<void> editSentence() async {
    List<String> sentences = await ttsService.loadSavedTexts();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Saved Sentences'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (sentences.isNotEmpty)
                    ...sentences.map((sentence) {
                      return ListTile(
                        title: Text(sentence),
                        trailing: IconButton(
                          icon: Icon(Icons.close),
                          onPressed: () async {
                            await _removeSentence(sentence);
                            setState(() {
                              sentences.remove(sentence);
                            });
                          },
                        ),
                      );
                    }).toList(),
                  if (sentences.isEmpty) Text("No saved sentences"),
                ],
              );
            },
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // ダイアログを閉じる
              },
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _removeSentence(String sentence) async {
    List<String> sentences = await ttsService.loadSavedTexts();
    sentences.remove(sentence);

    final filePath = await ttsService.getLocalFilePath();
    final file = File(filePath);

    if (sentences.isNotEmpty) {
      await file.writeAsString(sentences.join('\n'));
    } else {
      await file.delete();
    }
  }

  void skipback(bool isskip) {
    ttsService.skipback(isskip);
    setState(() {});
  }

  void _flashNext(bool ispause) {
    logger.logWithTimestamp("AAA _flashNext called");
    ttsService.stopread(false);
    _speech.stop();
    _recognitionCompleter.complete(); // 認識が完了したことをCompleterに通知

    if (_recorder.isRecording) {
      _recorder.stopRecorder();
      _recordingCompleter?.complete();
      setState(() {
        isRecording = false;
      });
    }

    if (_player.isPlaying) {
      _player.stopPlayer();
      setState(() {
        isPlaying = false;
      });
    }
    gonext = true;
    if (!nextCompleter!.isCompleted) {
      nextCompleter?.complete();
    }
  }

  void _stopLoop(bool ispause) {
    answershowing = false;
    logger.logWithTimestamp("AAA _stopLoop called");
    if (ispause)
      pausing = true;
    else
      pausing = false;
    _videoController?.pause();
    ttsService.stopread(ispause);
    _speedset = false;

    if (_recorder.isRecording) {
      _recorder.stopRecorder();
      setState(() {
        isRecording = false;
      });
    }

    if (_player.isPlaying) {
      _player.stopPlayer();
      setState(() {
        isPlaying = false;
      });
    }

    // タイマーがある場合はキャンセル
    _timeoutTimer?.cancel();

    // リスニングを停止
    if (_isListening) {
      _speech.stop();
      setState(() {
        _isListening = false;
      });
    }

    setState(() {
      inLoop = false;
      inflash = false;
      isSpeaking = false;
      isRecording = false;
      isPlaying = false;
    });
  }

  @override
  void dispose() {
    textController.dispose();
    // アプリ終了時にWake Lockを無効化
    WakelockPlus.disable();
    _videoController?.dispose();
    _recorder.closeRecorder();
    _player.closePlayer();
    _recorderSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text('Repeatia'),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            print('Screen height: ${constraints.maxHeight} in builder _selectedFilePath $_selectedFilePath');

            bool showImage = constraints.maxHeight > 444;

            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    if (showImage && _selectedFilePath == null && !inLoop && !pausing && !inflash)
                      SizedBox(
                        width: 3 * MediaQuery.of(context).devicePixelRatio * 22.54,
                        height: 3 * MediaQuery.of(context).devicePixelRatio * 22.54,
                        child: Image.asset('assets/repeatiaicon.webp'),
                      ),
                    if (_selectedFilePath == null && (inLoop || pausing || inflash))
                      Text(
                        "${ttsService.chosentext} $displaytext", // テキストを表示
                        style: TextStyle(
                          fontSize: 18.0, // テキストのサイズを調整
                          color: Colors.black, // 必要に応じて色も変更
                        ),
                      ),
                    if (_selectedFilePath == null && (inLoop || pausing || inflash))
                      Text(
                        "$displaytext2", // テキストを表示
                        style: TextStyle(
                          fontSize: 18.0, // テキストのサイズを調整
                          color: Colors.black, // 必要に応じて色も変更
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.volume_up, color: isSpeaking ? Colors.blue : Colors.grey),
                        Icon(Icons.mic, color: isRecording ? Colors.red : Colors.grey),
                        Icon(Icons.play_arrow, color: isPlaying ? Colors.green : Colors.grey),
                      ],
                    ),
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
                        logger.logWithTimestamp("AAA _selectedLanguage newValue $newValue");
                        if (newValue != null) {
                          setState(() {
                            _selectedLanguage = newValue;
                            ttsService.setLanguage(newValue);
                          });

                          // 新しい言語に応じて声の一覧をロード
                          _loadVoices().then((_) {
                            logger.logWithTimestamp("AAA _selectedLanguage _loadVoices finished");

                            // firstWhereのorElseで空のMap<String, String>を返すように修正
                            var newVoice = _voices.firstWhere(
                              (voice) => voice['locale']!.startsWith(newValue),
                              orElse: () => <String, String>{}, // 空のMap<String, String>を返す
                            );

                            logger.logWithTimestamp("AAA _selectedLanguage newVoice $newVoice");

                            if (newVoice.isNotEmpty) {
                              // identifier が null か確認し、null であればデフォルトの identifier を設定
                              if (newVoice['identifier'] != null && newVoice['identifier']!.isNotEmpty) {
                                setState(() {
                                  _selectedVoice = newVoice['identifier'];
                                  logger.logWithTimestamp("AAA _selectedVoice updated to $_selectedVoice");
                                });
                              } else {
                                // identifier が null または空の場合、デフォルト値を設定
                                setState(() {
                                  _selectedVoice = "${newVoice['name']}-${newVoice['locale']}"; // デフォルトの identifier を設定
                                  logger.logWithTimestamp("AAA newVoice['identifier'] is null or empty, setting _selectedVoice to default $_selectedVoice");
                                });
                              }
                            } else {
                              setState(() {
                                _selectedVoice = null;
                                logger.logWithTimestamp("AAA _selectedVoice set to null");
                              });
                            }
                          });
                        }
                      },
                    ),
                    if (_voices.isNotEmpty)
                      DropdownButton<String>(
                        value: _selectedVoice,
                        hint: Text("Select Voice"),
                        items: _voices
                            .where((voice) => voice['locale'] == _selectedLanguage) // _selectedLanguage に一致するものだけを表示
                            .map((Map<String, dynamic> voice) {
                          return DropdownMenuItem<String>(
                            value: voice['identifier'] != null && voice['identifier']!.isNotEmpty ? voice['identifier'] : "${voice['name']}-${voice['locale']}", // identifier がない場合、デフォルト値を使用
                            child: Text("${voice['name']} (${voice['locale']})"),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _selectedVoice = newValue;
                            });

                            var selectedVoice = _voiceMap[newValue];
                            if (selectedVoice != null) {
                              ttsService.setVoice(selectedVoice).then((_) {
                                print("Voice set successfully");
                              }).catchError((error) {
                                print("Error setting voice: $error");
                              });
                            }
                          }
                        },
                      ),
                    if (_selectedFilePath == null)
                      Slider(
                        min: 0.1,
                        max: 1.0,
                        divisions: 10,
                        label: 'Pitch $_pitch',
                        value: _pitch,
                        onChanged: (double value) {
                          setState(() {
                            _pitch = value;
                            ttsService.setPitch(_pitch);
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
                          ttsService.setSpeechRate(_speed);
                        });
                      },
                    ),
                    if (_selectedFilePath == null && !inflash && !inLoop)
                      TextField(
                        controller: textController,
                        decoration: InputDecoration(
                          labelText: 'Enter text or choose from list',
                          border: OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(Icons.clear),
                            onPressed: () {
                              // クリアボタンを押したときにテキストをクリア
                              textController.clear();
                            },
                          ),
                        ),
                        maxLines: 3, // 3行に固定
                        minLines: 3, // 3行に固定
                        keyboardType: TextInputType.multiline,

                        onChanged: (text) {
                          setState(() {
                            textedited = true; // テキストが変更されたらtrueに設定
                          });
                        },
                      ),
                    if (!_sentences.isNotEmpty) Text('Loading sentences.', style: TextStyle(fontSize: 10)),
                    if (_sentences.isNotEmpty && _selectedFilePath == null && !inflash && !inLoop)
                      DropdownButton<String>(
                        value: _selectedSentence,
                        hint: Text("Select a sentence"),
                        items: _sentences.map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(
                              value,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          textedited = false;
                          setState(() {
                            _selectedSentence = newValue;
                            textController.text = newValue ?? '';
                            extractAndSetLanguage();
                          });
                        },
                        isExpanded: true,
                      ),
                    if (_selectedFilePath == null && !inflash && !inLoop)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: _chooseFile,
                            child: Text('Choose File'),
                          ),
                        ],
                      ),
                    Column(
                      children: [
                        if (_selectedFilePath != null && !inflash && !inLoop)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _selectedFileName!,
                                style: TextStyle(fontSize: 16),
                              ),
                              IconButton(
                                icon: Icon(Icons.close),
                                onPressed: _clearSelectedFile,
                              ),
                            ],
                          ),
                        SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if ((pausing || !inLoop) && !inflash)
                              ElevatedButton(
                                onPressed: _startLoop,
                                child: Text('Start'),
                              ),
                            SizedBox(width: 20),
                            if ((pausing || !inLoop) && !inflash)
                              ElevatedButton(
                                onPressed: _startflash,
                                child: Text('Flashcards'),
                              ),
                            //SizedBox(width: 20),
                            if (inLoop || inflash) // pause が true の場合、ボタンを表示しない
                              ElevatedButton(
                                onPressed: () => _stopLoop(false), // 無名関数を使って遅延評価する
                                child: Text('Stop'),
                              ),
                            //SizedBox(width: 20),
                            if (!pausing && inLoop) // pause が true の場合、ボタンを表示しない
                              ElevatedButton(
                                onPressed: () => _stopLoop(true), // 無名関数を使って遅延評価する
                                child: Text('Pause'),
                              ),
                            if (inflash) // pause が true の場合、ボタンを表示しない
                              ElevatedButton(
                                onPressed: () => _flashNext(true),
                                child: Text('Next'),
                              ),
                            if (answershowing) // pause が true の場合、ボタンを表示しない
                              ElevatedButton(
                                onPressed: () => skipflash(),
                                child: Text('Skip'),
                              ),
                            if (_selectedFilePath == null && (inLoop || pausing)) // pause が true の場合、ボタンを表示しない
                              ElevatedButton(
                                onPressed: () => skipback(false), // 無名関数を使って遅延評価する
                                child: Text('<-'),
                              ),
                            if (_selectedFilePath == null && (inLoop || pausing)) // pause が true の場合、ボタンを表示しない
                              ElevatedButton(
                                onPressed: () => skipback(true), // 無名関数を使って遅延評価する
                                child: Text('->'),
                              ),
                          ],
                        ),
                        if (_videoController != null && _videoController!.value.isInitialized && _selectedFilePath != null)
                          AspectRatio(
                            aspectRatio: _videoController!.value.aspectRatio,
                            child: VideoPlayer(_videoController!),
                          ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: _speak1Checked,
                              onChanged: (bool? value) {
                                setState(() {
                                  _speak1Checked = value ?? false;
                                });
                              },
                            ),
                            Text('Speak1', style: TextStyle(fontSize: 10)),
                          ],
                        ),
                        Row(
                          children: [
                            Checkbox(
                              value: _recordChecked,
                              onChanged: (bool? value) {
                                setState(() {
                                  _recordChecked = value ?? false;
                                });
                              },
                            ),
                            Text('Record', style: TextStyle(fontSize: 10)),
                          ],
                        ),
                        Row(
                          children: [
                            Checkbox(
                              value: _speak2Checked,
                              onChanged: (bool? value) {
                                setState(() {
                                  _speak2Checked = value ?? false;
                                });
                              },
                            ),
                            Text('Speak2', style: TextStyle(fontSize: 10)),
                          ],
                        ),
                        Row(
                          children: [
                            Checkbox(
                              value: _playChecked,
                              onChanged: (bool? value) {
                                setState(() {
                                  _playChecked = value ?? false;
                                });
                              },
                            ),
                            Text('Play', style: TextStyle(fontSize: 10)),
                          ],
                        ),
                      ],
                    ),
                    if (!inflash && !inLoop)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    title: Text('About'),
                                    content: Text('2024 Misota Michael All rights reserved. \n\n The copyright for the sample text, "Comma Gets a Cure," is as follows:   © Copyright 2000 Douglas N. Honorof, Jill McCullough & Barbara Somerville. All rights reserved.'),
                                    actions: [
                                      ElevatedButton(
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                        },
                                        child: Text('OK'),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                            child: Text('About'),
                          ),
                          SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: () {
                              setting();
                            },
                            child: Text('Setting'),
                          ),
                          SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: () {
                              editSentence();
                            },
                            child: Text('Edit sentences'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        ));
  }
}
