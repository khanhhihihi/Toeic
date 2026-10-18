import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

abstract interface class ExamApi {
  Future<List<ExamSummary>> listExams();

  Future<ExamStats> getStats();

  Future<ExamDetail> getExam(String id);

  Future<ExamDetail> importDocument(String fileName, Uint8List bytes);

  Future<ExamDetail> replaceDocument(
    String id,
    String fileName,
    Uint8List bytes,
  );

  Future<ExamDetail> updateQuestion(String id, ExamQuestion question);

  Future<ExamDetail> validate(String id);

  Future<ExamDetail> publish(String id);

  Future<void> delete(String id);

  Future<List<StudentExamSummary>> listStudentExams();

  Future<StudentExam> getStudentExam(String id);

  Future<StudentAttemptResult> submitStudentAttempt(
    String examId,
    Map<int, String> answers,
  );
}

class HttpExamApi implements ExamApi {
  HttpExamApi({
    http.Client? client,
    String baseUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:5134',
    ),
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl.replaceFirst(RegExp(r'/$'), '');

  final http.Client _client;
  final String _baseUrl;

  @override
  Future<List<ExamSummary>> listExams() async {
    final response = await _send('GET', '/api/exams');
    final json = _decodeJson(response);
    if (json is! List<dynamic>) {
      throw const FormatException(
        'The exams endpoint returned an invalid list.',
      );
    }
    return json
        .map((item) => ExamSummary.fromJson(_decodeObject(item)))
        .toList();
  }

  @override
  Future<ExamStats> getStats() async {
    final response = await _send('GET', '/api/stats');
    return ExamStats.fromJson(_decodeObject(_decodeJson(response)));
  }

  @override
  Future<ExamDetail> getExam(String id) async {
    final response = await _send(
      'GET',
      '/api/exams/${Uri.encodeComponent(id)}',
    );
    return ExamDetail.fromJson(_decodeObject(_decodeJson(response)));
  }

  @override
  Future<ExamDetail> importDocument(String fileName, Uint8List bytes) async {
    final request = http.MultipartRequest('POST', _uri('/api/exams/import'))
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: fileName),
      );
    final response = await _sendMultipart(request);
    return ExamDetail.fromJson(_decodeObject(_decodeJson(response)));
  }

  @override
  Future<ExamDetail> replaceDocument(
    String id,
    String fileName,
    Uint8List bytes,
  ) async {
    final request =
        http.MultipartRequest(
            'PUT',
            _uri('/api/exams/${Uri.encodeComponent(id)}/document'),
          )
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: fileName),
          );
    final response = await _sendMultipart(request);
    return ExamDetail.fromJson(_decodeObject(_decodeJson(response)));
  }

  @override
  Future<ExamDetail> updateQuestion(String id, ExamQuestion question) async {
    final request =
        http.Request(
            'PUT',
            _uri(
              '/api/exams/${Uri.encodeComponent(id)}/questions/${question.number}',
            ),
          )
          ..headers['content-type'] = 'application/json'
          ..body = jsonEncode({
            'prompt': question.prompt,
            'options': question.options,
            'answer': question.answer,
            'explanation': question.explanation,
          });
    final response = await _sendRequest(request);
    return ExamDetail.fromJson(_decodeObject(_decodeJson(response)));
  }

  @override
  Future<ExamDetail> validate(String id) async {
    final response = await _send(
      'POST',
      '/api/exams/${Uri.encodeComponent(id)}/validate',
    );
    return ExamDetail.fromJson(_decodeObject(_decodeJson(response)));
  }

  @override
  Future<ExamDetail> publish(String id) async {
    final response = await _send(
      'POST',
      '/api/exams/${Uri.encodeComponent(id)}/publish',
    );
    return ExamDetail.fromJson(_decodeObject(_decodeJson(response)));
  }

  @override
  Future<void> delete(String id) async {
    await _send('DELETE', '/api/exams/${Uri.encodeComponent(id)}');
  }

  @override
  Future<List<StudentExamSummary>> listStudentExams() async {
    final response = await _send('GET', '/api/student/exams');
    final json = _decodeJson(response);
    if (json is! List<dynamic>) {
      throw const FormatException(
        'The student exams endpoint returned an invalid list.',
      );
    }
    return json
        .map((item) => StudentExamSummary.fromJson(_decodeObject(item)))
        .toList();
  }

  @override
  Future<StudentExam> getStudentExam(String id) async {
    final response = await _send(
      'GET',
      '/api/student/exams/${Uri.encodeComponent(id)}',
    );
    return StudentExam.fromJson(_decodeObject(_decodeJson(response)));
  }

  @override
  Future<StudentAttemptResult> submitStudentAttempt(
    String examId,
    Map<int, String> answers,
  ) async {
    final request =
        http.Request(
            'POST',
            _uri('/api/student/exams/${Uri.encodeComponent(examId)}/attempts'),
          )
          ..headers['content-type'] = 'application/json'
          ..body = jsonEncode({
            'answers': answers.map(
              (number, answer) => MapEntry('$number', answer),
            ),
          });
    final response = await _sendRequest(request);
    return StudentAttemptResult.fromJson(_decodeObject(_decodeJson(response)));
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Future<http.Response> _send(String method, String path) async {
    try {
      final request = http.Request(method, _uri(path));
      return await _sendRequest(request);
    } on http.ClientException catch (error) {
      throw ExamApiException(
        'Could not connect to the exam API: ${error.message}',
      );
    }
  }

  Future<http.Response> _sendRequest(http.BaseRequest request) async {
    try {
      return await http.Response.fromStream(await _client.send(request));
    } on http.ClientException catch (error) {
      throw ExamApiException(
        'Could not connect to the exam API: ${error.message}',
      );
    }
  }

  Future<http.Response> _sendMultipart(http.MultipartRequest request) async {
    try {
      return await http.Response.fromStream(await _client.send(request));
    } on http.ClientException catch (error) {
      throw ExamApiException(
        'Could not connect to the exam API: ${error.message}',
      );
    }
  }

  static dynamic _decodeJson(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = 'The API returned HTTP ${response.statusCode}.';
      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          message =
              body['error'] as String? ??
              body['detail'] as String? ??
              body['title'] as String? ??
              message;
        }
      } on FormatException {
        if (response.body.isNotEmpty) message = response.body;
      }
      throw ExamApiException(message, statusCode: response.statusCode);
    }
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }
}

class ExamApiException implements Exception {
  const ExamApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ExamSummary {
  const ExamSummary({
    required this.id,
    required this.title,
    required this.code,
    required this.fileName,
    required this.isPublished,
    required this.updatedAt,
    required this.questionCount,
    required this.attempts,
    required this.averageScore,
    required this.issueCount,
  });

  final String id;
  final String title;
  final String code;
  final String fileName;
  final bool isPublished;
  final DateTime updatedAt;
  final int questionCount;
  final int attempts;
  final double? averageScore;
  final int issueCount;

  factory ExamSummary.fromJson(Map<String, dynamic> json) => ExamSummary(
    id: json['id'] as String,
    title: json['title'] as String,
    code: json['code'] as String,
    fileName: json['fileName'] as String,
    isPublished: json['isPublished'] as bool,
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    questionCount: json['questionCount'] as int,
    attempts: json['attempts'] as int,
    averageScore: (json['averageScore'] as num?)?.toDouble(),
    issueCount: json['issueCount'] as int,
  );
}

class ExamStats {
  const ExamStats({
    required this.totalExams,
    required this.publishedExams,
    required this.draftExams,
    required this.monthlyAttempts,
    required this.averageScore,
  });

  final int totalExams;
  final int publishedExams;
  final int draftExams;
  final int monthlyAttempts;
  final double averageScore;

  factory ExamStats.fromJson(Map<String, dynamic> json) => ExamStats(
    totalExams: json['totalExams'] as int,
    publishedExams: json['publishedExams'] as int,
    draftExams: json['draftExams'] as int,
    monthlyAttempts: json['monthlyAttempts'] as int,
    averageScore: (json['averageScore'] as num).toDouble(),
  );
}

class ExamIssue {
  const ExamIssue({
    required this.line,
    required this.code,
    required this.title,
    required this.description,
    required this.example,
    this.questionNumber,
  });

  final int line;
  final int? questionNumber;
  final String code;
  final String title;
  final String description;
  final String example;

  String get location => questionNumber == null
      ? 'Dòng $line'
      : 'Dòng $line · Câu $questionNumber';

  factory ExamIssue.fromJson(Map<String, dynamic> json) => ExamIssue(
    line: json['line'] as int,
    questionNumber: json['questionNumber'] as int?,
    code: json['code'] as String,
    title: json['title'] as String,
    description: json['description'] as String,
    example: json['example'] as String,
  );
}

class ExamQuestion {
  const ExamQuestion({
    required this.number,
    required this.prompt,
    required this.options,
    required this.answer,
    required this.explanation,
    this.passageNumber,
  });

  final int number;
  final String prompt;
  final Map<String, String> options;
  final String answer;
  final String explanation;
  final int? passageNumber;

  factory ExamQuestion.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    if (rawOptions is! Map<String, dynamic>) {
      throw const FormatException('The API returned invalid question options.');
    }
    return ExamQuestion(
      number: json['number'] as int,
      prompt: json['prompt'] as String,
      options: rawOptions.map((key, value) => MapEntry(key, value as String)),
      answer: json['answer'] as String,
      explanation: json['explanation'] as String,
      passageNumber: json['passageNumber'] as int?,
    );
  }
}

class ExamPassage {
  const ExamPassage({required this.number, required this.content});

  final int number;
  final String content;

  factory ExamPassage.fromJson(Map<String, dynamic> json) => ExamPassage(
    number: json['number'] as int,
    content: json['content'] as String,
  );
}

class ExamDetail extends ExamSummary {
  const ExamDetail({
    required super.id,
    required super.title,
    required super.code,
    required super.fileName,
    required super.isPublished,
    required super.updatedAt,
    required super.questionCount,
    required super.attempts,
    required super.averageScore,
    required super.issueCount,
    required this.issues,
    required this.questions,
    required this.passages,
  });

  final List<ExamIssue> issues;
  final List<ExamQuestion> questions;
  final List<ExamPassage> passages;

  factory ExamDetail.fromJson(Map<String, dynamic> json) {
    final summary = ExamSummary.fromJson(json);
    return ExamDetail(
      id: summary.id,
      title: summary.title,
      code: summary.code,
      fileName: summary.fileName,
      isPublished: summary.isPublished,
      updatedAt: summary.updatedAt,
      questionCount: summary.questionCount,
      attempts: summary.attempts,
      averageScore: summary.averageScore,
      issueCount: summary.issueCount,
      issues: _decodeList(json['issues'], ExamIssue.fromJson),
      questions: _decodeList(json['questions'], ExamQuestion.fromJson),
      passages: _decodeList(json['passages'], ExamPassage.fromJson),
    );
  }
}

class StudentExamSummary {
  const StudentExamSummary({
    required this.id,
    required this.title,
    required this.code,
    required this.questionCount,
    required this.attempts,
    required this.averageScore,
  });

  final String id;
  final String title;
  final String code;
  final int questionCount;
  final int attempts;
  final double? averageScore;

  factory StudentExamSummary.fromJson(Map<String, dynamic> json) =>
      StudentExamSummary(
        id: json['id'] as String,
        title: json['title'] as String,
        code: json['code'] as String,
        questionCount: json['questionCount'] as int,
        attempts: json['attempts'] as int,
        averageScore: (json['averageScore'] as num?)?.toDouble(),
      );
}

class StudentQuestion {
  const StudentQuestion({
    required this.number,
    required this.prompt,
    required this.options,
    required this.passageNumber,
  });

  final int number;
  final String prompt;
  final Map<String, String> options;
  final int? passageNumber;

  factory StudentQuestion.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    if (rawOptions is! Map<String, dynamic>) {
      throw const FormatException('The student API returned invalid options.');
    }
    return StudentQuestion(
      number: json['number'] as int,
      prompt: json['prompt'] as String,
      options: rawOptions.map((key, value) => MapEntry(key, value as String)),
      passageNumber: json['passageNumber'] as int?,
    );
  }
}

class StudentExam {
  const StudentExam({
    required this.id,
    required this.title,
    required this.code,
    required this.questionCount,
    required this.durationMinutes,
    required this.questions,
    required this.passages,
  });

  final String id;
  final String title;
  final String code;
  final int questionCount;
  final int durationMinutes;
  final List<StudentQuestion> questions;
  final List<ExamPassage> passages;

  factory StudentExam.fromJson(Map<String, dynamic> json) => StudentExam(
    id: json['id'] as String,
    title: json['title'] as String,
    code: json['code'] as String,
    questionCount: json['questionCount'] as int,
    durationMinutes: json['durationMinutes'] as int,
    questions: _decodeList(json['questions'], StudentQuestion.fromJson),
    passages: _decodeList(json['passages'], ExamPassage.fromJson),
  );
}

class StudentQuestionResult {
  const StudentQuestionResult({
    required this.number,
    required this.prompt,
    required this.options,
    required this.selectedAnswer,
    required this.correctAnswer,
    required this.isCorrect,
    required this.explanation,
  });

  final int number;
  final String prompt;
  final Map<String, String> options;
  final String? selectedAnswer;
  final String correctAnswer;
  final bool isCorrect;
  final String explanation;

  factory StudentQuestionResult.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    if (rawOptions is! Map<String, dynamic>) {
      throw const FormatException('The result API returned invalid options.');
    }
    return StudentQuestionResult(
      number: json['number'] as int,
      prompt: json['prompt'] as String,
      options: rawOptions.map((key, value) => MapEntry(key, value as String)),
      selectedAnswer: json['selectedAnswer'] as String?,
      correctAnswer: json['correctAnswer'] as String,
      isCorrect: json['isCorrect'] as bool,
      explanation: json['explanation'] as String,
    );
  }
}

class StudentAttemptResult {
  const StudentAttemptResult({
    required this.attemptId,
    required this.examId,
    required this.examTitle,
    required this.examCode,
    required this.correctCount,
    required this.totalQuestions,
    required this.score,
    required this.submittedAt,
    required this.questions,
  });

  final String attemptId;
  final String examId;
  final String examTitle;
  final String examCode;
  final int correctCount;
  final int totalQuestions;
  final double score;
  final DateTime submittedAt;
  final List<StudentQuestionResult> questions;

  factory StudentAttemptResult.fromJson(Map<String, dynamic> json) =>
      StudentAttemptResult(
        attemptId: json['attemptId'] as String,
        examId: json['examId'] as String,
        examTitle: json['examTitle'] as String,
        examCode: json['examCode'] as String,
        correctCount: json['correctCount'] as int,
        totalQuestions: json['totalQuestions'] as int,
        score: (json['score'] as num).toDouble(),
        submittedAt: DateTime.parse(json['submittedAt'] as String),
        questions: _decodeList(
          json['questions'],
          StudentQuestionResult.fromJson,
        ),
      );
}

Map<String, dynamic> _decodeObject(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  throw const FormatException('The API returned an invalid object.');
}

List<T> _decodeList<T>(dynamic value, T Function(Map<String, dynamic>) decode) {
  if (value is! List<dynamic>) {
    throw const FormatException('The API returned an invalid collection.');
  }
  return value.map((item) => decode(_decodeObject(item))).toList();
}
