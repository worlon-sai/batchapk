class DownloadInfo {
  int? id; // Make it nullable for new objects
  String url;
  String status;
  double progress;
  int totalTsFiles;
  int downloadedTsFiles;
  String episodeNumber;
  bool isPaused;
  bool isDownloading;
  String episodeFolderPath;
  DateTime date;
  Duration activeTime;
  DateTime? completedDate;
  String outputMkvPath;
  DateTime addedDate;
  int size;
  bool finished;
  double speed;

  DownloadInfo({
    this.id,
    required this.url,
    this.status = 'Queued', // Default status
    this.progress = 0.0,
    this.totalTsFiles = 0,
    this.downloadedTsFiles = 0,
    required this.episodeNumber,
    this.isPaused = false,
    this.isDownloading = false,
    this.episodeFolderPath = '',
    required this.date,
    required this.activeTime,
    this.completedDate,
    this.outputMkvPath = '',
    required this.addedDate,
    this.size = 10,
    this.finished = false,
    required this.speed,
  });

  // Convert DownloadInfo to Map (for database insertion)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'url': url,
      'status': status,
      'progress': progress,
      'totalTsFiles': totalTsFiles,
      'downloadedTsFiles': downloadedTsFiles,
      'episodeNumber': episodeNumber,
      'isPaused': isPaused ? 1 : 0,
      'isDownloading': isDownloading ? 1 : 0, // Store boolean as integer
      'episodeFolderPath': episodeFolderPath,
      'date': date.toIso8601String(),
      'activeTime': activeTime.inMicroseconds,
      'completedDate': completedDate?.toIso8601String(),
      'outputMkvPath': outputMkvPath,
      'addedDate': addedDate.toIso8601String(),
      'size': size,
      'finished': finished ? 1 : 0,
      'speed': speed,
    };
  }

  // Create a DownloadInfo object from a database row (Map)
  factory DownloadInfo.fromMap(Map<String, dynamic> map) {
    return DownloadInfo(
      id: map['id'],
      url: map['url'],
      status: map['status'],
      progress: map['progress'],
      totalTsFiles: map['totalTsFiles'],
      downloadedTsFiles: map['downloadedTsFiles'],
      episodeNumber: map['episodeNumber'],
      isPaused: map['isPaused'] == 1,
      isDownloading:
          map['isDownloading'] == 1, // Convert integer back to boolean
      episodeFolderPath: map['episodeFolderPath'],
      date: DateTime.parse(map['date']),
      activeTime: Duration(microseconds: map['activeTime']),
      completedDate: map['completedDate'] != null
          ? DateTime.parse(map['completedDate'])
          : null,
      outputMkvPath: map['outputMkvPath'],
      addedDate: DateTime.parse(map['addedDate']),
      size: map['size'],
      finished: map['finished'] == 1,
      speed: map['speed'],
    );
  }
}
