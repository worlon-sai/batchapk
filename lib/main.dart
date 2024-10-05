import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'fetchurls.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Web Scraper',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  // Create a PageStorageBucket to persist the state of each screen
  final PageStorageBucket _bucket = PageStorageBucket();

  static List<Widget> _widgetOptions = <Widget>[
    WebScrapingScreen(
        key: PageStorageKey(
            'web_scraping')), // Assign a key for state persistence
    Center(child: Text("Download screen - Empty")),
    Center(child: Text("Replace screen - Empty")),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Web Scraper'),
      ),
      // Wrap body with PageStorage to enable state persistence
      body: PageStorage(
        bucket: _bucket, // Provide the storage bucket
        child: _widgetOptions[_selectedIndex], // The selected screen widget
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Fetch URLs',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.download),
            label: 'Download',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.sync),
            label: 'Replace',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        onTap: _onItemTapped,
      ),
    );
  }
}
