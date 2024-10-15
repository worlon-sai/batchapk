import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class Phrases {
  Map<String, String> _phrases = {};

  Phrases._privateConstructor();

  // Singleton instance
  static final Phrases instance = Phrases._privateConstructor();

  // Load the phrases from the JSON file
  Future<void> loadPhrases() async {
    String jsonString = await rootBundle.loadString('asserts/Phrases.json');
    Map<String, dynamic> jsonMap = json.decode(jsonString);
    _phrases = jsonMap.map((key, value) => MapEntry(key, value.toString()));
  }

  // Get a phrase by key
  String getPhrase(String key) {
    return _phrases[key] ?? key;
  }
}
