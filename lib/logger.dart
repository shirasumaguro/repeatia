import 'package:path_provider/path_provider.dart';
import 'dart:io';

class Logger {
  String? _logFilePath;

  final List<String> _logMessages = [];

  // ログファイルのパスを初期化
  Future<void> initializeLogFilePath() async {
    if (_logFilePath == null || _logFilePath!.isEmpty) {
      final directory = await getApplicationDocumentsDirectory();
      _logFilePath = '${directory.path}/logfile.txt';
    }
  }

  void logWithTimestamp(String message) {
    var now = DateTime.now();
    String timestampedMessage = '$now: $message';
    print(timestampedMessage); // コンソールに出力
    _logMessages.add(timestampedMessage); // ログリストに追加
    if (_logMessages.length > 1000) {
      _logMessages.removeAt(0); // リストが1000行を超えたら最古のメッセージを削除
    }
    _writeLogsToFile(); // ファイルにログを書き出す
  }

  void _writeLogsToFile() {
    if (_logFilePath == null) {
      print("Log file path is not initialized yet.");
      return;
    }

    File logFile = File(_logFilePath!);
    logFile.writeAsStringSync(_logMessages.join('\n'), mode: FileMode.write); // ログファイルに書き込み
  }

  String? get logFilePath => _logFilePath;
}
