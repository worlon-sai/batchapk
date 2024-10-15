import 'package:flutter/material.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'download.dart';
import 'fetchurls.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Batch Downloader',
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

enum DownloadAction { startAll, stopAll, delete }

class _MainScreenState extends State<MainScreen> {
  final GlobalKey<DownloadScreenState> _downloadScreenKey = GlobalKey();

  int _selectedIndex = 0;
  bool _showDeleteIcon = false;
  List<int> _selectedCardIds = [];
  bool _selectAll = false;

  // Instead of _widgetOptions, we directly create the screens
  @override
  void initState() {
    super.initState();

    // Initialize _screens here
    _screens = [
      WebScrapingScreen(),
      DownloadScreen(
        key: _downloadScreenKey,
        onDownloadAction: _handleDownloadAction,
        onShowIcon: showIcon,
        showDeleteIcon: _showDeleteIcon,
      ),
      Center(child: Text("Replace screen - Empty")),
    ];
  }

  List<Widget> _screens = [];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    if (_selectedIndex != 1) {
      _showDeleteIcon = false;
    }
  }

  void showIcon(int? id) {
    setState(() {
      _showDeleteIcon = false;
    });
  }

  void StartAll() {
    _downloadScreenKey.currentState?.StartAll();
  }

  void StopAll() {
    _downloadScreenKey.currentState?.StopAll();
  }

  void _handleDownloadAction(DownloadAction action, {List<int>? ids}) {
    switch (action) {
      case DownloadAction.startAll:
        StartAll();
        // TODO: Implement logic to start all downloads
        print("Start All Downloads action triggered!");
        break;
      case DownloadAction.stopAll:
        StopAll();
        // TODO: Implement logic to stop all downloads
        print("Stop All Downloads action triggered!");
        break;
      case DownloadAction.delete:
        if (ids != null && ids.length > 0) {
          setState(() {
            _showDeleteIcon = true;
            _selectedCardIds = ids;
          });
          print("Delete Downloads action triggered with IDs: $ids");
        } else {
          setState(() {
            _showDeleteIcon = false;
            _selectedCardIds = [];
          });
        }
        break;
    }
  }

  void Delete() {
    _downloadScreenKey.currentState?.Delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Batch Downloader'),
        actions: _selectedIndex == 1
            ? [
                IconButton(
                  onPressed: () =>
                      _handleDownloadAction(DownloadAction.startAll),
                  icon: const Icon(Icons.play_arrow),
                ),
                IconButton(
                  onPressed: () =>
                      _handleDownloadAction(DownloadAction.stopAll),
                  icon: const Icon(Icons.pause),
                ),
                if (_showDeleteIcon)
                  IconButton(
                    onPressed: () {
                      Delete();
                      _selectedCardIds = [];
                      _selectAll = false;
                      setState(() {});
                    },
                    icon: const Icon(Icons.delete),
                  ),
              ]
            : null,
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
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
