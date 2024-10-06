import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> checkStoragePermission() async {
  if (await Permission.storage.request().isGranted) {
    // You can access external storage
  } else {
    // Handle the case where permission is denied
  }
}

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

  Future<void> selectFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any, // Allow any file type to be selected
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

      // Extract .ts segments
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
          // Update episode-level progress
          setState(() {
            downloadStatuses[index].downloadedTsFiles = i + 1;
            downloadStatuses[index].progress = (i + 1) / tsFiles.length;
            downloadStatuses[index].status =
                '${downloadStatuses[index].downloadedTsFiles}/${downloadStatuses[index].totalTsFiles} .ts files downloaded (${(downloadStatuses[index].progress * 100).toStringAsFixed(1)}%)';
          });
        });
        print('Downloaded $tsUrl');
      }

      return folderPath; // Returning the folder path containing all .ts files
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
      // Access granted for media (Android 13+)
      print("Media access granted.");
    } else if (await Permission.manageExternalStorage.request().isGranted) {
      // Access granted for managing external storage (Android 11+)
      print("Manage external storage granted.");
    } else {
      // Permission denied
      print("Permissions denied.");
    }
  }

  Future<void> mergeTsToMkv(
      String folderPath, String outputMkvPath, int index) async {
    Directory dir = Directory(folderPath);
    var status1 = await Permission.storage.request();
    requestStoragePermission();
    final permissionStatus = await Permission.storage.status;

    // Ensure the directory exists
    var status2 = await Permission.storage.request();
    final exter = await Permission.manageExternalStorage.request();
    // Check if the directory exists
    bool exists = await dir.exists();
    if (!exists) {
      print("Directory does not exist: $folderPath");
      setState(() {
        downloadStatuses[index].status = 'Error: Directory not found';
      });
      return;
    }

    // List all .ts files in the directory
    List<FileSystemEntity> tsFiles = dir
        .listSync(recursive: true) // Recursively list files in subdirectories
        .where((file) => file.path.endsWith('.ts'))
        .toList();

    if (tsFiles.isEmpty) {
      print("No .ts files found to merge in directory: $folderPath");
      setState(() {
        downloadStatuses[index].status = 'No .ts files found for merging';
      });
      return;
    }

    // Prepare input file list for ffmpeg
    String inputs = tsFiles.map((file) => 'file ${file.path}').join('\n');
    String inputsFile = '$folderPath/input.txt';

    // Write input file list to a file
    File(inputsFile).writeAsStringSync(inputs);

    // Debugging: Check if the input.txt was created properly
    print("Input.txt created at: $inputsFile with contents:\n$inputs");

    // Use ffmpeg to merge the .ts files into one .mkv
    String command = "-f concat -safe 0 -i $inputsFile -c copy $outputMkvPath";
    setState(() {
      downloadStatuses[index].status = 'Merging...';
    });

    await FFmpegKit.execute(command).then((session) async {
      // Merging process completed
      print("Merging process completed.");

      setState(() {
        downloadStatuses[index].status = 'Merging is in progress';
        downloadStatuses[index].progress = 0.5;
      });

      // Delete .ts files and input.txt after merging
      try {
        print("Deleting .ts files and input.txt...");

        // Delete each .ts file
        for (var file in tsFiles) {
          await file.delete();
          print("Deleted file: ${file.path}");
        }

        // Delete the input.txt file
        File inputsFileToDelete = File(inputsFile);
        if (await inputsFileToDelete.exists()) {
          await inputsFileToDelete.delete();
          print("Deleted input.txt: $inputsFile");
        }

        // Optionally delete the folder itself if it's empty
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
      // Handle error during merging
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
                  episodeNumber: "waiting",
                ))
            .toList();
      });

      for (int i = 0; i < urls.length; i++) {
        String m3u8_url = urls[i];
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
          downloadStatuses[i].status = 'Downloading...';
          downloadStatuses[i].episodeNumber =
              '${episodeTitle}-episode-${episodeName}.mkv';
        });

        String outputMkvPath =
            '$folderPath/${episodeTitle}-episode-${episodeName}.mkv';
        if (await File(outputMkvPath).exists()) {
          print('Skipping already downloaded $outputMkvPath');
          setState(() {
            downloadStatuses[i].status = 'Already Downloaded';
            downloadStatuses[i].episodeNumber =
                '${episodeTitle}-episode-${episodeName}.mkv';
          });
          continue;
        }
        // Download and save all .ts files for each episode
        await downloadM3u8AndSegments(urls[i], episodeFolderPath, i);

        // Merge the .ts files into one .mkv file

        await mergeTsToMkv(episodeFolderPath, outputMkvPath, i);
      }

      print('All episodes downloaded and merged.');
    }
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
                  child: const Text("Select File from Storage"),
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
