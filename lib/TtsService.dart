import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:convert';
import 'package:flutter_sound/flutter_sound.dart';

import 'package:audio_session/audio_session.dart' as audio_session;
//import 'package:audioplayers_platform_interface/src/api/audio_context.dart' as audioplayers;
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
//import 'package:just_audio/just_audio.dart';
import 'logger.dart';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart'; // 動画プレビューのために必要

class TtsService {
  final FlutterTts flutterTts = FlutterTts();
  bool isSpeaking = false;
  String currentText = "";
  String chosentext = "";
  bool skippedbyuser = false;
  bool firsttimestart = true;
  Logger logger = Logger();
  List<String> _sentences = [];
  SharedPreferences? prefs;
  bool speak2nd = false;
  String lastText = "";

  List<String> _textList = []; // テキストを保持するリスト
  int _currentIndex = 0; // 現在読み上げているテキストのインデックス

  // コールバック関数の型を定義
  Function(List<String>)? onSentencesLoaded;
  Function(String)? onTextChanged;

  // ファイル保存場所を取得
  Future<String> getLocalFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/saved_sentences.txt'; // ローカルファイル名
  }

  // ファイルからリストを読み込む関数
  Future<List<String>> loadSavedTexts() async {
    final filePath = await getLocalFilePath();
    final file = File(filePath);

    if (await file.exists()) {
      // ファイルが存在すれば内容を読み込んでリストとして返す
      return await file.readAsLines();
    } else {
      return [];
    }
  }

  Future<void> loadSentences() async {
    logger.logWithTimestamp("Start downloading sentences...");

    try {
      // ダウンロード開始
      String data = await _downloadSentencesFromUrl();
      logger.logWithTimestamp("Downloaded sentences: $data");

      // ダウンロードされたセンテンスを分割
      List<String> downloadedSentences = data.split('\n');
      logger.logWithTimestamp("Downloaded sentences after split: $downloadedSentences");

      // ローカルに保存されたセンテンスを取得
      List<String> savedSentences = await loadSavedTexts();
      logger.logWithTimestamp("Saved sentences from file: $savedSentences");

      // 重複のないようにダウンロードとローカルファイルからのセンテンスを結合
      _sentences = [...savedSentences, ...downloadedSentences.where((sentence) => !savedSentences.contains(sentence))];

      // コールバックを使ってデータを MyHomePageState に通知
      if (onSentencesLoaded != null) {
        onSentencesLoaded!(_sentences);
      }
      logger.logWithTimestamp("Final sentences in setState: $_sentences");
    } catch (e) {
      // ダウンロードが失敗した場合、ローカルファイルのセンテンスのみを使用
      logger.logWithTimestamp("Error downloading or processing sentences: $e");
      print("Error downloading sentences: $e");

      // ローカルに保存されたセンテンスを取得
      List<String> savedSentences = await loadSavedTexts();
      logger.logWithTimestamp("Using only saved sentences from file due to download error: $savedSentences");

      // ローカルファイルのセンテンスのみをセット
      _sentences = savedSentences;

      // コールバックを使ってデータを MyHomePageState に通知
      if (onSentencesLoaded != null) {
        onSentencesLoaded!(_sentences);
      }
    }
  }

  Future<void> loadSentencesFromFile() async {
    List<String> savedSentences = await loadSavedTexts();

    _sentences = savedSentences + _sentences; // ローカルファイルの内容をドロップダウンに追加
  }

  Future<String> _downloadSentencesFromUrl() async {
    // Google Driveのダウンロードリンクに変換
    final url = 'https://drive.google.com/uc?export=download&id=1j52PV5sPEGzN51-aVS80nFJol6lGu4Th';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      print("Downloaded file content: ${response.body}"); // ファイルの内容をログに出力

      return utf8.decode(response.bodyBytes); // UTF-8でデコード
      //return response.body; // テキストデータを返す
    } else {
      throw Exception('Failed to download sentences');
    }
  }

  // TtsService内の_addSentenceToDropdownを削除し、speakNextからも削除
  Future<void> speakNext() async {
    if (skippedbyuser || firsttimestart) {
      skippedbyuser = false;
      firsttimestart = false;
    } else
      _currentIndex = (_currentIndex + 1) % _textList.length;
    isSpeaking = true;
    if (_textList.isEmpty) {
      logger.logWithTimestamp("No text to speak.");
      return;
    }

    if (speak2nd) {
      chosentext = lastText;
      speak2nd = false;
    } else {
      // 現在のインデックスのテキストを読み上げ
      chosentext = _textList[_currentIndex];
    }
    // ここでコールバックを呼び出し、chosentextの変更を通知
    if (onTextChanged != null) {
      onTextChanged!(chosentext);
    }
    currentText = chosentext.replaceAll(RegExp(r'\(.*?\)'), '').trim();
    logger.logWithTimestamp("Speaking: $currentText");

    await speak(currentText);
    lastText = chosentext;
    await waitForCompletion();

    // インデックスを次に進める
  }

  // テキストを分割してリストに保存するメソッド
  void saveText(String text) {
    // テキストを保存
    saveTextToFile(text);

    // ドロップダウンリストに追加。重複チェック：既に存在する場合は追加しない
    if (!_sentences.contains(text)) {
      _sentences.insert(0, text); // リストの先頭に追加
    } else {
      logger.logWithTimestamp("Sentence already exists in the list.");
    }
  }

  // テキストを分割してリストに保存するメソッド
  void setText(String text) {
    _textList = text.split('/').map((t) => t.trim()).toList(); // "/"で分割し、トリムしてリストに格納
  }

  void stopread(bool ispause) {
    if (ispause)
      _currentIndex = _currentIndex - 1;
    else {
      _currentIndex = 0; // インデックスをリセット
      firsttimestart = true;
    }
//    isSpeaking = false

    flutterTts.stop().then((_) {
      logger.logWithTimestamp("TTS speaking forcibly stopped.");
    }).catchError((error) {
      logger.logWithTimestamp("Failed to stop TTS speaking: $error");
    });
  }

// ローカルにファイルとして保存する関数
  Future<void> saveTextToFile(String text) async {
    final filePath = await getLocalFilePath();
    final file = File(filePath);

    List<String> existingSentences = [];
    if (await file.exists()) {
      // 既存ファイルの内容を取得してリストに格納
      existingSentences = await file.readAsLines(encoding: utf8);
    }

    if (!existingSentences.contains(text)) {
      // 重複がなければファイルに追加
      await file.writeAsString('$text\n', mode: FileMode.append, encoding: utf8);
      logger.logWithTimestamp("Saved text to file: $text");
    } else {
      logger.logWithTimestamp("Text already exists in the file: $text");
    }
  }

  @override
  void initState() {
    print("AAA TtsService in initstate.");
  }

  TtsService() {
    logger.initializeLogFilePath();
    logger.logWithTimestamp("Logger initialized.");

    print("AAA TtsService constructor");
    loadSentencesFromFile(); // ローカルファイルから保存されたテキストをロード
    loadSentences(); // 追加: sentences.txtの読み込み

    logger.initializeLogFilePath();
    // イベントリスナーの設定
    flutterTts.setStartHandler(() {
      logger.logWithTimestamp("AAA TTS started isSpeaking $isSpeaking");
      isSpeaking = true;
    });

    flutterTts.setCompletionHandler(() {
      logger.logWithTimestamp("AAA TTS complete isSpeaking $isSpeaking");
      isSpeaking = false;
    });

    flutterTts.setErrorHandler((msg) {
      logger.logWithTimestamp("AAA TTS error: $msg isSpeaking $isSpeaking");
      isSpeaking = false;
      print("TTS error: $msg");
    });
  }

  Future<void> speak(String text) async {
    logger.logWithTimestamp("AAA TTS speak isSpeaking $isSpeaking text: $text");
    isSpeaking = true;
    logger.logWithTimestamp("AAA TTS speak isSpeaking 2 $isSpeaking");
    await flutterTts.speak(text);
    logger.logWithTimestamp("AAA TTS speak isSpeaking 3 $isSpeaking");
    await waitForCompletion();
    logger.logWithTimestamp("AAA TTS speak isSpeaking 4 $isSpeaking");
  }

  Future<void> setVolume(double volume) async {
    await flutterTts.setVolume(volume);
  }

  Future<void> setPitch(double pitch) async {
    await flutterTts.setPitch(pitch);
  }

  Future<void> setSpeechRate(double rate) async {
    await flutterTts.setSpeechRate(rate);
  }

  Future<void> setLanguage(String language) async {
    var setResult = await flutterTts.setLanguage(language);
    await prefs?.setString('language', language);
    print('Saved language setting: $language'); // 保存された言語設定を表示
    print('Set language result: $setResult'); // 言語設定結果を表示
  }

  Future<void> setVoice(Map<String, String> voice) async {
    var setResult = await flutterTts.setVoice(voice);
    String voiceJson = json.encode(voice);
    await prefs?.setString('voice', voiceJson);
    print('Saved voice setting: $voiceJson'); // 保存された音声設定を表示
    print('Set voice result: $setResult'); // 音声設定結果を表示
  }

  Future<List<dynamic>> getLanguages() async {
    return await flutterTts.getLanguages;
  }

  Future<List<dynamic>> getVoices() async {
    return await flutterTts.getVoices;
  }

  Future<void> awaitSpeakCompletion(bool awaitCompletion) async {
    await flutterTts.awaitSpeakCompletion(awaitCompletion);
  }

  void skipback(bool isskip) {
    logger.logWithTimestamp("AAA TTS skipback: 1 _currentIndex $_currentIndex _textList[_currentIndex] ${_textList[_currentIndex]}");
    skippedbyuser = true;
    if (isskip) {
      _currentIndex++;
      if (_currentIndex == _textList.length) _currentIndex = 0;
    } else {
      _currentIndex = _currentIndex - 1;
      if (_currentIndex == -1) _currentIndex = _textList.length;
    }
    chosentext = _textList[_currentIndex];
    logger.logWithTimestamp("AAA TTS skipback: 2 _currentIndex $_currentIndex _textList[_currentIndex] ${_textList[_currentIndex]}");
  }

  Future<void> waitForCompletion() async {
    logger.logWithTimestamp("AAA TTS waitForCompletion:  isSpeaking $isSpeaking");

    try {
      throw Exception('Stack trace test');
    } catch (e, stackTrace) {
      logger.logWithTimestamp("AAA TTS waitForCompletion stack trace: $stackTrace");
    }
    while (isSpeaking) {
      await Future.delayed(Duration(milliseconds: 500));
    }
  }
}
