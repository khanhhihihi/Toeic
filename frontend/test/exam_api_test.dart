import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/exam_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('decodes exam summaries returned by the backend', () async {
    final api = HttpExamApi(
      baseUrl: 'http://localhost:5134/',
      client: MockClient((request) async {
        expect(request.url.path, '/api/exams');
        return http.Response(
          jsonEncode([_summaryJson]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final exams = await api.listExams();

    expect(exams, hasLength(1));
    expect(exams.single.code, 'RD-01');
    expect(exams.single.issueCount, 2);
    expect(exams.single.isPublished, isFalse);
  });

  test(
    'uploads a DOCX as a multipart file and decodes the created exam',
    () async {
      var requestPath = '';
      final api = HttpExamApi(
        client: MockClient((request) async {
          requestPath = request.url.path;
          expect(request.method, 'POST');
          expect(
            request.headers['content-type'],
            startsWith('multipart/form-data;'),
          );
          return http.Response(
            jsonEncode(_detailJson),
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final detail = await api.importDocument(
        'reading.docx',
        Uint8List.fromList([1, 2, 3]),
      );

      expect(requestPath, '/api/exams/import');
      expect(detail.title, 'TOEIC Reading — Đề 01');
      expect(detail.issues, hasLength(1));
      expect(detail.questions.single.options['A'], 'Option A');
    },
  );

  test('surfaces backend validation errors', () async {
    final api = HttpExamApi(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'error': 'Only .docx files are supported.'}),
          400,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    await expectLater(
      api.validate('10000000-0000-0000-0000-000000000001'),
      throwsA(
        isA<ExamApiException>()
            .having((error) => error.statusCode, 'statusCode', 400)
            .having(
              (error) => error.message,
              'message',
              'Only .docx files are supported.',
            ),
      ),
    );
  });

  test('updates an imported question on the backend', () async {
    final api = HttpExamApi(
      client: MockClient((request) async {
        expect(request.method, 'PUT');
        expect(
          request.url.path,
          '/api/exams/10000000-0000-0000-0000-000000000001/questions/1',
        );
        expect(request.headers['content-type'], 'application/json');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['prompt'], 'Updated question');
        expect(body['answer'], 'B');
        return http.Response(
          jsonEncode(_detailJson),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final detail = await api.updateQuestion(
      '10000000-0000-0000-0000-000000000001',
      const ExamQuestion(
        number: 1,
        prompt: 'Updated question',
        options: {
          'A': 'Option A',
          'B': 'Option B',
          'C': 'Option C',
          'D': 'Option D',
        },
        answer: 'B',
        explanation: 'Updated explanation',
      ),
    );

    expect(detail.questions.single.number, 1);
  });

  test('loads a student-safe exam and submits the answer map', () async {
    final api = HttpExamApi(
      client: MockClient((request) async {
        if (request.url.path == '/api/student/exams') {
          return http.Response(
            jsonEncode([
              {
                'id': 'student-exam-1',
                'title': 'Published exam',
                'code': 'RD-01',
                'questionCount': 1,
                'attempts': 0,
                'averageScore': null,
              },
            ]),
            200,
          );
        }
        if (request.url.path == '/api/student/exams/student-exam-1') {
          expect(request.method, 'GET');
          return http.Response(
            jsonEncode({
              'id': 'student-exam-1',
              'title': 'Published exam',
              'code': 'RD-01',
              'questionCount': 1,
              'durationMinutes': 75,
              'questions': [
                {
                  'number': 1,
                  'prompt': 'Question',
                  'options': {'A': 'Alpha', 'B': 'Beta'},
                  'passageNumber': null,
                },
              ],
              'passages': [],
            }),
            200,
          );
        }
        expect(request.url.path, '/api/student/exams/student-exam-1/attempts');
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {
          'answers': {'1': 'A'},
        });
        return http.Response(
          jsonEncode({
            'attemptId': 'attempt-1',
            'examId': 'student-exam-1',
            'examTitle': 'Published exam',
            'examCode': 'RD-01',
            'correctCount': 1,
            'totalQuestions': 1,
            'score': 100,
            'submittedAt': '2026-10-17T00:00:00Z',
            'questions': [
              {
                'number': 1,
                'prompt': 'Question',
                'options': {'A': 'Alpha', 'B': 'Beta'},
                'selectedAnswer': 'A',
                'correctAnswer': 'A',
                'isCorrect': true,
                'explanation': 'Because.',
              },
            ],
          }),
          200,
        );
      }),
    );

    final exams = await api.listStudentExams();
    final exam = await api.getStudentExam(exams.single.id);
    final result = await api.submitStudentAttempt(exam.id, {1: 'A'});

    expect(exam.questions.single.options['A'], 'Alpha');
    expect(result.score, 100);
    expect(result.questions.single.correctAnswer, 'A');
  });
}

const _summaryJson = {
  'id': '10000000-0000-0000-0000-000000000001',
  'title': 'TOEIC Reading — Đề 01',
  'code': 'RD-01',
  'fileName': 'reading.docx',
  'isPublished': false,
  'updatedAt': '2026-10-17T00:00:00Z',
  'questionCount': 99,
  'attempts': 0,
  'averageScore': null,
  'issueCount': 2,
};

const _detailJson = {
  ..._summaryJson,
  'issues': [
    {
      'line': 86,
      'questionNumber': 18,
      'code': 'missing-explanation',
      'title': 'Thiếu tag [EXPLANATION]',
      'description': 'Câu hỏi chưa có phần lời giải bắt buộc.',
      'example': 'Question excerpt',
    },
  ],
  'questions': [
    {
      'number': 1,
      'prompt': 'What does the notice indicate?',
      'options': {
        'A': 'Option A',
        'B': 'Option B',
        'C': 'Option C',
        'D': 'Option D',
      },
      'answer': 'A',
      'explanation': 'The notice says so.',
      'passageNumber': 1,
    },
  ],
  'passages': [
    {'number': 1, 'content': 'Notice content'},
  ],
};
