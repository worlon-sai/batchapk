import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart' as http;

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

  static List<Widget> _widgetOptions = <Widget>[
    WebScrapingScreen(),
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
      body: _widgetOptions[_selectedIndex],
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

class WebScrapingScreen extends StatefulWidget {
  @override
  _WebScrapingScreenState createState() => _WebScrapingScreenState();
}

class _WebScrapingScreenState extends State<WebScrapingScreen> {
  TextEditingController urlController = TextEditingController();
  TextEditingController startController = TextEditingController();
  TextEditingController endController = TextEditingController();
  String output = "";
  bool isFetching = false; // Track fetching process
  Timer? fetchTimer; // Timer to simulate fetching

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: <Widget>[
          TextField(
            controller: urlController,
            decoration: InputDecoration(
              labelText: "Enter URL",
              suffixIcon: urlController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          urlController.clear(); // Clear URL input
                          if (isFetching) {
                            // Stop fetching process
                            stopFetching();
                          }
                        });
                      },
                    )
                  : null,
            ),
            onChanged: (value) {
              setState(() {}); // Refresh the UI when text changes
            },
          ),
          TextField(
            controller: startController,
            decoration: InputDecoration(labelText: "Enter Start Episode"),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: endController,
            decoration: InputDecoration(labelText: "Enter End Episode"),
            keyboardType: TextInputType.number,
          ),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
              final url = urlController.text;
              final start = int.tryParse(startController.text) ?? 1;
              final end = int.tryParse(endController.text);

              if (url.isNotEmpty) {
                setState(() {
                  output = "Fetching data...";
                  isFetching = true; // Mark as fetching
                });

                // Simulate a long-running task
                await fetchEpisodes(
                      url, start, end, (message) {
                  setState(() {
                  output += "\n$message";
                    isFetching = false; // Mark as done
                  });
                });
              } else {
                setState(() {
                  output = "Please enter a valid URL.";
                });
              }
            },
            child: Text("Start Scraping"),
          ),
          SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              child: Text(output),
            ),
          ),
        ],
      ),
    );
  }

  void stopFetching() {
    // Logic to stop fetching
    if (fetchTimer != null && fetchTimer!.isActive) {
      fetchTimer!.cancel();
      setState(() {
        output = "Fetching stopped.";
        isFetching = false;
      });
    }
  }
}

// Helper function to log messages to console and a file
void logMessage(String message) {
  final now = DateTime.now();
  final formattedTime = "${now.year}-${now.month}-${now.day} ${now.hour}:${now.minute}";
  final logMessage = "$formattedTime: $message";

  // Print to console
  print(logMessage);

  // Append log to a file
  final logFile = File('log_${now.year}-${now.month}-${now.day}.txt');
  logFile.writeAsStringSync("$logMessage\n", mode: FileMode.append, flush: true);
}

// Fetch episodes based on the provided URL
Future<void> fetchEpisodes(String url, int start, int? end, Function(String) callback) async {
  logMessage("Starting to fetch episodes from $url");

  if (url.contains("asianload") || url.contains("mkvdrama")) {
    await saveM3u8Asianload(url, start, end ?? start, callback);
  } else if (url.contains("yugenanime")) {
    await saveM3u8Yugen(url, "https://yugenanime.tv/api/embed/", start, end ?? start, callback);
  } else if (url.contains("kisskh")) {
    await getM3u8KissKH(url, 'output.txt', callback);
  } else {
    logMessage("Unsupported website");
    callback("Unsupported website");
  }
}

// Function to save m3u8 URLs from Asianload/MKVDrama
Future<void> saveM3u8Asianload(String baseUrl, int start, int end, Function(String) callback) async {
  String seriesName = baseUrl.split('/videos/')[1].split('-episode')[0];
  String baseVideoUrl = "https://stream.mkvdrama.org/streaming.php?slug=";
  String outputFilename = "$seriesName.txt";

  for (int episodeNumber = start; episodeNumber <= end; episodeNumber++) {
    String url = "$baseVideoUrl$seriesName-episode-$episodeNumber";
    String? m3u8Url = await getM3u8Asianload(url, 1, callback);
    if (m3u8Url != null) {
      File(outputFilename).writeAsStringSync("$m3u8Url\n", mode: FileMode.writeOnlyAppend, flush: true);
    }
  }
  callback("URLs saved to $outputFilename");
}

// Function to get m3u8 URL from Asianload/MKVDrama
Future<String?> getM3u8Asianload(String url, int count, Function(String) callback) async {
  if (count > 20) {
    callback("Error: Could not find the video source URL after 20 attempts.");
    return null;
  }

  logMessage("Fetching $url (attempt $count)");
  final response = await http.get(Uri.parse(url), headers: {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3'
  });

  if (response.statusCode == 200) {
    final soup = parse(response.body);
    final mediaPlayer = soup.getElementsByTagName('media-player').first;
    final srcUrl = mediaPlayer.attributes['src'];

    if (srcUrl != null) {
      logMessage("Got URL for episode");
      return srcUrl.replaceAll(".m3u8", ".1080.m3u8");
    } else {
      logMessage("Media player not found. Retrying...");
      return await getM3u8Asianload(url, count + 1, callback);
    }
  } else {
    logMessage("Error fetching webpage: ${response.statusCode}");
    return null;
  }
}

// Function to save m3u8 URLs from YugenAnime
Future<void> saveM3u8Yugen(String url, String apiBaseUrl, int start, int end, Function(String) callback) async {
  String seriesName = url.split('/watch/')[1].split('/')[1];
  String outputFilename = "$seriesName.txt";

  for (int episodeNumber = start; episodeNumber <= end; episodeNumber++) {
    String episodeUrl = "$url$episodeNumber/";
    String? m3u8Url = await getM3u8Yugen(episodeUrl, apiBaseUrl, episodeNumber, callback);
    if (m3u8Url != null) {
      File(outputFilename).writeAsStringSync("$m3u8Url\n", mode: FileMode.append, flush: true);
    }
  }
  callback("URLs saved to $outputFilename");
}

// Function to get m3u8 URL from YugenAnime
// Function to get m3u8 URL from YugenAnime
Future<String?> getM3u8Yugen(String url, String apiBaseUrl, int episodeNumber, Function(String) callback) async {
  logMessage("Fetching YugenAnime URL for episode $episodeNumber");

  final response = await http.get(Uri.parse(url));
  logMessage("reponse from yugen $response");
  if (response.statusCode == 200) {
    final soup = parse(response.body);
    final iframeTag = soup.querySelector("#main-embed");

    if (iframeTag != null) {
      final iframeSrc = iframeTag.attributes['src'];

      if (iframeSrc != null) {
        final eId = iframeSrc.split('/')[4];  // Only attempt to split if iframeSrc is non-null
        final refUrl = "https://yugenanime.tv/e/$eId/";

        final headers = {
          "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
          "Referer": refUrl,
          "X-Requested-With": "XMLHttpRequest"
        };

        final response1 = await http.post(Uri.parse(apiBaseUrl), body: {"id": eId, "ac": "0"}, headers: headers);

        if (response1.statusCode == 200) {
          final data = jsonDecode(response1.body);
          final hlsUrl = data["hls"][0];

          if (hlsUrl != null) {
            logMessage("Found URL for episode $episodeNumber");
            return hlsUrl.replaceAll(".m3u8", ".1080.m3u8");
          } else {
            logMessage("Stream URL not found for episode $episodeNumber");
            return null;
          }
        }
      } else {
        logMessage("iframeSrc is null. Could not extract episode ID.");
        callback("iframeSrc is null. Could not extract episode ID.");
        return null;
      }
    }
  }

  logMessage("Failed to fetch episode $episodeNumber from YugenAnime");
  return null;
}

// Function to fetch m3u8 URLs and subtitles from KissKH
Future<void> getM3u8KissKH(String url, String outputFilename, Function(String) callback) async {
  logMessage("Fetching KissKH m3u8 URLs");

  final nameId = url.split('/Drama/')[1].split('?id=');
  final seriesName = nameId[0];
  final dramaUrl = "https://kisskh.co/api/DramaList/Drama/" + nameId[1].split('&q')[0];

  final response = await http.get(Uri.parse(dramaUrl));

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    final episodes = data["episodes"]..sort((a, b) => a["id"].compareTo(b["id"]));

    for (var episode in episodes) {
      final videoResponse = await http.get(Uri.parse("https://kisskh.co/api/DramaList/Episode/${episode['id']}.png"));
      final subtitleResponse = await http.get(Uri.parse("https://kisskh.co/api/Sub/${episode['id']}"));

      if (videoResponse.statusCode == 200) {
        final videoUrl = jsonDecode(videoResponse.body)["Video"];
        logMessage("Found video URL for episode ${episode['number']}");
        File(outputFilename).writeAsStringSync("$videoUrl\n", mode: FileMode.append, flush: true);
      }

      // Save subtitles
      for (var sub in jsonDecode(subtitleResponse.body)) {
        if (sub["label"] == "English") {
          final subtitleContent = await http.get(Uri.parse(sub["src"]));
          File("${seriesName}_${episode['number']}.srt").writeAsStringSync(subtitleContent.body);
          logMessage("Saved subtitle for episode ${episode['number']}");
        }
      }
    }

    callback("URLs and subtitles saved successfully!");
  } else {
    logMessage("Failed to fetch data from KissKH");
  }
}
