import 'dart:async';

import 'package:flutter/material.dart';

import 'exam_api.dart';

const _studentInk = Color(0xFF182238);
const _studentMuted = Color(0xFF6B7487);
const _studentLine = Color(0xFFE5E8EF);
const _studentCanvas = Color(0xFFF5F6FA);
const _studentPurple = Color(0xFF4F46E5);
const _studentPalePurple = Color(0xFFEEEDFF);
const _studentGreen = Color(0xFF087A55);
const _studentPaleGreen = Color(0xFFEAF7F0);
const _studentRed = Color(0xFFCE3434);
const _studentPaleRed = Color(0xFFFFF0F0);

class StudentPortal extends StatefulWidget {
  const StudentPortal({super.key, required this.api, this.onSwitchToTeacher});

  final ExamApi api;
  final VoidCallback? onSwitchToTeacher;

  @override
  State<StudentPortal> createState() => _StudentPortalState();
}

enum _StudentPage { exams, details, taking, result }

class _StudentPortalState extends State<StudentPortal> {
  _StudentPage _page = _StudentPage.exams;
  List<StudentExamSummary> _exams = [];
  StudentExam? _exam;
  StudentAttemptResult? _result;
  final Map<int, String> _answers = {};
  int _selectedQuestion = 1;
  int _remainingSeconds = 0;
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_loadExams());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadExams() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final exams = await widget.api.listStudentExams();
      if (!mounted) return;
      setState(() {
        _exams = exams;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _selectExam(StudentExamSummary summary) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final exam = await widget.api.getStudentExam(summary.id);
      if (!mounted) return;
      setState(() {
        _exam = exam;
        _loading = false;
        _page = _StudentPage.details;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _startExam() {
    final exam = _exam;
    if (exam == null) return;
    _timer?.cancel();
    setState(() {
      _answers.clear();
      _selectedQuestion = exam.questions.isEmpty
          ? 1
          : exam.questions.first.number;
      _remainingSeconds = exam.durationMinutes * 60;
      _page = _StudentPage.taking;
      _submitting = false;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _page != _StudentPage.taking || _submitting) return;
      if (_remainingSeconds <= 1) {
        timer.cancel();
        setState(() => _remainingSeconds = 0);
        unawaited(_submitAttempt(timeout: true));
      } else {
        setState(() => _remainingSeconds--);
      }
    });
  }

  Future<void> _confirmSubmit() async {
    final exam = _exam;
    if (exam == null || _submitting) return;
    final unanswered = exam.questions.length - _answers.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nộp bài thi?'),
        content: Text(
          unanswered == 0
              ? 'Bạn đã trả lời tất cả câu hỏi. Bạn có chắc muốn nộp bài không?'
              : 'Bạn còn $unanswered câu chưa trả lời. Các câu này sẽ được tính sai nếu bạn nộp bây giờ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Làm tiếp'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Nộp bài'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _submitAttempt();
  }

  Future<void> _submitAttempt({bool timeout = false}) async {
    final exam = _exam;
    if (exam == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      final result = await widget.api.submitStudentAttempt(exam.id, _answers);
      if (!mounted) return;
      _timer?.cancel();
      setState(() {
        _result = result;
        _submitting = false;
        _page = _StudentPage.result;
      });
      if (timeout) _showMessage('Hết giờ. Bài thi đã được nộp tự động.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showMessage('Không thể nộp bài thi: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String get _clock {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _studentCanvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: InkWell(
          onTap: () {
            if (_page == _StudentPage.taking) return;
            setState(() {
              _page = _StudentPage.exams;
              _exam = null;
              _result = null;
            });
          },
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_rounded, color: _studentPurple, size: 23),
              SizedBox(width: 9),
              Text(
                'readia',
                style: TextStyle(
                  color: _studentInk,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(width: 12),
              Text(
                'Khu vực học viên',
                style: TextStyle(color: _studentMuted, fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          if (_page != _StudentPage.taking)
            TextButton.icon(
              onPressed: widget.onSwitchToTeacher,
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: const Text('Giảng viên'),
            ),
          if (_page != _StudentPage.taking)
            IconButton(
              tooltip: 'Hướng dẫn',
              onPressed: () =>
                  _showMessage('Đây là khu vực làm bài thi dành cho học viên.'),
              icon: const Icon(Icons.help_outline, size: 18),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _messagePanel(
        icon: Icons.cloud_off_outlined,
        title: 'Không tải được dữ liệu đề thi',
        message: _error!,
        action: FilledButton.icon(
          onPressed: _loadExams,
          icon: const Icon(Icons.refresh),
          label: const Text('Thử lại'),
        ),
      );
    }
    return switch (_page) {
      _StudentPage.exams => _examList(),
      _StudentPage.details => _examDetails(),
      _StudentPage.taking => _takingExam(),
      _StudentPage.result => _resultPage(),
    };
  }

  Widget _examList() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LUYỆN THI TOEIC',
            style: TextStyle(
              color: _studentPurple,
              letterSpacing: 1,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Chọn đề thi',
            style: TextStyle(
              color: _studentInk,
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Chọn một đề đã được giảng viên xuất bản để bắt đầu ca thi.',
            style: TextStyle(color: _studentMuted, fontSize: 14),
          ),
          const SizedBox(height: 22),
          if (_exams.isEmpty)
            _messagePanel(
              icon: Icons.inbox_outlined,
              title: 'Chưa có đề thi khả dụng',
              message: 'Đề thi sẽ xuất hiện ở đây sau khi giảng viên xuất bản.',
              action: OutlinedButton.icon(
                onPressed: _loadExams,
                icon: const Icon(Icons.refresh),
                label: const Text('Tải lại'),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 760 ? 2 : 1;
                final cardWidth =
                    (constraints.maxWidth - (columns - 1) * 16) / columns;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final exam in _exams)
                      SizedBox(width: cardWidth, child: _examCard(exam)),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _examCard(StudentExamSummary exam) {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _studentPalePurple,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.assignment_outlined,
                  color: _studentPurple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exam.title,
                      style: const TextStyle(
                        fontSize: 15,
                        color: _studentInk,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      exam.code,
                      style: const TextStyle(color: _studentMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _metadata(Icons.quiz_outlined, '${exam.questionCount} câu hỏi'),
              _metadata(Icons.timer_outlined, '75 phút'),
              _metadata(Icons.people_outline, '${exam.attempts} lượt thi'),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _selectExam(exam),
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('Xem đề thi'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _examDetails() {
    final exam = _exam!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: () => setState(() => _page = _StudentPage.exams),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Danh sách đề thi'),
          ),
          const SizedBox(height: 12),
          _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _studentBadge(exam.code),
                const SizedBox(height: 14),
                Text(
                  exam.title,
                  style: const TextStyle(
                    color: _studentInk,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 22,
                  runSpacing: 12,
                  children: [
                    _metadata(Icons.quiz_outlined, '${exam.questionCount} câu'),
                    _metadata(
                      Icons.timer_outlined,
                      '${exam.durationMinutes} phút',
                    ),
                    _metadata(Icons.checklist_outlined, 'Chọn một đáp án A–D'),
                  ],
                ),
                const Divider(height: 32),
                const Text(
                  'Lưu ý trước khi thi',
                  style: TextStyle(
                    color: _studentInk,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Thời gian bắt đầu ngay khi bạn nhấn nút bên dưới. Bạn có thể chuyển câu hỏi, thay đổi lựa chọn và nộp bài trước khi hết giờ. Khi hết giờ, bài sẽ được nộp tự động.',
                  style: TextStyle(
                    color: _studentMuted,
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: _startExam,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Bắt đầu ca thi'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _takingExam() {
    final exam = _exam!;
    final questions = exam.questions;
    StudentQuestion? question;
    for (final item in questions) {
      if (item.number == _selectedQuestion) {
        question = item;
        break;
      }
    }
    final selectedQuestion = question;
    final passage = exam.passages
        .where((item) => item.number == selectedQuestion?.passageNumber)
        .firstOrNull;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: _studentLine)),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 14,
            runSpacing: 10,
            children: [
              Text(
                '${exam.code} · ${exam.title}',
                style: const TextStyle(
                  color: _studentInk,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.timer_outlined,
                    color: _remainingSeconds < 300
                        ? _studentRed
                        : _studentPurple,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _clock,
                    style: TextStyle(
                      color: _remainingSeconds < 300
                          ? _studentRed
                          : _studentInk,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 14),
                  FilledButton(
                    onPressed: _submitting ? null : _confirmSubmit,
                    child: Text(_submitting ? 'Đang nộp...' : 'Nộp bài'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 800;
              final questionPanel = selectedQuestion == null
                  ? const _StudentPanel(
                      child: Text('Đề thi không có câu hỏi để làm.'),
                    )
                  : _questionCard(selectedQuestion);
              final navigator = _questionNavigator(questions);
              if (narrow) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (passage != null) ...[
                        _passageCard(passage),
                        const SizedBox(height: 14),
                      ],
                      questionPanel,
                      const SizedBox(height: 14),
                      navigator,
                      const SizedBox(height: 14),
                      _questionControls(questions),
                    ],
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 250, child: navigator),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        children: [
                          if (passage != null) ...[
                            _passageCard(passage),
                            const SizedBox(height: 14),
                          ],
                          Expanded(
                            child: SingleChildScrollView(child: questionPanel),
                          ),
                          const SizedBox(height: 14),
                          _questionControls(questions),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _questionCard(StudentQuestion question) {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Câu ${question.number}',
            style: const TextStyle(
              color: _studentPurple,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          SelectableText(
            question.prompt,
            style: const TextStyle(
              color: _studentInk,
              fontWeight: FontWeight.w600,
              fontSize: 17,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          for (final key in ['A', 'B', 'C', 'D'])
            if (question.options.containsKey(key))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _answerOption(
                  question.number,
                  key,
                  question.options[key]!,
                ),
              ),
        ],
      ),
    );
  }

  Widget _answerOption(int questionNumber, String key, String text) {
    final selected = _answers[questionNumber] == key;
    return Material(
      color: selected ? _studentPalePurple : Colors.white,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => setState(() => _answers[questionNumber] = key),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? _studentPurple : _studentLine,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? _studentPurple : _studentMuted,
                size: 19,
              ),
              const SizedBox(width: 12),
              Text(
                '$key.',
                style: const TextStyle(
                  color: _studentInk,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: const TextStyle(height: 1.45))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _questionNavigator(List<StudentQuestion> questions) {
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Danh sách câu hỏi',
                  style: TextStyle(
                    color: _studentInk,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${_answers.length}/${questions.length}',
                style: const TextStyle(color: _studentMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final question in questions)
                InkWell(
                  onTap: () =>
                      setState(() => _selectedQuestion = question.number),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 38,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: question.number == _selectedQuestion
                          ? _studentPurple
                          : _answers.containsKey(question.number)
                          ? _studentPaleGreen
                          : _studentCanvas,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${question.number}',
                      style: TextStyle(
                        color: question.number == _selectedQuestion
                            ? Colors.white
                            : _answers.containsKey(question.number)
                            ? _studentGreen
                            : _studentMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _questionControls(List<StudentQuestion> questions) {
    final index = questions.indexWhere(
      (item) => item.number == _selectedQuestion,
    );
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: index > 0
              ? () => setState(
                  () => _selectedQuestion = questions[index - 1].number,
                )
              : null,
          icon: const Icon(Icons.arrow_back, size: 17),
          label: const Text('Câu trước'),
        ),
        const Spacer(),
        Text(
          '${index < 0 ? 0 : index + 1} / ${questions.length}',
          style: const TextStyle(color: _studentMuted),
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: index >= 0 && index < questions.length - 1
              ? () => setState(
                  () => _selectedQuestion = questions[index + 1].number,
                )
              : null,
          icon: const Icon(Icons.arrow_forward, size: 17),
          label: const Text('Câu tiếp'),
        ),
      ],
    );
  }

  Widget _passageCard(ExamPassage passage) => _panel(
    color: const Color(0xFFF9FAFC),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _studentBadge('ĐOẠN ĐỌC ${passage.number}'),
        const SizedBox(height: 10),
        SelectableText(
          passage.content,
          style: const TextStyle(color: _studentInk, height: 1.6),
        ),
      ],
    ),
  );

  Widget _resultPage() {
    final result = _result!;
    final passed = result.score >= 70;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panel(
            child: Center(
              child: Column(
                children: [
                  Icon(
                    passed
                        ? Icons.emoji_events_outlined
                        : Icons.assignment_turned_in_outlined,
                    size: 48,
                    color: passed ? _studentGreen : _studentPurple,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Kết quả bài thi',
                    style: TextStyle(
                      color: _studentInk,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${result.examCode} · ${result.examTitle}',
                    style: const TextStyle(color: _studentMuted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '${result.score.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: passed ? _studentGreen : _studentPurple,
                      fontSize: 48,
                      height: 1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${result.correctCount} / ${result.totalQuestions} câu đúng',
                    style: const TextStyle(
                      color: _studentInk,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _page = _StudentPage.exams;
                        _exam = null;
                        _result = null;
                      });
                      unawaited(_loadExams());
                    },
                    icon: const Icon(Icons.list_alt),
                    label: const Text('Về danh sách đề'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Xem lại đáp án',
            style: TextStyle(
              color: _studentInk,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          for (final question in result.questions) ...[
            _panel(
              color: question.isCorrect ? _studentPaleGreen : _studentPaleRed,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        question.isCorrect ? Icons.check_circle : Icons.cancel,
                        color: question.isCorrect ? _studentGreen : _studentRed,
                        size: 19,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Câu ${question.number}',
                        style: const TextStyle(
                          color: _studentInk,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(question.prompt),
                  const SizedBox(height: 8),
                  Text(
                    'Bạn chọn: ${question.selectedAnswer ?? 'Chưa trả lời'} · Đáp án đúng: ${question.correctAnswer}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (question.explanation.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      question.explanation,
                      style: const TextStyle(color: _studentMuted, height: 1.5),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _messagePanel({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: _panel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 38, color: _studentPurple),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _studentInk,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _studentMuted, height: 1.5),
            ),
            if (action != null) ...[const SizedBox(height: 16), action],
          ],
        ),
      ),
    ),
  );

  Widget _panel({required Widget child, Color color = Colors.white}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: _studentLine),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );

  Widget _metadata(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: _studentMuted),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(color: _studentMuted, fontSize: 12)),
    ],
  );

  Widget _studentBadge(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: _studentPalePurple,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: _studentPurple,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _StudentPanel extends StatelessWidget {
  const _StudentPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _studentLine),
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
}
