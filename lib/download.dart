import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'downloadFile.repository.dart';
import 'downloadFileInfo.dart';
import 'package:path/path.dart' as path;
import 'main.dart';

class DownloadScreen extends StatefulWidget {
  final Function(DownloadAction, {List<int>? ids})?
      onDownloadAction; // Callback
  final Function(int?)? onShowIcon;
  final bool showDeleteIcon;

  const DownloadScreen({
    Key? key,
    this.onDownloadAction,
    this.onShowIcon,
    required this.showDeleteIcon,
  }) : super(key: key);
  @override
  DownloadScreenState createState() => DownloadScreenState();
}

enum DownloadFilter { Downloading, Downloaded, All }

class DownloadScreenState extends State<DownloadScreen> {
  String? selectedFilePath;
  String? uiselectedFilePath;
  Dio dio = Dio();
  List<DownloadInfo> downloadStatuses = [];
  int maxParallelDownloads = 2;
  final TextEditingController _parallelDownloadsController =
      TextEditingController(text: '1');
  final Queue<int> _downloadQueue = Queue<int>();
  final Map<int, CancelToken> _cancelTokens = {};
  final dbHelper = DatabaseHelper();
  bool _showDeleteIcon = false;
  List<int> _selectedCardIds = [];
  DownloadFilter _selectedFilter = DownloadFilter.All;
  bool _selectAll = false;

  @override
  void initState() {
    super.initState();
    _initializeDownloads();
    _parallelDownloadsController.addListener(() {
      setState(() {
        maxParallelDownloads =
            int.tryParse(_parallelDownloadsController.text) ?? 2;
      });
    });
  }

  @override
  void dispose() {
    _parallelDownloadsController.dispose();
    for (var token in _cancelTokens.values) {
      token.cancel();
    }
    super.dispose();
  }

  void _deleteDownloads() {
// Suggested code may be subject to a license. Learn more: ~LicenseLog:4073815592.
    widget.onShowIcon?.call(null);
    widget.onDownloadAction?.call(DownloadAction.delete, ids: _selectedCardIds);
  }

  Future<void> _initializeDownloads() async {
    int downloading = _getActiveDownloads();
    downloadStatuses = await getAllDownloads();
    downloadStatuses.sort((a, b) =>
        ((b.isDownloading ? 1 : 0).compareTo(a.isDownloading ? 1 : 0)));

    for (var download in downloadStatuses) {
      if (!download.finished && !download.isPaused) {
        if (download.isDownloading) {
          if (downloading < maxParallelDownloads) {
            _startDownload(downloadStatuses.indexOf(download));
            downloading++;
          }
        } else {
          download.isDownloading = false;
          _downloadQueue.add(downloadStatuses.indexOf(download));
          _processDownloadQueue();
        }
      }
    }

    setState(() {});
  }

  Future<void> selectFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

    if (result != null) {
      setState(() {
        selectedFilePath = result.files.single.path;
        uiselectedFilePath = result.files.single.path;
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

  Future<List<DownloadInfo>> getAllDownloads() async {
    return await dbHelper.getAllDownloads();
  }

  Future<int> getTotalDownloadSize(List<String> tsFiles, String baseUrl) async {
    int totalSizeInBytes = 0;
    for (String tsFile in tsFiles) {
      String tsUrl = Uri.parse(baseUrl).resolve(tsFile).toString();
      try {
        Response response = await dio.head(tsUrl);
        if (response.statusCode == 200) {
          totalSizeInBytes +=
              int.parse(response.headers['content-length']?[0] ?? '0');
        }
      } catch (e) {
        print('Error getting size of $tsUrl: $e');
      }
    }
    return totalSizeInBytes;
  }

  Future<String> downloadM3u8AndSegments(
      String url, String folderPath, int index) async {
    _cancelTokens[index] = CancelToken();
    int consecutive404Errors = 0;
    const int maxConsecutive404Errors = 4;

    try {
      Response response = await dio.get(url, cancelToken: _cancelTokens[index]);
      String playlistContent = response.data.toString();

      List<String> tsFiles = playlistContent
          .split('\n')
          .where((line) => line.endsWith('.ts'))
          .toList();

      if (downloadStatuses[index].size == 0) {
        int totalSizeInBytes = await getTotalDownloadSize(tsFiles, url);
        setState(() {
          downloadStatuses[index].size = totalSizeInBytes;
        });

        updateDownloadInfoDb(downloadStatuses[index]);
      }

      setState(() {
        downloadStatuses[index].totalTsFiles = tsFiles.length;
      });
      int downloadedtsfiles = downloadStatuses[index].downloadedTsFiles > 2
          ? downloadStatuses[index].downloadedTsFiles - 2
          : downloadStatuses[index].downloadedTsFiles;
      for (int i = downloadedtsfiles; i < tsFiles.length; i++) {
        if (downloadStatuses[index].isPaused) {
          print("Download paused for episode ${index + 1}");
          _cancelTokens[index]?.cancel("Download Paused");
          return "";
        }

        String tsUrl = Uri.parse(url).resolve(tsFiles[i]).toString();
        String savePath = '$folderPath/segment-$i.ts';

        if (await File(savePath).exists()) {
          print('Skipping already downloaded $savePath');
          _updateDownloadProgress(index, i, tsFiles.length);
          continue;
        }

        try {
          await dio.download(tsUrl, savePath, cancelToken: _cancelTokens[index],
              onReceiveProgress: (received, total) {
            if (downloadStatuses[index].isPaused) {
              print("Download paused for episode ${index + 1}");
              _cancelTokens[index]?.cancel("Download Paused");
              return;
            }
            _updateDownloadProgress(index, i, tsFiles.length);
          });
          print('Downloaded $tsUrl');
          consecutive404Errors = 0; // Reset counter on successful download
        } catch (e) {
          if (e is DioError && e.response?.statusCode == 404) {
            consecutive404Errors++;
            print('Error downloading $tsUrl: 404 Not Found');
            if (consecutive404Errors >= maxConsecutive404Errors) {
              print("Too many consecutive 404 errors. Aborting download.");
              setState(() {
                downloadStatuses[index].status =
                    'Too many consecutive 404 errors. Aborting download.';
              });
              throw e; // Re-throw the exception to trigger the outer catch block
            }
          } else {
            // Re-throw other errors
            throw e;
          }
        }
      }

      setState(() {
        downloadStatuses[index].status = 'Downloaded .ts files';
      });
      return folderPath;
    } catch (e) {
      if (e is DioError && e.type == DioErrorType.cancel) {
        print('Download canceled');
        setState(() {
          downloadStatuses[index].status = 'Paused';
        });
      } else {
        print('Error downloading .ts files: $e');
        if (url.contains('1080')) {
          setState(() {
            downloadStatuses[index].status = 'downgrading to 720p';
          });
          return downloadM3u8AndSegments(
              url.replaceAll('1080.m3u8', '720.m3u8'), folderPath, index);
        } else {
          setState(() {
            downloadStatuses[index].status = 'Error downloading .ts files';
            downloadStatuses[index].isDownloading = false;
          });
        }
      }
      return '';
    }
  }

  void _updateDownloadProgress(int index, int currentFile, int totalFiles) {
    setState(() {
      downloadStatuses[index].downloadedTsFiles = currentFile + 1;
      downloadStatuses[index].progress = (currentFile + 1) / totalFiles;
      downloadStatuses[index].status =
          '${downloadStatuses[index].downloadedTsFiles}/${downloadStatuses[index].totalTsFiles} .ts files downloaded (${(downloadStatuses[index].progress * 100).toStringAsFixed(1)}%)';
    });
    if ((downloadStatuses[index].progress * 100).toInt() % 5 == 0) {
      updateDownloadInfoDb(downloadStatuses[index]);
    }
  }

  Future<int> updateDownloadInfoDb(DownloadInfo download) async {
    return await dbHelper.updateDownload(download);
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
    updateDownloadInfoDb(downloadStatuses[index]);

    await FFmpegKit.execute(command).then((session) async {
      print("Merging process completed.");

      setState(() {
        downloadStatuses[index].status = 'Merging is in progress';
        downloadStatuses[index].progress = 0.5;
      });
      updateDownloadInfoDb(downloadStatuses[index]);
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
            downloadStatuses[index].isDownloading = false;
            downloadStatuses[index].finished = true;
          });
          updateDownloadInfoDb(downloadStatuses[index]);
        }
        setState(() {
          downloadStatuses[index].status = 'Merging is completed';
          downloadStatuses[index].progress = 1.0;
          downloadStatuses[index].isDownloading = false;
          downloadStatuses[index].finished = true;
        });
      } catch (e) {
        setState(() {
          downloadStatuses[index].status = 'Merging is error';
          downloadStatuses[index].progress = 0.0;
        });
        print("Error while deleting files: $e");
      }
    }).catchError((error) {
      print("Error during merging: $error");
      setState(() {
        downloadStatuses[index].status = 'error during merging';
      });
    });
  }

  Future<void> downloadFile() async {
    if (selectedFilePath != null) {
      List<String> urls = await readUrlsFromFile(selectedFilePath!);

      String folderPath = await createFolderForFile(selectedFilePath!);
      List<DownloadInfo> UrlDownload = [];
      setState(() {
        UrlDownload = urls.map((url) {
          String episodeName = url
              .split('/')
              .last
              .split('.')[1]; // Use path.basenameWithoutExtension here as well

          if (episodeName.contains('original')) {
            episodeName =
                url.split('/').last.split('episode-').last.split('-')[0];
          }

          String episodeFolderPath = '$folderPath/episode-${episodeName}';
          String outputMkvPath =
              '$folderPath/${folderPath.split('/').last}-episode-${episodeName}.mkv';
          return DownloadInfo(
            url: url,
            status: 'Waiting',
            progress: 0.0,
            totalTsFiles: 0,
            downloadedTsFiles: 0,
            isDownloading: true,
            episodeNumber:
                '${folderPath.split('/').last}-episode-${episodeName}.mkv',
            date: DateTime.now(),
            activeTime: Duration.zero,
            addedDate: DateTime.now(),
            size: 0,
            finished: false,
            speed: 0.0,
            episodeFolderPath: episodeFolderPath,
            outputMkvPath: outputMkvPath,
          );
        }).toList();
      });

      for (var download in UrlDownload) {
        DownloadInfo? isExisting =
            await dbHelper.getDownloadByUrl(download.url);
        if (isExisting == null) {
          await dbHelper.insertDownload(download);
          DownloadInfo? inserted =
              await dbHelper.getDownloadByUrl(download.url);
          if (inserted != null) {
            download.id = inserted.id;
            download.size = inserted.size;
            download.progress = inserted.progress;
          }
        } else {
          download.id = isExisting.id;
          download.size = isExisting.size;
          download.progress = isExisting.progress;
        }
      }
      _initializeDownloads();
    }
  }

  // Function to process the download queue
  void _processDownloadQueue() {
    if (_downloadQueue.isEmpty) {
      return; // Nothing to download
    }
    if (_downloadQueue.isNotEmpty &&
        _getActiveDownloads() < maxParallelDownloads) {
      print(_downloadQueue.length);
      int index = _downloadQueue.removeFirst();
      setState(() {
        downloadStatuses[index].isDownloading = true;
        downloadStatuses[index].status = '.ts files downloaded';
      });
      _startDownload(index);
    }
  }

  void _startDownload(int index) {
    setState(() {
      downloadStatuses[index].isPaused = false;
      if (downloadStatuses[index].status == 'Paused') {
        downloadStatuses[index].status = 'Resuming...';
      } else {
        downloadStatuses[index].status = '.ts files downloaded';
        downloadStatuses[index].isDownloading = true; // Update status
      }
    });
    _downloadAndMergeEpisode(index);
  }

  // Function to get the number of currently active downloads
  int _getActiveDownloads() {
    return downloadStatuses.where((element) => element.isDownloading).length;
  }

  // Function to handle download and merge of a single episode
  Future<void> _downloadAndMergeEpisode(int index) async {
    String url = downloadStatuses[index].url;

    String m3u8_url = url;

    String episodeFolderPath = downloadStatuses[index].episodeFolderPath;
    Directory(episodeFolderPath).createSync();
    setState(() {
      downloadStatuses[index].isDownloading = true;
      downloadStatuses[index].status = '.ts files downloaded';
    });

    String outputMkvPath = downloadStatuses[index].outputMkvPath;

    if (await File(outputMkvPath).exists()) {
      print('Skipping already downloaded $outputMkvPath');

      setState(() {
        downloadStatuses[index].status = 'Already Downloaded';
        downloadStatuses[index].progress = 1.0;
        downloadStatuses[index].finished = true;
        downloadStatuses[index].isDownloading = false;
      });
      updateDownloadInfoDb(downloadStatuses[index]);
      List<DownloadInfo> alldownloads = await dbHelper.getAllDownloads();
      Directory dir = Directory(episodeFolderPath);
      dir.delete();

      // Start the next download in the queue if available
      _processDownloadQueue();
      return;
    }
    Future<int> com = updateDownloadInfoDb(downloadStatuses[index]);
    List<DownloadInfo> alldownloads = await dbHelper.getAllDownloads();
    if (downloadStatuses[index].isPaused) {
      print("Download paused for episode ${index + 1}");
      _cancelTokens[index]?.cancel("Download Paused"); // Cancel the download
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

  List<DownloadInfo> getFilteredDownloads() {
    switch (_selectedFilter) {
      case DownloadFilter.Downloading:
        return downloadStatuses
            .where((status) => status.isDownloading && status.progress < 1.0)
            .toList();
      case DownloadFilter.Downloaded:
        return downloadStatuses
            .where((status) => status.progress == 1.0)
            .toList();
      case DownloadFilter.All:
      default:
        return downloadStatuses;
    }
  }

  void StartAll() {
    int activedownloads = _getActiveDownloads();
    for (var download in downloadStatuses) {
      if (!download.finished && download.isPaused) {
        download.isPaused = false;
        download.status = "Waiting...";
        if (activedownloads < maxParallelDownloads) {
          _startDownload(downloadStatuses.indexOf(download));
          activedownloads++;
        } else {
          download.isDownloading = false;
          _downloadQueue.add(downloadStatuses.indexOf(download));
          _processDownloadQueue();
        }
      }
      updateDownloadInfoDb(download);
    }
    setState(() {});
  }

  void StopAll() {
    for (var download in downloadStatuses) {
      if (!download.finished &&
          (download.isDownloading || !download.isPaused)) {
        download.isPaused = true;
        download.status = "Paused";
        download.isDownloading = false;
        _downloadQueue.remove(downloadStatuses.indexOf(download));
        _processDownloadQueue();
      }
      updateDownloadInfoDb(download);
    }
    setState(() {});
  }

  Future<void> Delete() async {
    for (var Id in _selectedCardIds) {
      setState(() {
        downloadStatuses.firstWhere((e) => e.id == Id).status = "Deleting...";
      });
      var deletedownload = downloadStatuses.firstWhere((e) => e.id == Id);
      deletedownload.status = "Deleting...";
      deletedownload.isPaused = true;
      deletedownload.isDownloading = false;
      deletedownload.progress = 0.0;
      var isupdated = updateDownloadInfoDb(deletedownload);
      setState(() {});
      Directory(deletedownload.episodeFolderPath).deleteSync(recursive: true);
      Directory dir = Directory(deletedownload.episodeFolderPath);
      dir.delete();
      await dbHelper.deleteDownload(Id);
      setState(() {
        downloadStatuses.removeAt(downloadStatuses.indexOf(deletedownload));
      });
      _selectedCardIds = [];
    }
  }

  void _toggleCardSelection(int id) {
    if (_selectedCardIds.contains(id)) {
      _selectedCardIds.remove(id);
      _selectAll = false; // Uncheck "Select All" if an item is deselected
    } else {
      _selectedCardIds.add(id);
      // Check if all filtered items are selected
      _selectAll = _selectedCardIds.length == getFilteredDownloads().length;
    }
    _showDeleteIcon = _selectedCardIds.isNotEmpty;
    _deleteDownloads();
  }

  Widget _buildSelectAllChip() {
    return FilterChip(
      label: Text(_selectAll ? 'Deselect All' : 'Select All'),
      selected: _selectAll,
      onSelected: (selected) {
        setState(() {
          _selectAll = selected;
          _selectedCardIds = selected
              ? getFilteredDownloads()
                  .map((status) => status.id)
                  .whereType<int>() // Filter out null values
                  .toList()
              : [];
          _showDeleteIcon = _selectedCardIds.isNotEmpty;
          _deleteDownloads();
        });
      },
    );
  }

  Future<void> showFileSelectionDialog(BuildContext context) async {
    String? selectedFileName; // To store and display the file name

    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('File Selection'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      await selectFile();
                      if (uiselectedFilePath != null &&
                          uiselectedFilePath!.isNotEmpty) {
                        // Extract the file name from the file path
                        selectedFileName = uiselectedFilePath!.split('/').last;
                      }
                      // Update the dialog state to display the file name and change button text
                      setState(() {});
                    },
                    child: const Text("Select File"),
                  ),
                  const SizedBox(height: 10),
                  if (selectedFileName != null)
                    Text(
                      "Selected File: $selectedFileName", // Show the selected file name
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  const SizedBox(height: 10),
                  // Display parallel downloads value as non-editable
                  TextFormField(
                    initialValue: maxParallelDownloads.toString(),
                    decoration: const InputDecoration(
                      labelText: 'Parallel Downloads',
                    ),
                    enabled: false, // Make it non-editable
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    // Clear the selected file path when closing the dialog
                    uiselectedFilePath = "";
                    Navigator.of(context).pop();
                  },
                  child: const Text("Close"),
                ),
                TextButton(
                  onPressed: () {
                    // Only start download if the file is selected
                    if (uiselectedFilePath != null &&
                        uiselectedFilePath!.isNotEmpty) {
                      downloadFile();
                      Navigator.of(context)
                          .pop(); // Close the dialog after starting download
                    }
                  },
                  child: Text(
                    uiselectedFilePath != null && uiselectedFilePath!.isNotEmpty
                        ? "Start Download"
                        : "Select File First",
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Dialog to update the parallel downloads value
  Future<void> showParallelDownloadsDialog(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('Set Parallel Downloads'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: () {
                          if (maxParallelDownloads > 1) {
                            setState(() {
                              maxParallelDownloads--;
                            });
                          }
                        },
                        icon: const Icon(Icons.remove),
                      ),
                      Text(
                        maxParallelDownloads.toString(),
                        style: const TextStyle(fontSize: 20),
                      ),
                      IconButton(
                        onPressed: () {
                          if (maxParallelDownloads < 8) {
                            setState(() {
                              maxParallelDownloads++;
                            });
                          }
                        },
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text("Close"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _getStatusWidget(DownloadInfo status, int index) {
    // Check for error in the status
    if (status.status.toLowerCase().contains("error") ||
        status.status.toLowerCase().contains("720p")) {
      return IconButton(
        onPressed: () {
          // Retry logic (same as play button)
          setState(() {
            downloadStatuses[index].isPaused = false;
            downloadStatuses[index].status = "Waiting...";
          });
          _downloadQueue.add(index);
          _processDownloadQueue();
        },
        icon: const Icon(Icons.refresh, color: Colors.blue),
      );
    }
    // Check if download is complete
    else if (status.progress == 1.0) {
      return const Icon(
        Icons.check_circle_outline,
        color: Colors.green,
      );
    }
    // Download is paused
    else if (status.isPaused) {
      return IconButton(
        onPressed: () {
          setState(() {
            downloadStatuses[index].isPaused = false;
            downloadStatuses[index].status = "Waiting...";
          });
          updateDownloadInfoDb(downloadStatuses[index]);
          _downloadQueue.add(index);
          _processDownloadQueue();
        },
        icon: const Icon(
          Icons.play_circle,
          color: Colors.green,
        ),
      );
    }
    // Merging in progress
    else if (status.status == "Merging..." ||
        status.status == "Merging is in progress") {
      return Icon(
        Icons.check_circle_outline,
        color: Colors.orange,
      );
    }
    // Download is in progress
    else if (!status.isPaused) {
      return IconButton(
        onPressed: () {
          setState(() {
            downloadStatuses[index].isPaused = true;
            downloadStatuses[index].isDownloading = false;
            downloadStatuses[index].status = "Paused";
          });
          // Remove the paused download from the queue
          if (_downloadQueue.contains(index)) {
            _downloadQueue.remove(index);
          }
          updateDownloadInfoDb(downloadStatuses[index]);
          // Process the queue to potentially start the next download
          _processDownloadQueue();
        },
        icon: Icon(
          Icons.pause_circle,
          color: downloadStatuses[index].status.contains("Waiting")
              ? Colors.blue
              : Colors.orange, // Change color to blue when waiting
        ),
      );
    }

    // Default case (shouldn't happen, but good practice)
    else {
      return const SizedBox(); // Or any other default widget
    }
  }

  Widget _buildFilterChip(DownloadFilter filter) {
    return FilterChip(
      label: Text(filter.name),
      selected: _selectedFilter == filter,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = filter;
          List<int> newIds = getFilteredDownloads()
              .map((status) => status.id)
              .whereType<int>() // Filter out null values
              .toList();
          _selectedCardIds.removeWhere((id) => !newIds.contains(id));
          if (_selectAll) {
            // If the filter is selected
            _selectedCardIds = getFilteredDownloads()
                .map((status) => status.id)
                .whereType<int>() // Filter out null values
                .toList();
            if (_selectedCardIds.length == 0) {
              _selectAll = false;
            }
          }
          _deleteDownloads();
        });
        // You may want to update your downloadStatuses based on the filter here
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Wrap(
              spacing: 8.0,
              children: [
                _buildFilterChip(DownloadFilter.All),
                _buildFilterChip(DownloadFilter.Downloading),
                _buildFilterChip(DownloadFilter.Downloaded),
                _buildSelectAllChip(),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: getFilteredDownloads().length, // Use filtered list
              itemBuilder: (context, index) {
                final status = getFilteredDownloads()[index];
                Color cardBackgroundColor = _selectedCardIds.contains(status.id)
                    ? Colors.grey[300]! // Highlighted when selected
                    : Colors.white;
                Color progressColor;
                IconData? statusIcon;
                // Check for error in the status
                if (status.status.toLowerCase().contains("error") ||
                    status.status.toLowerCase().contains("720p")) {
                  progressColor = Colors.redAccent;
                  statusIcon = Icons.error_outline;
                }
                // Check if download is complete
                else if (status.progress == 1.0) {
                  progressColor = Colors.lightGreen;
                  statusIcon = Icons.check_circle_outline;
                }
                // Download is in progress or paused, we'll use buttons
                else {
                  progressColor = Colors.lightBlueAccent;
                  statusIcon = null; // No icon, we'll use buttons
                }

                // Calculate percentage
                String progressPercentage =
                    (status.progress * 100).toStringAsFixed(1) + "%";

                return GestureDetector(
                  onTap: () {
                    // <-- Add onTap handler here
                    if (_showDeleteIcon) {
                      // <-- Only allow selection in delete mode
                      setState(() {
                        _toggleCardSelection(status.id ?? 0);
                      });
                    }
                  },
                  onLongPress: () {
                    setState(() {
                      _toggleCardSelection(status.id ?? 0);
                    });
                  },
                  child: Card(
                    elevation: 4,
                    color: cardBackgroundColor, // Apply background color
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  "${status.episodeNumber}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              _getStatusWidget(status, index),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: status.progress,
                                  backgroundColor: Colors.grey[300],
                                  color: progressColor,
                                  minHeight: 8,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                progressPercentage,
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            getDisplayStatus(status),
                            style: TextStyle(
                              color: (status.status
                                          .toLowerCase()
                                          .contains("error") ||
                                      status.status
                                          .toLowerCase()
                                          .contains("720p"))
                                  ? Colors.redAccent
                                  : Colors.black54,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton(
                onPressed: () {
                  showFileSelectionDialog(context);
                },
                child: const Icon(Icons.add),
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(14),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  showParallelDownloadsDialog(context);
                },
                child: const Text('Parallel Downloads'),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatFileSize(int sizeInBytes) {
  if (sizeInBytes < 1024) {
    return '$sizeInBytes B';
  } else if (sizeInBytes < 1024 * 1024) {
    return '${(sizeInBytes / 1024).toStringAsFixed(2)} KB';
  } else if (sizeInBytes < 1024 * 1024 * 1024) {
    return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  } else {
    return '${(sizeInBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

String getDisplayStatus(DownloadInfo status) {
  return status.status.contains('.ts files downloaded')
      ? _formatFileSize(status.size) +
          ' : ' +
          'Part ' +
          status.status.split('.ts files downloaded')[0] +
          ' (' +
          (status.progress * 100).toStringAsFixed(1) +
          '%)'
      : _formatFileSize(status.size) +
          ' : ' +
          status.status +
          ' (' +
          (status.progress * 100).toStringAsFixed(1) +
          '%)';
}
