import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:html/parser.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class EpisodeData {
  final int episodeNumber;
  final String status;
  final bool isCompleted;

  EpisodeData({
    required this.episodeNumber,
    required this.status,
    required this.isCompleted,
  });
}

class WebScrapingScreen extends StatefulWidget {
  // Ensure the key is passed
  @override
  _WebScrapingScreenState createState() => _WebScrapingScreenState();
}

class _WebScrapingScreenState extends State<WebScrapingScreen> {
  TextEditingController urlController = TextEditingController();
  TextEditingController startController = TextEditingController();
  TextEditingController endController = TextEditingController();
  List<EpisodeData> episodeDataList = []; // Track the episodes
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
                            stopFetching(); // Stop fetching process
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
                  episodeDataList.clear();
                  isFetching = true; // Mark as fetching
                });

                await fetchEpisodes(url, start, end, (episodeData) {
                  setState(() {
                    episodeDataList
                        .add(episodeData); // Update the list of episodes
                    isFetching = false; // Mark as done
                  });
                });
              } else {
                setState(() {
                  // Handle invalid URL
                });
              }
            },
            child: Text("Start Scraping"),
          ),
          SizedBox(height: 20),
          Expanded(
            child: ListView.builder(
              itemCount: episodeDataList.length,
              itemBuilder: (context, index) {
                EpisodeData episode = episodeDataList[index];

                // Color the row based on episode status
                Color rowColor;
                if (episode.isCompleted) {
                  rowColor = Colors.green
                      .withOpacity(0.3); // Light green for completed
                } else {
                  rowColor =
                      Colors.red.withOpacity(0.3); // Light red for failed
                }

                return Container(
                  color: rowColor,
                  child: ListTile(
                    title: Text(
                      'Episode ${episode.episodeNumber}',
                      style: TextStyle(
                        color: episode.isCompleted ? Colors.green : Colors.red,
                      ),
                    ),
                    subtitle: Text(episode.status),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void stopFetching() {
    if (fetchTimer != null && fetchTimer!.isActive) {
      fetchTimer!.cancel();
      setState(() {
        isFetching = false;
      });
    }
  }
}

// Function to log messages to console and a file

Future<void> logMessage(String message) async {
  try {
    // Get the directory for external storage (app-specific directory)
    final directory = await getExternalStorageDirectory();
    if (directory != null) {
      final logFile = File(
          '${directory.path}/log_${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}.txt');
      logFile.writeAsStringSync(message, mode: FileMode.append, flush: true);
    } else {
      print("Error: Could not access external storage directory.");
    }
  } catch (e) {
    print("Error logging message: $e");
  }
}

// Fetch episodes based on the provided URL
Future<void> fetchEpisodes(
    String url, int start, int? end, Function(EpisodeData) callback) async {
  logMessage("Starting to fetch episodes from $url");

  if (url.contains("asianload") || url.contains("mkvdrama")) {
    await saveM3u8Asianload(url, start, end ?? start, callback);
  } else if (url.contains("yugenanime")) {
    await saveM3u8Yugen(
        url, "https://yugenanime.tv/api/embed/", start, end ?? start, callback);
  } else if (url.contains("kisskh")) {
    await getM3u8KissKH(url, 'output.txt', callback);
  } else {
    logMessage("Unsupported website");
    callback(EpisodeData(
        episodeNumber: 0, status: "Unsupported website", isCompleted: false));
  }
}

// Function to save m3u8 URLs from Asianload/MKVDrama
// Function to save m3u8 URLs from Asianload/MKVDrama with error handling
Future<void> saveM3u8Asianload(
    String baseUrl, int start, int end, Function(EpisodeData) callback) async {
  String seriesName = baseUrl.split('/videos/')[1].split('-episode')[0];
  String baseVideoUrl = "https://stream.mkvdrama.org/streaming.php?slug=";
  String outputFilename = "$seriesName.txt";

  for (int episodeNumber = start; episodeNumber <= end; episodeNumber++) {
    try {
      String url = "$baseVideoUrl$seriesName-episode-$episodeNumber";
      String? m3u8Url = await getM3u8Asianload(url, 1, callback);
      if (m3u8Url != null) {
        final directory = await getExternalStorageDirectory();
        if (directory != null) {
          final path = directory.parent.parent.parent.parent.path + '/download';
          final file = File('$path/$outputFilename');

          if (!(await file.exists())) {
            await file.create(
                recursive: true); // Create the file if it doesn't exist
          }

          file.writeAsStringSync(
            "$m3u8Url\n",
            mode: FileMode.append,
            flush: true,
          );
        }
        // File(outputFilename).writeAsStringSync("$m3u8Url\n",
        //     mode: FileMode.writeOnlyAppend, flush: true);
        callback(EpisodeData(
            episodeNumber: episodeNumber,
            status: "Completed",
            isCompleted: true));
      } else {
        callback(EpisodeData(
            episodeNumber: episodeNumber,
            status: "Failed: No m3u8 URL",
            isCompleted: false));
      }
    } catch (e) {
      // Log the error and mark as failed with the error message
      logMessage("Episode $episodeNumber failed with error: $e");
      callback(EpisodeData(
          episodeNumber: episodeNumber,
          status: "Error: $e",
          isCompleted: false));
    }
  }
}

Future<String?> getM3u8Asianload(
    String url, int count, Function(EpisodeData) callback) async {
  if (count > 20) {
    callback(EpisodeData(
        episodeNumber: 0,
        status: "Error: Retry limit reached",
        isCompleted: false));
    return null;
  }

  final response = await http.get(Uri.parse(url), headers: {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3'
  });

  if (response.statusCode == 200) {
    final soup = parse(response.body);
    final mediaPlayer = soup.getElementsByTagName('media-player').first;
    final srcUrl = mediaPlayer.attributes['src'];

    if (srcUrl != null) {
      if (srcUrl.contains('original')) {
        return srcUrl;
      }
      return srcUrl.replaceAll(".m3u8", ".1080.m3u8");
    } else {
      return await getM3u8Asianload(url, count + 1, callback);
    }
  } else {
    return null;
  }
}

// Function to save m3u8 URLs from YugenAnime with error handling
Future<void> saveM3u8Yugen(String baseUrl, String embedBaseUrl, int start,
    int end, Function(EpisodeData) callback) async {
  String seriesName = baseUrl.split('/watch/')[1].split('/')[1];
  String outputFilename = "$seriesName.txt";

  for (int episodeNumber = start; episodeNumber <= end; episodeNumber++) {
    try {
      String url = "https://yugenanime.tv/watch/" +
          baseUrl.split('/watch/')[1].split('/')[0] +
          "/" +
          seriesName +
          "/" +
          episodeNumber.toString() +
          "/";
      String? m3u8Url = await getM3u8Yugen(url, episodeNumber, callback);
      if (m3u8Url != null) {
        if (!m3u8Url.contains('original')) {
          m3u8Url = m3u8Url.replaceAll(".m3u8", ".1080.m3u8");
        }

        final directory = await getExternalStorageDirectory();
        if (directory != null) {
          final path = directory.parent.parent.parent.parent.path + '/download';

          final file = File('$path/$outputFilename');

          if (!(await file.exists())) {
            await file.create(
                recursive: true); // Create the file if it doesn't exist
          }

          file.writeAsStringSync(
            "$m3u8Url\n",
            mode: FileMode.append,
            flush: true,
          );
        }
        // File(outputFilename).writeAsStringSync("$m3u8Url\n",
        //     mode: FileMode.writeOnlyAppend, flush: true);
        callback(EpisodeData(
            episodeNumber: episodeNumber,
            status: "Completed",
            isCompleted: true));
      } else {
        callback(EpisodeData(
            episodeNumber: episodeNumber,
            status: "Failed: No m3u8 URL",
            isCompleted: false));
      }
    } catch (e) {
      // Log the error and mark as failed with the error message
      logMessage("Episode $episodeNumber failed with error: $e");
      callback(EpisodeData(
          episodeNumber: episodeNumber,
          status: "Error: $e",
          isCompleted: false));
    }
  }
}

Future<String?> getM3u8Yugen(
    String apiUrl, int episodeNumber, Function(EpisodeData) callback) async {
  try {
    // Make the API call to fetch the episode's embed details
    final response = await http.get(Uri.parse('$apiUrl'));
    final baseUrl = "https://yugenanime.tv/api/embed/";

    // Check if the request was successful
    final responsebody = response.body;
    if (response.statusCode == 200) {
      final soup = parse(responsebody);
      final mediaPlayer = soup.getElementsByTagName('iframe').first;
      final srcUrl = mediaPlayer.attributes['src'];
      final eId = srcUrl?.split('/e/')[1].split('/')[0];
      Map<String, String> formData = {"id": eId != null ? eId : "", "ac": "0"};

      // Headers equivalent
      Map<String, String> headers = {
        "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
        "Referer": srcUrl != null ? srcUrl : "",
        "X-Requested-With": "XMLHttpRequest"
      };

      // Make the POST request
      var response = await http.post(
        Uri.parse(baseUrl),
        body: formData,
        headers: headers,
      );

      // Check if the request was successful
      if (response.statusCode == 200) {
        // Parse the JSON response
        var data = json.decode(response.body);

        print("Response data: $data");
        var hlsArray = data['hls'];
        return hlsArray[0];
      } else {
        // Handle the error

        print("Error: ${response.statusCode}");
        callback(EpisodeData(
            episodeNumber: episodeNumber,
            status: "Stream not found",
            isCompleted: false));
        return null;
      }
    } else {
      callback(EpisodeData(
          episodeNumber: episodeNumber,
          status: "Failed API request",
          isCompleted: false));
      return null;
    }
  } catch (e) {
    logMessage("Error fetching YugenAnime episode $episodeNumber: $e");
    callback(EpisodeData(
        episodeNumber: episodeNumber, status: "Error: $e", isCompleted: false));
    return null;
  }
}

// Function to get m3u8 URL from KissKH with error handling
// Future<void> getM3u8KissKH(String url, String outputFilename, Function(EpisodeData) callback) async {
//   try {
//     String? m3u8Url = await fetchM3u8FromKissKH(url);
//     if (m3u8Url != null) {
//       File(outputFilename).writeAsStringSync("$m3u8Url\n", mode: FileMode.writeOnlyAppend, flush: true);
//       callback(EpisodeData(episodeNumber: 1, status: "Completed", isCompleted: true));
//     } else {
//       callback(EpisodeData(episodeNumber: 1, status: "Failed: No m3u8 URL", isCompleted: false));
//     }
//   } catch (e) {
//     // Log the error and mark as failed with the error message
//     logMessage("Fetching m3u8 from KissKH failed with error: $e");
//     callback(EpisodeData(episodeNumber: 1, status: "Error: $e", isCompleted: false));
//   }
// }

Future<void> getM3u8KissKH(
    String url, String outputPath, Function(EpisodeData) callback) async {
  try {
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      // Parse the HTML and extract the necessary information
      final document = parse(response.body);
      final scriptTag = document.getElementsByTagName('script').firstWhere(
          (tag) => tag.text.contains('playerInstance.setup'),
          orElse: () => throw Exception("No player script found"));

      // Extract the m3u8 URL from the player setup script
      final regex = RegExp(r'"file":"(https?.*?.m3u8)"');
      final match = regex.firstMatch(scriptTag.text);

      if (match != null) {
        final m3u8Url = match.group(1);
        if (m3u8Url != null) {
          callback(EpisodeData(
              episodeNumber: 1, status: "Completed", isCompleted: true));

          // Log the m3u8 URL
          logMessage("m3u8 URL: $m3u8Url");

          // Optionally, save to output file if needed
          final outputFile = File(outputPath);
          await outputFile.writeAsString(m3u8Url, mode: FileMode.append);
        }
      } else {
        callback(EpisodeData(
            episodeNumber: 1,
            status: "Failed to extract m3u8",
            isCompleted: false));
      }
    } else {
      callback(EpisodeData(
          episodeNumber: 1, status: "Failed HTTP request", isCompleted: false));
    }
  } catch (e) {
    logMessage("Error fetching KissKH m3u8 URL: $e");
    callback(
        EpisodeData(episodeNumber: 1, status: "Error: $e", isCompleted: false));
  }
}
