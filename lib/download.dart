import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({Key? key}) : super(key: key);

  @override
  _DownloadScreenState createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  String? selectedFilePath;
  Dio dio = Dio();

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

  Future<String> downloadM3u8AndSegments(String url, String folderPath) async {
    try {
      Response response = await dio.get(url);
      String playlistContent = response.data.toString();

      // Extract .ts segments
      List<String> tsFiles = playlistContent
          .split('\n')
          .where((line) => line.endsWith('.ts'))
          .toList();

      // Download each segment
      for (int i = 0; i < tsFiles.length; i++) {
        String tsUrl = Uri.parse(url).resolve(tsFiles[i]).toString();
        String savePath = '$folderPath/segment-$i.ts';
        await dio.download(tsUrl, savePath);
        print('Downloaded $tsUrl');
      }

      return folderPath; // Returning the folder path containing all .ts files
    } catch (e) {
      print('Error downloading .ts files: $e');
      return '';
    }
  }

  Future<void> mergeTsToMkv(String folderPath, String outputMkvPath) async {
    // Prepare a list of input .ts files
    Directory dir = Directory(folderPath);
    List<FileSystemEntity> tsFiles =
        dir.listSync().where((file) => file.path.endsWith('.ts')).toList();

    String inputs = tsFiles.map((file) => 'file ${file.path}').join('\n');
    String inputsFile = '$folderPath/input.txt';

    // Write input file list to a file
    File(inputsFile).writeAsStringSync(inputs);

    // Use ffmpeg to merge the .ts files into one .mkv
    String command = "-f concat -safe 0 -i $inputsFile -c copy $outputMkvPath";
    await FFmpegKit.execute(command).then((session) {
      print("Merging process completed.");
    }).catchError((error) {
      print("Error during merging: $error");
    });
  }

  Future<void> downloadFile() async {
    if (selectedFilePath != null) {
      List<String> urls = await readUrlsFromFile(selectedFilePath!);

      String folderPath = await createFolderForFile(selectedFilePath!);

      for (int i = 0; i < urls.length; i++) {
        String episodeFolderPath = '$folderPath/episode-${i + 1}';
        Directory(episodeFolderPath).createSync();

        // Download and save all .ts files for each episode
        await downloadM3u8AndSegments(urls[i], episodeFolderPath);

        // Merge the .ts files into one .mkv file
        String outputMkvPath = '$folderPath/episode-${i + 1}.mkv';
        await mergeTsToMkv(episodeFolderPath, outputMkvPath);
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 30),
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
              selectedFilePath != null
                  ? ElevatedButton(
                      onPressed: downloadFile,
                      child: const Text("Download and Merge"),
                    )
                  : const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
  }
}
