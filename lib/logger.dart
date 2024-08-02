import 'package:path_provider/path_provider.dart';
import 'dart:io';

class Logger {
  late String _logFilePath;
  final List<String> _logMessages = [];

  Future<void> initializeLogFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    _logFilePath = '${directory.path}/logfile.txt'; // ドキュメントディレクトリにファイルを作成
    print("AAA initializeLogFilePath _logFilePath $_logFilePath");
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
    File logFile = File(_logFilePath);
    logFile.writeAsStringSync(_logMessages.join('\n'), mode: FileMode.write); // ログファイルに書き込み
  }

  String get logFilePath => _logFilePath;
}
