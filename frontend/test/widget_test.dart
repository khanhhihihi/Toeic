import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:frontend/exam_api.dart';
import 'package:frontend/main.dart';
import 'package:frontend/student_ui.dart';

void main() {
  testWidgets('loads the exam list from the API and opens import', (
    tester,
  ) async {
    final api = _FakeExamApi();
    await tester.pumpWidget(MyApp(api: api));
    await tester.pumpAndSettle();

    expect(find.text('Ngân hàng đề thi'), findsOneWidget);
    expect(find.text('TOEIC Reading — Đề 01'), findsOneWidget);

    await tester.tap(find.text('Nhập đề Word').first);
    await tester.pumpAndSettle();

    expect(find.text('Nhập đề từ Word'), findsOneWidget);
    expect(find.text('Chưa có tệp Word'), findsOneWidget);
  });

  testWidgets('shows server validation issues without marking them fixed', (
    tester,
  ) async {
    final api = _FakeExamApi(valid: false);
    await tester.pumpWidget(MyApp(api: api));
    await tester.pumpAndSettle();

    final menuButton = find.byTooltip('Tác vụ với TOEIC Reading — Đề 01');
    await tester.ensureVisible(menuButton);
    await tester.tap(menuButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhập nội dung'));
    await tester.pumpAndSettle();

    expect(find.text('Thiếu tag [EXPLANATION]'), findsOneWidget);
    final fixButton = find.text('Sửa lỗi').first;
    await tester.ensureVisible(fixButton);
    await tester.tap(fixButton);
    await tester.pumpAndSettle();

    expect(find.text('Cần sửa tệp Word gốc'), findsOneWidget);
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();

    expect(find.text('Thiếu tag [EXPLANATION]'), findsOneWidget);
    expect(find.text('1 cần xem lại'), findsOneWidget);
  });

  testWidgets('validates, previews server content, and publishes via API', (
    tester,
  ) async {
    final api = _FakeExamApi();
    await tester.pumpWidget(MyApp(api: api));
    await tester.pumpAndSettle();

    final menuButton = find.byTooltip('Tác vụ với TOEIC Reading — Đề 01');
    await tester.ensureVisible(menuButton);
    await tester.tap(menuButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhập nội dung'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Tải lại & kiểm tra'));
    await tester.tap(find.text('Tải lại & kiểm tra'));
    await tester.pumpAndSettle();
    expect(api.validateCalls, 1);
    expect(find.text('Đề hợp lệ 100/100 câu.'), findsOneWidget);

    await tester.ensureVisible(find.text('Xem trước'));
    await tester.tap(find.text('Xem trước'));
    await tester.pumpAndSettle();

    expect(find.text('TOEIC Reading — Đề 01'), findsOneWidget);
    expect(find.text('What does the notice indicate?'), findsOneWidget);
    expect(find.text('75 phút'), findsNothing);

    await tester.ensureVisible(find.text('Xuất bản đề'));
    await tester.tap(find.text('Xuất bản đề'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xuất bản ngay'));
    await tester.pumpAndSettle();

    expect(api.publishCalls, 1);
    expect(find.text('Đã xuất bản TOEIC Reading — Đề 01.'), findsOneWidget);
    expect(find.textContaining('Đề đã xuất bản · 100/100 câu'), findsOneWidget);
  });

  testWidgets('edits an imported question and saves it through the API', (
    tester,
  ) async {
    final api = _FakeExamApi();
    await tester.pumpWidget(MyApp(api: api));
    await tester.pumpAndSettle();

    final menuButton = find.byTooltip('Tác vụ với TOEIC Reading — Đề 01');
    await tester.ensureVisible(menuButton);
    await tester.tap(menuButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhập nội dung'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Tải lại & kiểm tra'));
    await tester.tap(find.text('Tải lại & kiểm tra'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Xem trước'));
    await tester.tap(find.text('Xem trước'));
    await tester.pumpAndSettle();

    final editButton = find.byTooltip('Chỉnh sửa câu 1');
    await tester.ensureVisible(editButton);
    await tester.tap(editButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'Updated question content',
    );
    await tester.tap(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();

    expect(api.updateQuestionCalls, 1);
    expect(find.text('Updated question content'), findsOneWidget);
    expect(find.text('Đã lưu nội dung câu 1.'), findsOneWidget);
  });

  testWidgets('student selects an exam, answers and sees the result', (
    tester,
  ) async {
    final api = _FakeExamApi();
    await tester.pumpWidget(MaterialApp(home: StudentPortal(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Chọn đề thi'), findsOneWidget);
    await tester.tap(find.text('Xem đề thi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bắt đầu ca thi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('The office will open late.'));
    await tester.tap(find.widgetWithText(FilledButton, 'Nộp bài').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Nộp bài').last);
    await tester.pumpAndSettle();

    expect(find.text('Kết quả bài thi'), findsOneWidget);
    expect(find.text('100.0%'), findsOneWidget);
    expect(api.studentSubmitCalls, 1);
  });

  testWidgets('student can switch back to the teacher area', (tester) async {
    var switchedToTeacher = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StudentPortal(
          api: _FakeExamApi(),
          onSwitchToTeacher: () => switchedToTeacher = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Giảng viên'));

    expect(switchedToTeacher, isTrue);
  });

}

class _FakeExamApi implements ExamApi {
  _FakeExamApi({bool valid = true}) {
    _detail = _createDetail(valid: valid);
  }

  late ExamDetail _detail;
  int validateCalls = 0;
  int publishCalls = 0;
  int updateQuestionCalls = 0;
  int studentSubmitCalls = 0;

  @override
  Future<List<ExamSummary>> listExams() async => [_detail];

  @override
  Future<ExamStats> getStats() async => ExamStats(
    totalExams: 1,
    publishedExams: _detail.isPublished ? 1 : 0,
    draftExams: _detail.isPublished ? 0 : 1,
    monthlyAttempts: _detail.attempts,
    averageScore: _detail.averageScore ?? 0,
  );

  @override
  Future<ExamDetail> getExam(String id) async => _detail;

  @override
  Future<ExamDetail> importDocument(String fileName, Uint8List bytes) async {
    _detail = _createDetail(valid: false, fileName: fileName);
    return _detail;
  }

  @override
  Future<ExamDetail> replaceDocument(
    String id,
    String fileName,
    Uint8List bytes,
  ) async {
    _detail = _createDetail(valid: false, fileName: fileName);
    return _detail;
  }

  @override
  Future<ExamDetail> validate(String id) async {
    validateCalls++;
    return _detail;
  }

  @override
  Future<ExamDetail> updateQuestion(String id, ExamQuestion question) async {
    updateQuestionCalls++;
    _detail = _createDetail(valid: true, question: question);
    return _detail;
  }

  @override
  Future<ExamDetail> publish(String id) async {
    publishCalls++;
    _detail = _createDetail(valid: true, published: true);
    return _detail;
  }

  @override
  Future<void> delete(String id) async {
    _detail = _createDetail(valid: true);
  }

  @override
  Future<List<StudentExamSummary>> listStudentExams() async => [
    const StudentExamSummary(
      id: 'student-exam-1',
      title: 'TOEIC Reading — Đề 01',
      code: 'RD-01',
      questionCount: 1,
      attempts: 0,
      averageScore: null,
    ),
  ];

  @override
  Future<StudentExam> getStudentExam(String id) async => const StudentExam(
    id: 'student-exam-1',
    title: 'TOEIC Reading — Đề 01',
    code: 'RD-01',
    questionCount: 1,
    durationMinutes: 75,
    questions: [
      StudentQuestion(
        number: 1,
        prompt: 'What does the notice indicate?',
        options: {
          'A': 'The office will open late.',
          'B': 'The office will be closed.',
          'C': 'The event has been canceled.',
          'D': 'The meeting room has changed.',
        },
        passageNumber: 1,
      ),
    ],
    passages: [
      ExamPassage(number: 1, content: 'The office will be closed Monday.'),
    ],
  );

  @override
  Future<StudentAttemptResult> submitStudentAttempt(
    String examId,
    Map<int, String> answers,
  ) async {
    studentSubmitCalls++;
    return StudentAttemptResult(
      attemptId: 'attempt-1',
      examId: examId,
      examTitle: 'TOEIC Reading — Đề 01',
      examCode: 'RD-01',
      correctCount: answers[1] == 'A' ? 1 : 0,
      totalQuestions: 1,
      score: answers[1] == 'A' ? 100 : 0,
      submittedAt: DateTime.utc(2026, 10, 17),
      questions: [
        StudentQuestionResult(
          number: 1,
          prompt: 'What does the notice indicate?',
          options: const {
            'A': 'The office will open late.',
            'B': 'The office will be closed.',
            'C': 'The event has been canceled.',
            'D': 'The meeting room has changed.',
          },
          selectedAnswer: answers[1],
          correctAnswer: 'A',
          isCorrect: answers[1] == 'A',
          explanation: 'This is the selected correct answer.',
        ),
      ],
    );
  }
}

ExamDetail _createDetail({
  required bool valid,
  bool published = false,
  String fileName = 'toeic-reading.docx',
  ExamQuestion? question,
}) {
  final updatedAt = DateTime.utc(2026, 10, 17);
  final issues = valid
      ? const <ExamIssue>[]
      : const [
          ExamIssue(
            line: 86,
            questionNumber: 18,
            code: 'missing-explanation',
            title: 'Thiếu tag [EXPLANATION]',
            description: 'Câu hỏi chưa có phần lời giải bắt buộc.',
            example: '[QUESTION] 18. The meeting begins at 9 a.m.',
          ),
        ];
  const defaultQuestion = ExamQuestion(
    number: 1,
    prompt: 'What does the notice indicate?',
    options: {
      'A': 'The office will open late.',
      'B': 'The office will be closed.',
      'C': 'The event has been canceled.',
      'D': 'The meeting room has changed.',
    },
    answer: 'B',
    explanation: 'The notice states that the office will be closed.',
    passageNumber: 1,
  );
  final questions = [question ?? defaultQuestion];
  return ExamDetail(
    id: '10000000-0000-0000-0000-000000000001',
    title: 'TOEIC Reading — Đề 01',
    code: 'RD-01',
    fileName: fileName,
    isPublished: published,
    updatedAt: updatedAt,
    questionCount: valid ? 100 : 99,
    attempts: published ? 20 : 0,
    averageScore: published ? 75 : null,
    issueCount: issues.length,
    issues: issues,
    questions: valid ? questions : const [],
    passages: valid
        ? const [
            ExamPassage(
              number: 1,
              content: 'The office will be closed Monday.',
            ),
          ]
        : const [],
  );
}
