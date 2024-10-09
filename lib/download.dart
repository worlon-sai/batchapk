import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({Key? key}) : super(key: key);

  @override
  _DownloadScreenState createState() => _DownloadScreenState();
}

class DownloadStatus {
  String url;
  String status;
  double progress;
  int totalTsFiles;
  int downloadedTsFiles;
  String episodeNumber;

  DownloadStatus({
    required this.url,
    required this.status,
    required this.progress,
    required this.totalTsFiles,
    required this.downloadedTsFiles,
    required this.episodeNumber,
  });
}

class _DownloadScreenState extends State<DownloadScreen> {
  String? selectedFilePath;
  Dio dio = Dio();
  List<DownloadStatus> downloadStatuses = [];
  int maxParallelDownloads = 1;
  final TextEditingController _parallelDownloadsController =
      TextEditingController(text: '1');
  final Queue<int> _downloadQueue = Queue<int>(); // Queue to manage downloads

  @override
  void initState() {
    super.initState();
    _parallelDownloadsController.addListener(() {
      setState(() {
        maxParallelDownloads = int.tryParse(_parallelDownloadsController.text) ??
            1; 
      });
    });
  }

  @override
  void dispose() {
    _parallelDownloadsController.dispose();
    super.dispose();
  }

 Future<void> selectFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

    if (result != null) {
      setState(() {
        selectedFilePath = result.files.single.path;
      });
    } else {
      setState(() {
        selectedFilePath = null;
      });
    }
  }

 Future<List<String>> readUrlsFromFile(String filePath) async {
    final file = File(filePath);
    return await file.readAsLines();
  }

  Future<String> downloadM3u8AndSegments(
      String url, String folderPath, int index) async {
    try {
      Response response = await dio.get(url);
      String playlistContent = response.data.toString();

      List<String> tsFiles = playlistContent
          .split('\n')
          .where((line) => line.endsWith('.ts'))
          .toList();

      setState(() {
        downloadStatuses[index].totalTsFiles = tsFiles.length;
        downloadStatuses[index].downloadedTsFiles = 0;
      });

      // Download each segment
      for (int i = 0; i < tsFiles.length; i++) {
        String tsUrl = Uri.parse(url).resolve(tsFiles[i]).toString();
        String savePath = '$folderPath/segment-$i.ts';

        // Skip download if file already exists
        if (await File(savePath).exists()) {
          print('Skipping already downloaded $savePath');
          setState(() {
            downloadStatuses[index].downloadedTsFiles = i + 1;
            downloadStatuses[index].progress = (i + 1) / tsFiles.length;
            downloadStatuses[index].status =
                '${downloadStatuses[index].downloadedTsFiles}/${downloadStatuses[index].totalTsFiles} .ts files downloaded (${(downloadStatuses[index].progress * 100).toStringAsFixed(1)}%)';
          });
          continue;
        }

        await dio.download(tsUrl, savePath,
            onReceiveProgress: (received, total) {
          setState(() {
            downloadStatuses[index].downloadedTsFiles = i + 1;
            downloadStatuses[index].progress = (i + 1) / tsFiles.length;
            downloadStatuses[index].status =
                '${downloadStatuses[index].downloadedTsFiles}/${downloadStatuses[index].totalTsFiles} .ts files downloaded (${(downloadStatuses[index].progress * 100).toStringAsFixed(1)}%)';
          });
        });
        print('Downloaded $tsUrl');
      }
      setState(() {
        downloadStatuses[index].status = 'Downloaded .ts files';
      });
      return folderPath;
    } catch (e) {
      print('Error downloading .ts files: $e');
      setState(() {
        downloadStatuses[index].status = 'Error downloading .ts files';
      });
      setState(() {
        downloadStatuses[index].status = 'downgrading to 720p';
      });
      if (url.contains('1080')) {
        return downloadM3u8AndSegments(
            url.replaceAll('1080.m3u8', '720.m3u8'), folderPath, index);
      } else {
        return '';
      }
    }
  }


  void requestStoragePermission() async {
    if (await Permission.photos.request().isGranted ||
        await Permission.videos.request().isGranted ||
        await Permission.audio.request().isGranted) {
      print("Media access granted.");
    } else if (await Permission.manageExternalStorage.request().isGranted) {
      print("Manage external storage granted.");
    } else {
      print("Permissions denied.");
    }
  }

  Future<void> mergeTsToMkv(
      String folderPath, String outputMkvPath, int index) async {
    Directory dir = Directory(folderPath);
    await Permission.storage.request();
    requestStoragePermission();
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();

    bool exists = await dir.exists();
    if (!exists) {
      print("Directory does not exist: $folderPath");
      setState(() {
        downloadStatuses[index].status = 'Error: Directory not found';
      });
      return;
    }

    List<FileSystemEntity> tsFiles = dir
        .listSync(recursive: true)
        .where((file) => file.path.endsWith('.ts'))
        .toList();

    tsFiles.sort((a, b) {
      int getSegmentNumber(String filePath) {
        RegExp regex = RegExp(r'segment-(\d+)\.ts');
        Match? match = regex.firstMatch(filePath);
        return match != null ? int.parse(match.group(1)!) : 0;
      }

      return getSegmentNumber(a.path).compareTo(getSegmentNumber(b.path));
    });

    if (tsFiles.isEmpty) {
      print("No .ts files found to merge in directory: $folderPath");
      setState(() {
        downloadStatuses[index].status = 'No .ts files found for merging';
      });
      return;
    }

    String inputs = tsFiles.map((file) => 'file ${file.path}').join('\n');
    String inputsFile = '$folderPath/input.txt';

    File(inputsFile).writeAsStringSync(inputs);

    print("Input.txt created at: $inputsFile with contents:\n$inputs");

    String command = "-f concat -safe 0 -i $inputsFile -c copy $outputMkvPath";
    setState(() {
      downloadStatuses[index].status = 'Merging...';
    });

    await FFmpegKit.execute(command).then((session) async {
      print("Merging process completed.");

      setState(() {
        downloadStatuses[index].status = 'Merging is in progress';
        downloadStatuses[index].progress = 0.5;
      });

      try {
        print("Deleting .ts files and input.txt...");

        for (var file in tsFiles) {
          await file.delete();
          print("Deleted file: ${file.path}");
        }

        File inputsFileToDelete = File(inputsFile);
        if (await inputsFileToDelete.exists()) {
          await inputsFileToDelete.delete();
          print("Deleted input.txt: $inputsFile");
        }

        if (dir.listSync().isEmpty) {
          await dir.delete();
          print("Deleted folder: $folderPath");
          setState(() {
            downloadStatuses[index].status = 'Merging is completed';
            downloadStatuses[index].progress = 1.0;
          });
        }
        setState(() {
          downloadStatuses[index].status = 'Merging is completed';
          downloadStatuses[index].progress = 1.0;
        });
      } catch (e) {
        setState(() {
          downloadStatuses[index].status = 'Merging is failed';
          downloadStatuses[index].progress = 0.0;
        });
        print("Error while deleting files: $e");
      }
    }).catchError((error) {
      print("Error during merging: $error");
      setState(() {
        downloadStatuses[index].status = 'Error during merging';
      });
    });
  }

  Future<void> downloadFile() async {
    if (selectedFilePath != null) {
      List<String> urls = await readUrlsFromFile(selectedFilePath!);

      String folderPath = await createFolderForFile(selectedFilePath!);

      setState(() {
        downloadStatuses = urls
            .map((url) => DownloadStatus(
                  url: url,
                  status: 'Waiting',
                  progress: 0.0,
                  totalTsFiles: 0,
                  downloadedTsFiles: 0,
                  episodeNumber: episode_Name(url),
                ))
            .toList();
        //_downloadQueue.addAll(List.generate(urls.length, (index) => index));
      });
    int initialDownloads = urls.length < maxParallelDownloads
        ? urls.length
        : maxParallelDownloads;

    for (int i = 0; i < initialDownloads; i++) {
      _downloadAndMergeEpisode(i);  // Start download immediately
      downloadStatuses[i].status = '.ts files downloaded'; // Update status
    }

    // Add the remaining episodes to the queue
    if (urls.length > initialDownloads) {
      _downloadQueue.addAll(
          List.generate(urls.length - initialDownloads, (i) => i + initialDownloads));
    }
    }
  }

  String episode_Name(String url) { 
  
  String episodeName =url.split('/').last.split('.')[1];
  String? episodeTitle =selectedFilePath?.split('/').last.split('.').first;
  return "${episodeTitle}-episode-${episodeName}.mkv";
  }

  // Function to process the download queue
  void _processDownloadQueue() {
    print(_getActiveDownloads());
    while (_downloadQueue.isNotEmpty &&
        _getActiveDownloads() < maxParallelDownloads) {
          print(_downloadQueue.length);
      int index = _downloadQueue.removeFirst();
      setState(() {
        downloadStatuses[index].status = '.ts files downloaded';
      });
      _downloadAndMergeEpisode(index);
    }
  }

  // Function to get the number of currently active downloads
  int _getActiveDownloads() {
    return downloadStatuses.where((status) => status.status.contains('.ts files downloaded')).length;
  }

  // Function to handle download and merge of a single episode
  Future<void> _downloadAndMergeEpisode(int index) async {
    String url = downloadStatuses[index].url;
    String folderPath = await createFolderForFile(selectedFilePath!); // Ensure folder path is correct
    String m3u8_url = url;
    String episodeTitle = folderPath.split('/').last;
    String episodeName = m3u8_url.split('/').last.split('.')[1];

    if (episodeName.contains('original')) {
      String episode_Name =
          m3u8_url.split('/').last.split('episode-').last.split('-')[0];
      episodeName = episode_Name;
    }
    String episodeFolderPath = '$folderPath/episode-${episodeName}';
    Directory(episodeFolderPath).createSync();
    setState(() {
      downloadStatuses[index].status = '.ts files downloaded';
      downloadStatuses[index].episodeNumber =
          '${episodeTitle}-episode-${episodeName}.mkv';
    });

    String outputMkvPath =
        '$folderPath/${episodeTitle}-episode-${episodeName}.mkv';
    if (await File(outputMkvPath).exists()) {
      print('Skipping already downloaded $outputMkvPath');
      setState(() {
        downloadStatuses[index].status = 'Already Downloaded';
        downloadStatuses[index].episodeNumber =
            '${episodeTitle}-episode-${episodeName}.mkv';
      });
      Directory dir = Directory(episodeFolderPath);
      dir.delete();

      // Start the next download in the queue if available
      _processDownloadQueue(); 
      return;
    }
    await downloadM3u8AndSegments(url, episodeFolderPath, index);

    if (downloadStatuses[index].status == "Downloaded .ts files") {
      await mergeTsToMkv(episodeFolderPath, outputMkvPath, index);
    } else {
      print(
          "Condition false: downloadStatuses[$index].status = ${downloadStatuses[index].status}");
    }

    // Download and merging completed for this episode, start the next
    _processDownloadQueue();
  }

  Future<String> createFolderForFile(String filePath) async {
    String fileName = filePath.split('/').last.split('.').first;

    final downloadsDirectory = await getExternalStorageDirectory();
    final path =
        '${downloadsDirectory?.parent.parent.parent.parent.path}/download';
    String folderPath = '$path/$fileName';

    final folder = Directory(folderPath);
    if (!(await folder.exists())) {
      await folder.create();
    }

    return folderPath;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                ElevatedButton(
                  onPressed: selectFile,
                  child: const Text("Select File"),
                ),
                const SizedBox(width: 10),
                selectedFilePath != null
                    ? Expanded(
                        child: Text(
                          selectedFilePath!,
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      )
                    : const Expanded(
                        child: Text(
                          "No file selected",
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
              ],
            ),
            const SizedBox(height: 20),
            // Input field for number of parallel downloads
            Row(
              children: [
                const Text('Parallel Downloads:'),
                const SizedBox(width: 10),
                SizedBox(
                  width: 50,
                  child: TextField(
                    controller: _parallelDownloadsController,
                    keyboardType: TextInputType.number,
                    maxLength: 1, // Limit input to a single digit
                    decoration: const InputDecoration(
                      counterText: "", // Hide the character counter
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: selectedFilePath != null ? downloadFile : null,
              child: const Text("Download and Merge"),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: downloadStatuses.length,
                itemBuilder: (context, index) {
                  DownloadStatus status = downloadStatuses[index];
                  return ListTile(
                    title: Text("${status.episodeNumber}"),
                    subtitle: Text(status.status),
                    trailing: CircularProgressIndicator(
                      value: status.progress,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
