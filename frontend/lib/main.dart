import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf_text/pdf_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';

void main() => runApp(MetaPDF());

class MetaPDF extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "MetaPDF",
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      home: LibraryPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class LibraryPage extends StatefulWidget {
  @override
  _LibraryPageState createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<Map<String, String>> books = [];

  Future<void> pickPDF() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
      if (result != null && result.files.single.path != null) {
        PDFDoc pdfDoc = await PDFDoc.fromPath(result.files.single.path!);
        String text = await pdfDoc.text;
        setState(() {
          books.add({"title": result.files.single.name, "content": text});
        });
      }
    } catch (e) {
      debugPrint("PDF pick/read error: \$e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("PDF yüklenemedi: \$e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("MetaPDF"),
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.upload_file),
        onPressed: pickPDF,
      ),
      body: books.isEmpty
          ? Center(child: Text("Henüz kitap eklemedin."))
          : ListView.builder(
              itemCount: books.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(books[index]["title"]!),
                  trailing: Icon(Icons.arrow_forward_ios),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReaderPage(title: books[index]["title"]!, content: books[index]["content"]!))),
                );
              },
            ),
    );
  }
}

class ReaderPage extends StatefulWidget {
  final String title;
  final String content;
  ReaderPage({required this.title, required this.content});
  @override
  _ReaderPageState createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> with SingleTickerProviderStateMixin {
  final FlutterTts flutterTts = FlutterTts();
  final AudioPlayer audioPlayer = AudioPlayer();
  bool isReading = false;
  double voicePitch = 1.0;
  double voiceRate = 0.5;
  String summary = "";

  // Replace with your backend base URL
  final String backendBase = "https://your-backend.example.com";

  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(vsync: this, duration: Duration(seconds: 1))..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.6, end: 1.0).animate(_animationController);
  }

  Future<void> startLocalTts() async {
    try {
      await flutterTts.setLanguage("tr-TR");
      await flutterTts.setPitch(voicePitch);
      await flutterTts.setSpeechRate(voiceRate);
      setState(() => isReading = true);
      await flutterTts.speak(widget.content);
      flutterTts.setCompletionHandler(() => setState(() => isReading = false));
    } catch (e) {
      debugPrint("Local TTS error: \$e");
      setState(() => isReading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Seslendirme başlatılamadı.")));
    }
  }

  Future<void> requestAISummary() async {
    try {
      final resp = await http.post(Uri.parse('\$backendBase/summary'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"text": widget.content}));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        setState(() {
          summary = data['summary'] ?? "";
        });
      } else {
        setState(() {
          summary = "Özet alınamadı (sunucu hatası)";
        });
      }
    } catch (e) {
      debugPrint("Summary request error: \$e");
      setState(() {
        summary = "İstek başarısız: \$e";
      });
    }
  }

  Future<void> requestAIPlayAudio({String voiceStyle = 'narrator'}) async {
    try {
      final resp = await http.post(Uri.parse('\$backendBase/tts'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"text": widget.content, "voice": voiceStyle}));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final audioUrl = data['audio_url'];
        int result = await audioPlayer.play(audioUrl);
        if (result == 1) {
          setState(() => isReading = true);
          audioPlayer.onPlayerComplete.listen((event) {
            setState(() => isReading = false);
          });
        }
      } else {
        await startLocalTts();
      }
    } catch (e) {
      debugPrint("AI TTS error: \$e");
      await startLocalTts();
    }
  }

  Future<void> stopReading() async {
    try {
      await flutterTts.stop();
      await audioPlayer.stop();
    } catch (e) {
      debugPrint("Stop reading error: \$e");
    } finally {
      setState(() => isReading = false);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    flutterTts.stop();
    audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (isReading)
              Center(
                child: ScaleTransition(
                  scale: _animation,
                  child: Icon(Icons.graphic_eq, size: 60, color: Colors.deepPurple),
                ),
              ),
            SizedBox(height: 12),
            Text(widget.content, style: TextStyle(fontSize: 16)),
            SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: isReading ? stopReading : () => requestAIPlayAudio(voiceStyle: 'narrator'),
                    child: Text(isReading ? "Durdur" : "AI ile Oku"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                  ),
                ),
                SizedBox(width: 12),
                ElevatedButton(
                  onPressed: requestAISummary,
                  child: Text("Özetle"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
                ),
              ],
            ),
            SizedBox(height: 12),
            Text('Ses Tonu', style: TextStyle(fontWeight: FontWeight.bold)),
            Slider(value: voicePitch, min: 0.5, max: 2.0, onChanged: (v) => setState(() => voicePitch = v)),
            Text('Konuşma Hızı', style: TextStyle(fontWeight: FontWeight.bold)),
            Slider(value: voiceRate, min: 0.3, max: 1.0, onChanged: (v) => setState(() => voiceRate = v)),
            SizedBox(height: 12),
            if (summary.isNotEmpty) ...[
              SizedBox(height: 12),
              Text('Özet', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text(summary),
            ]
          ]),
        ),
      ),
    );
  }
}
