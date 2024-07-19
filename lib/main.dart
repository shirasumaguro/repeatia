import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Text to Speech',
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
  final TextEditingController textController = TextEditingController();
  final TextEditingController localeController = TextEditingController();
  List<String> languages = [];

  Future<void> _speak() async {
    String text = textController.text;
    String locale = localeController.text;

    if (locale.isNotEmpty) {
      await flutterTts.setLanguage(locale);
    }
    await flutterTts.speak(text);
  }

  @override
  void initState() {
    super.initState();
    _getLanguages();
  }

  Future<void> _getLanguages() async {
    List<dynamic> langs = await flutterTts.getLanguages;
    setState(() {
      languages = langs.cast<String>();
    });
    print("Available languages: $languages");
  }

  @override
  void dispose() {
    textController.dispose();
    localeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Text to Speech'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            TextField(
              controller: textController,
              decoration: InputDecoration(
                labelText: 'Enter text',
              ),
            ),
            TextField(
              controller: localeController,
              decoration: InputDecoration(
                labelText: 'Enter locale code (e.g., en-US)',
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _speak,
              child: Text('Speak'),
            ),
          ],
        ),
      ),
    );
  }
}
