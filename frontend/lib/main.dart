import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'exam_api.dart';
import 'student_ui.dart';

const _ink = Color(0xFF182238);
const _muted = Color(0xFF6B7487);
const _line = Color(0xFFE5E8EF);
const _canvas = Color(0xFFF5F6FA);
const _purple = Color(0xFF4F46E5);
const _palePurple = Color(0xFFEEEDFF);
const _green = Color(0xFF087A55);
const _paleGreen = Color(0xFFEAF7F0);
const _red = Color(0xFFCE3434);
const _paleRed = Color(0xFFFFF0F0);

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.api, this.initialStudent});

  final ExamApi? api;
  final bool? initialStudent;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final ExamApi _api = widget.api ?? HttpExamApi();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'readia · Quản trị TOEIC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _canvas,
        colorScheme: ColorScheme.fromSeed(seedColor: _purple)
            .copyWith(primary: _purple, surface: Colors.white, error: _red),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: _ink, fontSize: 13),
          bodySmall: TextStyle(color: _muted, fontSize: 11),
          titleMedium: TextStyle(
            color: _ink,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 11,
          ),
          hintStyle: const TextStyle(color: Color(0xFF9AA2B1), fontSize: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _purple),
          ),
        ),
      ),
      home: _RoleSwitcher(
        api: _api,
        initialStudent: widget.initialStudent ?? Uri.base.path == '/student',
      ),
    );
  }
}

class _RoleSwitcher extends StatefulWidget {
  const _RoleSwitcher({required this.api, required this.initialStudent});

  final ExamApi api;
  final bool initialStudent;

  @override
  State<_RoleSwitcher> createState() => _RoleSwitcherState();
}

class _RoleSwitcherState extends State<_RoleSwitcher> {
  late bool _isStudent = widget.initialStudent;

  @override
  Widget build(BuildContext context) {
    return _isStudent
        ? StudentPortal(
            api: widget.api,
            onSwitchToTeacher: () => setState(() => _isStudent = false),
          )
        : AdminShell(
            api: widget.api,
            onSwitchToStudent: () => setState(() => _isStudent = true),
          );
  }
}

enum _Page { exams, importWord, preview, analytics }

class _Exam {
  _Exam({
    this.id = '',
    required this.title,
    required this.code,
    required this.updated,
    required this.published,
    this.questionCount = 0,
    this.issueCount = 0,
    this.attempts = 0,
    this.average = '—',
  });

  final String id;
  final String title;
  final String code;
  final String updated;
  bool published;
  final int questionCount;
  final int issueCount;
  final int attempts;
  final String average;

  factory _Exam.fromApi(ExamSummary exam) => _Exam(
    id: exam.id,
    title: exam.title,
    code: exam.code,
    updated: _formatDate(exam.updatedAt),
    published: exam.isPublished,
    questionCount: exam.questionCount,
    issueCount: exam.issueCount,
    attempts: exam.attempts,
    average: exam.averageScore?.toStringAsFixed(1).replaceAll('.', ',') ?? '—',
  );
}

class _ImportIssue {
  const _ImportIssue({
    required this.code,
    required this.title,
    required this.description,
    required this.line,
    required this.example,
    this.questionNumber,
  });

  final String code;
  final String title;
  final String description;
  final int line;
  final int? questionNumber;
  final String example;

  String get location => questionNumber == null
      ? 'Dòng $line'
      : 'Dòng $line · Câu $questionNumber';

  factory _ImportIssue.fromApi(ExamIssue issue) => _ImportIssue(
    code: issue.code,
    title: issue.title,
    description: issue.description,
    line: issue.line,
    questionNumber: issue.questionNumber,
    example: issue.example,
  );
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key, this.api, this.onSwitchToStudent});

  final ExamApi? api;
  final VoidCallback? onSwitchToStudent;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _searchController = TextEditingController();
  late final ExamApi _api = widget.api ?? HttpExamApi();
  _Page _page = _Page.exams;
  String _previewTitle = '';
  String _previewCode = '';
  String _previewUpdated = '';
  String? _currentExamId;
  ExamDetail? _currentExam;
  ExamStats? _stats;
  bool _previewingPublishedExam = false;
  int _selectedQuestionNumber = 1;
  String _filter = 'Tất cả';
  String _sort = 'Mới nhất';
  int _currentPage = 0;
  String _fileName = '';
  int _fileSize = 0;
  bool _hasFile = false;
  bool _validated = false;
  bool _showAllIssues = false;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  List<_ImportIssue> _issues = [];
  List<_Exam> _exams = [];

  @override
  void initState() {
    super.initState();
    unawaited(_refreshDashboard(showError: false));
  }

  Future<void> _refreshDashboard({bool showError = true}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final exams = await _api.listExams();
      final stats = await _api.getStats();
      if (!mounted) return;
      setState(() {
        _exams = exams.map(_Exam.fromApi).toList();
        _stats = stats;
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
      if (showError) _showMessage('Không thể tải dữ liệu từ máy chủ: $error');
    }
  }

  void _applyDetail(ExamDetail detail) {
    _currentExamId = detail.id;
    _currentExam = detail;
    _previewTitle = detail.title;
    _previewCode = detail.code;
    _previewUpdated = _formatDate(detail.updatedAt);
    _fileName = detail.fileName;
    _hasFile = true;
    _issues = detail.issues.map(_ImportIssue.fromApi).toList();
    _validated = detail.questionCount == 100 && _issues.isEmpty;
    _selectedQuestionNumber = detail.questions.isEmpty
        ? 1
        : detail.questions.first.number;
  }

  Future<void> _openImportForExam(_Exam exam) async {
    setState(() {
      _page = _Page.importWord;
      _saving = true;
      _loadError = null;
      _currentExamId = exam.id;
      _previewingPublishedExam = false;
    });
    try {
      final detail = await _api.getExam(exam.id);
      if (!mounted) return;
      setState(() {
        _applyDetail(detail);
        _saving = false;
        _fileSize = 0;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _loadError = error.toString();
      });
      _showMessage('Không thể tải đề ${exam.code}: $error');
    }
  }

  void _startNewImport() {
    setState(() {
      _page = _Page.importWord;
      _currentExamId = null;
      _currentExam = null;
      _fileName = '';
      _fileSize = 0;
      _hasFile = false;
      _validated = false;
      _issues = [];
      _previewingPublishedExam = false;
      _loadError = null;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _pageTitle => switch (_page) {
    _Page.exams => 'Đề thi',
    _Page.importWord => 'Nhập đề Word',
    _Page.preview => 'Xem trước đề',
    _Page.analytics => 'Thống kê',
  };

  void _navigate(_Page page) {
    if (page == _Page.preview && !_validated && !_previewingPublishedExam) {
      page = _Page.importWord;
      _showMessage('Hãy kiểm tra đề hợp lệ trước khi xem trước.');
    }
    setState(() {
      _page = page;
      _showAllIssues = false;
      if (page != _Page.preview) _previewingPublishedExam = false;
    });
    if (MediaQuery.sizeOf(context).width < 920) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _openExamPreview(_Exam exam) async {
    if (!exam.published) {
      await _openImportForExam(exam);
      return;
    }
    setState(() {
      _saving = true;
      _loadError = null;
    });
    try {
      final detail = await _api.getExam(exam.id);
      if (!mounted) return;
      setState(() {
        _applyDetail(detail);
        _previewingPublishedExam = true;
        _page = _Page.preview;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage('Không thể tải nội dung đề ${exam.code}: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Future<void> _pickDocument() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['docx'],
      );
      if (files.isEmpty) return;
      final file = files.single;
      final bytes = await file.xFile.readAsBytes();
      final fileSize = bytes.length;
      if (fileSize == 0) {
        _showMessage('Tệp đã chọn đang trống.');
        return;
      }
      if (fileSize > 20 * 1024 * 1024) {
        _showMessage('File vượt quá giới hạn 20 MB.');
        return;
      }
      setState(() {
        _validated = false;
        _saving = true;
        _loadError = null;
      });
      final currentId = _currentExamId;
      final detail = currentId == null
          ? await _api.importDocument(file.name, bytes)
          : await _api.replaceDocument(currentId, file.name, bytes);
      if (!mounted) return;
      setState(() {
        _applyDetail(detail);
        _fileSize = fileSize;
        _saving = false;
      });
      await _refreshDashboard();
      _showMessage('Đã tải ${file.name} lên máy chủ và phân tích nội dung.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _loadError = error.toString();
      });
      _showMessage('Không thể tải hoặc phân tích file: $error');
    }
  }

  Future<void> _editIssue(_ImportIssue issue) async {
    ExamQuestion? question;
    for (final item in _currentExam?.questions ?? const <ExamQuestion>[]) {
      if (item.number == issue.questionNumber) {
        question = item;
        break;
      }
    }
    if (question != null) {
      await _editQuestion(question);
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cần sửa tệp Word gốc'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(issue.location, style: const TextStyle(color: _muted)),
              const SizedBox(height: 8),
              Text(issue.description),
              if (issue.example.isNotEmpty) ...[
                const SizedBox(height: 12),
                SelectableText(issue.example),
              ],
              const SizedBox(height: 12),
              const Text(
                'Hãy sửa nội dung trong Word rồi tải lại tệp. Máy chủ sẽ phân tích lại toàn bộ đề.',
                style: TextStyle(color: _muted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Future<void> _editQuestion(ExamQuestion question) async {
    if (_currentExam?.isPublished == true) {
      _showMessage('Không thể sửa trực tiếp đề đã xuất bản.');
      return;
    }

    final updatedQuestion = await showDialog<ExamQuestion>(
      context: context,
      builder: (_) => _EditQuestionDialog(question: question),
    );

    if (updatedQuestion == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final examId = _currentExamId;
      if (examId == null) {
        throw StateError('Không tìm thấy đề thi cần cập nhật.');
      }
      final detail = await _api.updateQuestion(examId, updatedQuestion);
      if (!mounted) return;
      setState(() {
        _applyDetail(detail);
        _saving = false;
      });
      await _refreshDashboard();
      _showMessage('Đã lưu nội dung câu ${question.number}.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage('Không thể lưu nội dung câu hỏi: $error');
    }
  }

  Future<void> _validateImport() async {
    if (!_hasFile) {
      _showMessage('Vui lòng chọn file .docx trước khi kiểm tra.');
      return;
    }
    final id = _currentExamId;
    if (id == null) {
      _showMessage('Tải tệp Word lên máy chủ trước khi kiểm tra.');
      return;
    }
    setState(() => _saving = true);
    try {
      final detail = await _api.validate(id);
      if (!mounted) return;
      setState(() {
        _applyDetail(detail);
        _saving = false;
      });
      await _refreshDashboard();
      _showMessage(
        _validated
            ? 'Đề hợp lệ 100/100 câu.'
            : 'Còn ${_issues.length} lỗi cần xử lý trong tệp Word.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage('Không thể kiểm tra đề trên máy chủ: $error');
    }
  }

  Future<void> _publishExam() async {
    final examId = _currentExamId;
    if (examId == null || !_validated || _issues.isNotEmpty) {
      _showMessage('Hãy sửa hết lỗi và kiểm tra lại đề trước khi xuất bản.');
      return;
    }
    final publish = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xuất bản đề thi?'),
        content: const Text(
          'Đề thi sẽ xuất hiện trong danh sách dành cho sinh viên. '
          'Bạn có thể kiểm tra nội dung lần cuối trước khi xác nhận.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Quay lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xuất bản ngay'),
          ),
        ],
      ),
    );
    if (publish != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final detail = await _api.publish(examId);
      if (!mounted) return;
      setState(() {
        _applyDetail(detail);
        _previewingPublishedExam = true;
        _page = _Page.preview;
        _saving = false;
      });
      await _refreshDashboard();
      _showMessage('Đã xuất bản ${detail.title}.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage('Máy chủ không thể xuất bản đề: $error');
    }
  }

  List<_Exam> get _visibleExams {
    final query = _searchController.text.trim().toLowerCase();
    final result = _exams.where((exam) {
      final matchesTab = switch (_filter) {
        'Đã xuất bản' => exam.published,
        'Bản nháp' => !exam.published,
        _ => true,
      };
      return matchesTab &&
          (query.isEmpty ||
              exam.title.toLowerCase().contains(query) ||
              exam.code.toLowerCase().contains(query));
    }).toList();
    if (_sort == 'Lượt thi') {
      result.sort((a, b) => b.attempts.compareTo(a.attempts));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 920;
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: _canvas,
          drawer: compact ? Drawer(width: 260, child: _sidebar()) : null,
          body: Row(
            children: [
              if (!compact) SizedBox(width: 220, child: _sidebar()),
              Expanded(
                child: Column(
                  children: [
                    _topBar(compact),
                    Expanded(
                      child: Container(
                        color: _canvas,
                        child: SingleChildScrollView(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 16 : 28,
                            vertical: compact ? 20 : 28,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1440),
                              child: _buildPage(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sidebar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: _line)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 18, 15, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 30),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _purple,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(
                        Icons.menu_book_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 9),
                    const Text(
                      'readia',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                        letterSpacing: -.7,
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 2, bottom: 8),
                child: Text(
                  'KHÔNG GIAN GIẢNG VIÊN',
                  style: TextStyle(
                    color: Color(0xFF929AA9),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .2,
                  ),
                ),
              ),
              _navItem('Đề thi', Icons.folder_copy_outlined, _Page.exams),
              _navItem(
                'Nhập đề Word',
                Icons.note_add_outlined,
                _Page.importWord,
              ),
              _navItem('Xem trước đề', Icons.center_focus_weak, _Page.preview),
              _navItem('Thống kê', Icons.query_stats, _Page.analytics),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed:
                      widget.onSwitchToStudent ??
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => StudentPortal(api: _api),
                        ),
                      ),
                  icon: const Icon(Icons.school_outlined, size: 17),
                  label: const Text('Khu vực học viên'),
                ),
              ),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFC),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Học kỳ I · 2026–2027',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Trung tâm Ngoại ngữ\nBộ môn tiếng Anh',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 10,
                        height: 1.5,
                      ),
                    ),
                    SizedBox(height: 8),
                    _Badge(
                      'Gói học thuật',
                      color: _purple,
                      background: _palePurple,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _showMessage(
                  'Mỗi đề cần đủ 100 câu, 4 lựa chọn A–D, đáp án và lời giải.',
                ),
                icon: const Icon(Icons.help_outline, size: 17),
                label: const Text('Hướng dẫn nhập đề'),
                style: TextButton.styleFrom(
                  foregroundColor: _muted,
                  textStyle: const TextStyle(fontSize: 11),
                ),
              ),
              const Divider(color: _line),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: _palePurple,
                  child: Text(
                    'HL',
                    style: TextStyle(
                      color: _purple,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                title: Text(
                  'Hoàng Lan',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                subtitle: Text(
                  'Giảng viên',
                  style: TextStyle(color: _muted, fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(String label, IconData icon, _Page page) {
    final active = _page == page;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: active ? _palePurple : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => _navigate(page),
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 42,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: active ? _purple : _muted),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: TextStyle(
                      color: active ? _purple : _muted,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(bool compact) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          if (compact) ...[
            IconButton(
              tooltip: 'Mở menu',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              icon: const Icon(Icons.menu, size: 20),
            ),
            const SizedBox(width: 4),
          ],
          const Text(
            'Quản trị TOEIC',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Icon(Icons.chevron_right, color: _muted, size: 16),
          ),
          Text(
            _pageTitle,
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
          const Spacer(),
          if (!compact)
            const _Badge(
              'Năm học 2026–2027',
              color: _muted,
              background: _canvas,
            ),
          IconButton(
            tooltip: 'Thông báo',
            onPressed: () => _showMessage('Bạn đã xem thông báo mới nhất.'),
            icon: const Icon(Icons.notifications_none, color: _muted, size: 19),
          ),
          const Text('VI', style: TextStyle(color: _muted, fontSize: 11)),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_loadError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _StatusBanner(
            success: false,
            title: 'Không thể kết nối máy chủ đề thi',
            message: _loadError!,
            action: TextButton.icon(
              onPressed: () => _refreshDashboard(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Thử lại'),
            ),
          ),
        ),
      if (_loading)
        const Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: LinearProgressIndicator(),
        ),
      if (_saving)
        const Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: LinearProgressIndicator(),
        ),
      switch (_page) {
        _Page.exams => _buildDashboard(),
        _Page.importWord => _buildImportPage(),
        _Page.preview => _buildPreviewPage(),
        _Page.analytics => _buildAnalyticsPage(),
      },
    ],
  );

  Widget _pageHeading({
    required String eyebrow,
    required String title,
    required String description,
    Widget? trailing,
  }) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 14,
      children: [
        SizedBox(
          width: trailing == null ? double.infinity : 650,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: const TextStyle(
                  color: _purple,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .2,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 25,
                  letterSpacing: -.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _buildDashboard() {
    final publishedCount = _exams.where((exam) => exam.published).length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cardWidth = width < 570
            ? width
            : (width - (width < 1050 ? 16 : 48)) / (width < 1050 ? 2 : 4);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _pageHeading(
              eyebrow: 'Quản lý học liệu',
              title: 'Ngân hàng đề thi',
              description: 'Tổ chức đề Reading, kiểm soát chất lượng và theo dõi việc luyện thi.',
              trailing: _FilledAction(
                label: 'Nhập đề Word',
                icon: Icons.add,
                onPressed: _startNewImport,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 14,
              children: [
                SizedBox(
                  width: cardWidth,
                  child: _MetricCard(
                    label: 'Tổng số đề',
                    value: '${_stats?.totalExams ?? _exams.length}',
                    note:
                        '${_stats?.draftExams ?? _exams.length - publishedCount} bản nháp đang chuẩn bị',
                    icon: Icons.folder_copy_outlined,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _MetricCard(
                    label: 'Đã xuất bản',
                    value: '${_stats?.publishedExams ?? publishedCount}',
                    note: 'Sẵn sàng cho sinh viên',
                    icon: Icons.check_circle_outline,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _MetricCard(
                    label: 'Lượt thi trong tháng',
                    value: (_stats?.monthlyAttempts ?? 0).toString(),
                    note: 'Tổng lượt thi đã ghi nhận',
                    icon: Icons.people_outline,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _MetricCard(
                    label: 'Điểm trung bình',
                    value: (_stats?.averageScore ?? 0)
                        .toStringAsFixed(1)
                        .replaceAll('.', ','),
                    note: 'Theo các đề đã xuất bản',
                    icon: Icons.query_stats,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildExamTable(),
            const SizedBox(height: 18),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: width < 880 ? width : (width - 16) * .46,
                  child: _Panel(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.verified_user_outlined,
                          color: _purple,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Chất lượng trước khi xuất bản',
                                style: TextStyle(
                                  color: _ink,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Mỗi đề được kiểm tra đủ 100 câu, 4 đáp án A–D và lời giải. Chỉ đề hợp lệ mới được mở cho sinh viên.',
                                style: TextStyle(
                                  color: _muted,
                                  height: 1.5,
                                  fontSize: 11,
                                ),
                              ),
                              TextButton(
                                onPressed: () => _navigate(_Page.importWord),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 30),
                                ),
                                child: const Text(
                                  'Xem quy chuẩn nhập .docx →',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: width < 880 ? width : (width - 16) * .54,
                  child: _Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Hoạt động gần đây',
                                style: TextStyle(
                                  color: _ink,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Text(
                              'Hôm nay',
                              style: TextStyle(color: _muted, fontSize: 10),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _exams.isEmpty
                              ? 'Chưa có đề thi trong hệ thống.'
                              : '${_exams.length} đề thi đã được đồng bộ từ máy chủ.',
                          style: const TextStyle(color: _ink, fontSize: 11),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _Badge(
                              '${_stats?.publishedExams ?? publishedCount} đề đã xuất bản',
                              color: _green,
                              background: _paleGreen,
                            ),
                            const Text(
                              'Dữ liệu từ API',
                              style: TextStyle(color: _muted, fontSize: 10),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildExamTable() {
    final exams = _visibleExams;
    const pageSize = 6;
    final pageCount = (exams.length / pageSize).ceil().clamp(1, 999);
    final currentPage = _currentPage.clamp(0, pageCount - 1);
    final start = currentPage * pageSize;
    final pageExams = exams.skip(start).take(pageSize).toList();
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 14),
            child: Wrap(
              spacing: 10,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final tab in ['Tất cả', 'Đã xuất bản', 'Bản nháp'])
                  _FilterTab(
                    label:
                        '$tab (${tab == 'Tất cả'
                            ? _exams.length
                            : tab == 'Đã xuất bản'
                            ? _exams.where((exam) => exam.published).length
                            : _exams.where((exam) => !exam.published).length})',
                    active: _filter == tab,
                    onTap: () => setState(() {
                      _filter = tab;
                      _currentPage = 0;
                    }),
                  ),
                SizedBox(
                  width: 215,
                  child: TextField(
                    key: const Key('examSearchField'),
                    controller: _searchController,
                    onChanged: (_) => setState(() => _currentPage = 0),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Tìm tên hoặc mã đề...',
                      prefixIcon: Icon(Icons.search, size: 17, color: _muted),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Sắp xếp danh sách',
                  onSelected: (value) => setState(() => _sort = value),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'Mới nhất', child: Text('Mới nhất')),
                    PopupMenuItem(value: 'Lượt thi', child: Text('Lượt thi')),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: _line),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.filter_list, size: 16, color: _ink),
                        const SizedBox(width: 7),
                        Text(
                          _sort,
                          style: const TextStyle(color: _ink, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _line),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 880,
              child: Column(
                children: [
                  const _TableHeader(),
                  if (pageExams.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        _exams.isEmpty
                            ? 'Chưa có đề thi. Hãy nhấn “Nhập đề Word” để tạo đề.'
                            : 'Không tìm thấy đề thi phù hợp.',
                        style: TextStyle(color: _muted),
                      ),
                    ),
                  for (final exam in pageExams)
                    _ExamRow(
                      exam: exam,
                      onOpen: () => _openExamPreview(exam),
                      onPreview: () => _openExamPreview(exam),
                      onImport: () {
                        _openImportForExam(exam);
                      },
                      onDelete: () => _deleteDraft(exam),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: _line),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    exams.isEmpty
                        ? 'Không có đề thi'
                        : 'Hiển thị ${start + 1}–${start + pageExams.length} trong ${exams.length} đề thi',
                    style: const TextStyle(color: _muted, fontSize: 10),
                  ),
                ),
                OutlinedButton(
                  onPressed: currentPage > 0
                      ? () => setState(() => _currentPage = currentPage - 1)
                      : null,
                  child: const Text('Trước'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    '${currentPage + 1} / $pageCount',
                    style: const TextStyle(color: _purple, fontSize: 11),
                  ),
                ),
                OutlinedButton(
                  onPressed: currentPage + 1 < pageCount
                      ? () => setState(() => _currentPage = currentPage + 1)
                      : null,
                  child: const Text('Sau'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteDraft(_Exam exam) async {
    if (exam.published) {
      _showMessage('Chỉ có thể xóa đề ở trạng thái bản nháp.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa bản nháp?'),
        content: Text('Bạn có chắc muốn xóa “${exam.title}”?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xóa đề'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await _api.delete(exam.id);
        if (!mounted) return;
        if (_currentExamId == exam.id) _startNewImport();
        await _refreshDashboard();
        _showMessage('Đã xóa bản nháp ${exam.code}.');
      } catch (error) {
        _showMessage('Không thể xóa bản nháp trên máy chủ: $error');
      }
    }
  }

  Widget _buildImportPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeading(
          eyebrow: 'Quy trình nhập đề',
          title: 'Nhập đề từ Word',
          description: _currentExam == null
              ? 'Tạo đề mới · Tải tài liệu .docx để lưu trên hệ thống.'
              : '${_currentExam!.title} · Chuẩn bị đề trước khi xuất bản.',
          trailing: OutlinedButton.icon(
            onPressed: _showFormatGuide,
            icon: const Icon(Icons.download_outlined, size: 17),
            label: const Text('Quy chuẩn .docx'),
          ),
        ),
        const SizedBox(height: 18),
        _stepIndicator(),
        const SizedBox(height: 18),
        _StatusBanner(
          success: _validated,
          title: _validated
              ? 'Đề đã sẵn sàng để xem trước và xuất bản'
              : !_hasFile
              ? 'Chưa có tệp Word'
              : 'Tệp đã được tải lên hệ thống',
          message: _validated
              ? 'Đề đã đạt điều kiện chuẩn và có thể dùng cho kiểm tra.'
              : !_hasFile
              ? 'Chọn tệp .docx để bắt đầu. Sau đó có thể kiểm tra và xuất bản.'
              : 'Bạn có thể kiểm tra lại hoặc xem trước đề trên giao diện web.',
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 850) {
              return Column(
                children: [
                  _fileColumn(),
                  const SizedBox(height: 16),
                  _issuesColumn(),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: _fileColumn()),
                const SizedBox(width: 18),
                Expanded(flex: 8, child: _issuesColumn()),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 14,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 15, color: _muted),
                SizedBox(width: 7),
                Text(
                  'Chỉ xuất bản khi đề đã hoàn tất và hợp lệ.',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
            _FilledAction(
              label: 'Tải lại & kiểm tra',
              icon: Icons.sync,
              onPressed: _validateImport,
            ),
            _FilledAction(
              label: 'Xem trước',
              icon: Icons.visibility_outlined,
              onPressed: _validated ? () => _navigate(_Page.preview) : null,
            ),
            _FilledAction(
              label: 'Xuất bản',
              icon: Icons.lock_outline,
              onPressed: _validated ? _publishExam : null,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            'Dữ liệu đề được lưu trên backend và có thể thao tác trực tiếp trong giao diện web.',
            style: const TextStyle(color: _muted, fontSize: 9),
          ),
        ),
      ],
    );
  }

  Widget _stepIndicator() {
    return _Panel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Wrap(
        spacing: 18,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _StepItem(number: '1', label: 'Tải tệp Word', complete: _hasFile),
          const Icon(Icons.chevron_right, size: 17, color: _muted),
          _StepItem(
            number: '2',
            label: 'Kiểm tra và sửa lỗi',
            complete: _page == _Page.importWord,
          ),
          const Icon(Icons.chevron_right, size: 17, color: _muted),
          _StepItem(
            number: '3',
            label: 'Xem trước & xuất bản',
            complete: _validated,
          ),
        ],
      ),
    );
  }

  Widget _fileColumn() {
    return Column(
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Tệp nguồn',
                      style: TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const _Badge(
                    '.docx',
                    color: _purple,
                    background: _palePurple,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Material(
                color: const Color(0xFFF9FAFC),
                borderRadius: BorderRadius.circular(9),
                child: InkWell(
                  onTap: _pickDocument,
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 17,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _purple,
                        style: BorderStyle.solid,
                      ),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.upload_file_outlined,
                          color: _purple,
                          size: 25,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          _hasFile ? _fileName : 'Kéo thả tệp .docx vào đây',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          _hasFile
                              ? '${_formatSize(_fileSize)} · Tệp Word đã chọn'
                              : 'Tối đa 20 MB · Chỉ nhận file .docx',
                          style: const TextStyle(color: _muted, fontSize: 10),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _pickDocument,
                          icon: const Icon(Icons.drive_folder_upload, size: 16),
                          label: Text(_hasFile ? 'Chọn tệp khác' : 'Chọn tệp'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Đã quét toàn bộ tệp',
                      style: TextStyle(color: _muted, fontSize: 10),
                    ),
                  ),
                  Text(
                    _validated
                        ? '${_currentExam?.questionCount ?? 0} câu · Hợp lệ'
                        : _issues.isEmpty
                        ? 'Chưa kiểm tra'
                        : '${_currentExam?.questionCount ?? 0} câu · ${_issues.length} lỗi',
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const Divider(height: 20, color: _line),
              Row(
                children: [
                  Icon(
                    _validated
                        ? Icons.check_circle_outline
                        : Icons.storage_outlined,
                    size: 15,
                    color: _validated ? _green : _red,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _validated
                        ? 'Nội dung đã sẵn sàng để lưu'
                        : 'Chưa lưu bất kỳ câu hỏi nào',
                    style: TextStyle(
                      color: _validated ? _green : _red,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _formatStandards(),
      ],
    );
  }

  Widget _formatStandards() {
    const tags = [
      ('[PASSAGE] / [PASSAGES]', 'Mở một nhóm đoạn văn / hình ảnh.'),
      ('[QUESTION]', 'Bắt đầu câu hỏi và số thứ tự.'),
      ('[OPTION]', 'Từng lựa chọn A–D; đánh dấu đáp án đúng.'),
      ('[EXPLANATION]', 'Lời giải sau mỗi câu hỏi.'),
    ];
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quy chuẩn tags bắt buộc',
            style: TextStyle(
              color: _ink,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          for (final tag in tags) ...[
            Text(
              tag.$1,
              style: const TextStyle(
                color: _purple,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 3),
            Text(tag.$2, style: const TextStyle(color: _muted, fontSize: 10)),
            const SizedBox(height: 9),
          ],
          const Divider(height: 12, color: _line),
          const Text(
            'Part 5 là câu độc lập, không cần [PASSAGE]. Part 6–7 phải có nhóm và nội dung đi kèm.',
            style: TextStyle(color: _muted, fontSize: 10, height: 1.5),
          ),
          const SizedBox(height: 8),
          const Text(
            'Cũng hỗ trợ mẫu [Q:n], [TEXT], [A]–[D], [KEY], [HINT] và [PASSAGE] của file Reading_v07_tagged.',
            style: TextStyle(color: _muted, fontSize: 10, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _issuesColumn() {
    final shownIssues = _showAllIssues ? _issues : _issues.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Tài liệu đã xử lý',
                      style: TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  _Badge(
                    _issues.isEmpty ? 'Đã ổn' : '${_issues.length} cần xem lại',
                    color: _issues.isEmpty ? _green : _red,
                    background: _issues.isEmpty ? _paleGreen : _paleRed,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_issues.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          color: _green,
                          size: 28,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Không phát hiện lỗi cần sửa',
                          style: TextStyle(
                            color: _green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                for (final issue in shownIssues)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _IssueCard(
                      issue: issue,
                      onTap: () => _editIssue(issue),
                    ),
                  ),
              if (_issues.length > 3)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () =>
                        setState(() => _showAllIssues = !_showAllIssues),
                    child: Text(_showAllIssues ? 'Thu gọn' : 'Xem thêm'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showFormatGuide() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quy chuẩn tệp .docx'),
        content: const SizedBox(
          width: 480,
          child: Text(
            'Mỗi đề có thể được upload và lưu trên hệ thống. Sau khi tải lên, '
            'sẽ được phân tích tự động để kiểm tra nội dung và chuẩn bị xuất bản. '
            'Tệp hỗ trợ dạng DOCX, có thể dùng cho các đề TOEIC dạng truyền thống '
            'hoặc theo định dạng chuẩn đã được cấu hình trong backend. '
            'Dung lượng tối đa 20 MB.',
            style: TextStyle(height: 1.55),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Đã hiểu'),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeading(
          eyebrow: 'Sẵn sàng xuất bản',
          title: _previewTitle,
          description: _previewingPublishedExam
              ? 'Đã xuất bản · $_previewCode · Cập nhật $_previewUpdated'
              : 'Bản nháp · $_fileName · Đã nhập lúc 09:24, 17/10/2026',
          trailing: Wrap(
            spacing: 10,
            children: _previewingPublishedExam
                ? [
                    OutlinedButton(
                      onPressed: () => _navigate(_Page.exams),
                      child: const Text('Về danh sách đề'),
                    ),
                  ]
                : [
                    OutlinedButton(
                      onPressed: () => _navigate(_Page.importWord),
                      child: const Text('Quay lại chỉnh sửa'),
                    ),
                    _FilledAction(
                      label: 'Xuất bản đề',
                      icon: Icons.send_outlined,
                      onPressed: _publishExam,
                    ),
                  ],
          ),
        ),
        const SizedBox(height: 18),
        _StatusBanner(
          success:
              _currentExam?.issueCount == 0 &&
              _currentExam?.questionCount == 100,
          title: _currentExam?.isPublished == true
              ? 'Đề đã xuất bản · ${_currentExam?.questionCount ?? 0}/100 câu'
              : 'Đã kiểm tra ${_currentExam?.questionCount ?? 0}/100 câu · Chưa xuất bản',
          message: _currentExam?.issues.isEmpty == true
              ? 'Dữ liệu xem trước được tải từ backend. Đề chỉ hiển thị cho sinh viên sau khi xuất bản.'
              : 'Đề còn ${_currentExam?.issues.length ?? 0} lỗi. Có thể sửa câu hỏi trong bản nháp; lỗi cấu trúc tài liệu cần sửa trong Word.',
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final stats = Wrap(
              spacing: 14,
              runSpacing: 10,
              children: [
                _PreviewStat(
                  label: 'CẤU TRÚC',
                  value: '${_currentExam?.questionCount ?? 0} câu',
                  icon: Icons.layers_outlined,
                ),
                _PreviewStat(
                  label: 'NHÓM ĐOẠN ĐỌC',
                  value: '${_currentExam?.passages.length ?? 0} nhóm',
                  icon: Icons.menu_book_outlined,
                ),
                _PreviewStat(
                  label: 'LƯỢT THI',
                  value: '${_currentExam?.attempts ?? 0}',
                  icon: Icons.people_outline,
                ),
              ],
            );
            return Column(
              children: [
                stats,
                const SizedBox(height: 16),
                if (constraints.maxWidth < 920)
                  Column(
                    children: [
                      _questionNavigation(),
                      const SizedBox(height: 14),
                      _passagePreview(),
                      const SizedBox(height: 14),
                      _questionPreview(),
                      const SizedBox(height: 14),
                      _reviewPanel(),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 205, child: _questionNavigation()),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          children: [
                            _passagePreview(),
                            const SizedBox(height: 14),
                            _questionPreview(),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(width: 230, child: _reviewPanel()),
                    ],
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _questionNavigation() {
    final questions = _currentExam?.questions ?? const <ExamQuestion>[];
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cấu trúc đề',
            style: TextStyle(
              color: _ink,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 11),
          Text(
            '${_currentExam?.passages.length ?? 0} đoạn đọc trong tài liệu',
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
          const Divider(color: _line),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Tất cả câu hỏi',
                  style: TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
              Text(
                '${questions.length}/100',
                style: TextStyle(
                  color: questions.length == 100 ? _green : _red,
                  fontSize: 9,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          if (questions.isEmpty)
            const Text(
              'Chưa có câu hỏi để xem.',
              style: TextStyle(color: _muted, fontSize: 10),
            )
          else
            Text(
              'Chọn một câu hỏi',
              style: const TextStyle(color: _ink, fontSize: 10),
            ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final question in questions)
                InkWell(
                  onTap: () =>
                      setState(() => _selectedQuestionNumber = question.number),
                  child: Container(
                    width: 27,
                    height: 25,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: question.number == _selectedQuestionNumber
                          ? _purple
                          : _paleGreen,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${question.number}',
                      style: TextStyle(
                        color: question.number == _selectedQuestionNumber
                            ? Colors.white
                            : _green,
                        fontSize: 8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            questions.isEmpty
                ? 'Không có câu hỏi trong bản xem trước.'
                : 'Đang xem câu $_selectedQuestionNumber/${questions.length}.',
            style: TextStyle(color: _muted, fontSize: 9, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _passagePreview() {
    final question = _selectedQuestion;
    final passageNumber = question?.passageNumber;
    ExamPassage? passage;
    for (final item in _currentExam?.passages ?? const <ExamPassage>[]) {
      if (item.number == passageNumber) passage = item;
    }
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Badge(
                passage == null
                    ? 'KHÔNG CÓ ĐOẠN ĐỌC'
                    : 'ĐOẠN ĐỌC ${passage.number}',
                color: _purple,
                background: _palePurple,
              ),
              const Spacer(),
              Text(
                question == null ? '—' : 'Câu ${question.number}',
                style: const TextStyle(color: _muted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            passage == null
                ? 'Câu hỏi độc lập hoặc chưa có đoạn đọc được liên kết.'
                : 'Nội dung đoạn đọc lấy từ tệp Word đã lưu.',
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFC),
              border: Border.all(color: _line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              passage?.content ?? 'Không có nội dung đoạn đọc cho câu này.',
              style: const TextStyle(color: _ink, height: 1.6, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _questionPreview() {
    final question = _selectedQuestion;
    if (question == null) {
      return const _Panel(
        child: Text(
          'Chưa có câu hỏi để xem. Hãy tải tài liệu Word lên backend trước.',
          style: TextStyle(color: _muted, fontSize: 11),
        ),
      );
    }
    final optionKeys = question.options.keys.toList()..sort();
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Câu ${question.number}',
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              _Badge(
                'Đáp án đúng: ${question.answer}',
                color: _green,
                background: _paleGreen,
              ),
              if (_currentExam?.isPublished != true)
                Tooltip(
                  message: 'Chỉnh sửa câu ${question.number}',
                  child: TextButton.icon(
                    onPressed: () => _editQuestion(question),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Sửa'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 36),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(
            question.prompt,
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          for (final key in optionKeys)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: key == question.answer ? _paleGreen : Colors.white,
                  border: Border.all(
                    color: key == question.answer ? _green : _line,
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: SelectableText(
                  '$key   ${question.options[key]}',
                  style: const TextStyle(color: _ink, fontSize: 11),
                ),
              ),
            ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _paleGreen,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              'LỜI GIẢI · CHỈ GIẢNG VIÊN\n${question.explanation}',
              style: const TextStyle(color: _green, fontSize: 10, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  ExamQuestion? get _selectedQuestion {
    for (final question in _currentExam?.questions ?? const <ExamQuestion>[]) {
      if (question.number == _selectedQuestionNumber) return question;
    }
    final questions = _currentExam?.questions ?? const <ExamQuestion>[];
    return questions.isEmpty ? null : questions.first;
  }

  Widget _reviewPanel() {
    final exam = _currentExam;
    final checks = [
      ('Số câu: ${exam?.questionCount ?? 0}/100', exam?.questionCount == 100),
      (
        'Đáp án và lời giải đầy đủ',
        exam?.issues.isEmpty == true && exam?.questionCount == 100,
      ),
      ('${exam?.passages.length ?? 0} đoạn đọc được phân tích', true),
      (
        'Lỗi định dạng: ${exam?.issues.length ?? 0}',
        exam?.issues.isEmpty == true,
      ),
    ];
    return Column(
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Kiểm duyệt nội dung',
                style: TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
              for (final check in checks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        check.$2
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: check.$2 ? _green : _red,
                        size: 14,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          check.$1,
                          style: const TextStyle(color: _ink, fontSize: 9),
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(color: _line),
              _Badge(
                exam?.issueCount == 0 && exam?.questionCount == 100
                    ? 'Không còn lỗi'
                    : 'Cần kiểm tra lại',
                color: exam?.issueCount == 0 && exam?.questionCount == 100
                    ? _green
                    : _red,
                background: exam?.issueCount == 0 && exam?.questionCount == 100
                    ? _paleGreen
                    : _paleRed,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Giới hạn xem trước',
                style: TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Backend hiện phân tích văn bản trong DOCX. Ảnh nhúng và bố cục bảng phức tạp chưa được hiển thị trong bản xem trước.',
                style: TextStyle(color: _muted, fontSize: 9, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: _palePurple,
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.visibility_outlined, color: _purple, size: 17),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Sau khi xuất bản\nĐề sẽ có trong danh sách sinh viên. Nội dung lượt thi đã bắt đầu được giữ nguyên.',
                  style: TextStyle(color: _purple, fontSize: 9, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyticsPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeading(
          eyebrow: 'Tổng quan',
          title: 'Thống kê luyện thi',
          description:
              'Theo dõi mức độ sử dụng đề và kết quả học tập trong học kỳ.',
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: 250,
              child: _MetricCard(
                label: 'Lượt thi trong tháng',
                value: '${_stats?.monthlyAttempts ?? 0}',
                note: 'Tổng lượt thi đã ghi nhận',
                icon: Icons.people_outline,
              ),
            ),
            SizedBox(
              width: 250,
              child: _MetricCard(
                label: 'Điểm trung bình',
                value: (_stats?.averageScore ?? 0)
                    .toStringAsFixed(1)
                    .replaceAll('.', ','),
                note: 'Theo các đề đã xuất bản',
                icon: Icons.query_stats,
              ),
            ),
            SizedBox(
              width: 250,
              child: _MetricCard(
                label: 'Đề đã xuất bản',
                value: '${_stats?.publishedExams ?? 0}',
                note: 'Đang hiển thị cho học viên',
                icon: Icons.task_alt,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Lượt thi theo đề',
                style: TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 18),
              for (final exam in _exams.where((exam) => exam.published))
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              exam.title,
                              style: const TextStyle(color: _ink, fontSize: 11),
                            ),
                          ),
                          Text(
                            '${exam.attempts} lượt',
                            style: const TextStyle(color: _muted, fontSize: 10),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          value:
                              _exams
                                      .where((exam) => exam.published)
                                      .fold<int>(
                                        0,
                                        (maxValue, item) =>
                                            item.attempts > maxValue
                                            ? item.attempts
                                            : maxValue,
                                      ) ==
                                  0
                              ? 0
                              : (exam.attempts /
                                        _exams
                                            .where((item) => item.published)
                                            .fold<int>(
                                              0,
                                              (maxValue, item) =>
                                                  item.attempts > maxValue
                                                  ? item.attempts
                                                  : maxValue,
                                            ))
                                    .clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: _palePurple,
                          color: _purple,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).ceil()} KB';
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(9),
      ),
      child: child,
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.note,
    required this.icon,
  });

  final String label;
  final String value;
  final String note;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: _muted, fontSize: 10),
                ),
              ),
              Icon(icon, color: _purple, size: 16),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            value,
            style: const TextStyle(
              color: _ink,
              fontSize: 25,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(note, style: const TextStyle(color: _muted, fontSize: 9)),
        ],
      ),
    );
  }
}

class _FilledAction extends StatelessWidget {
  const _FilledAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: _purple,
        disabledBackgroundColor: const Color(0xFFE8EAF0),
        disabledForegroundColor: const Color(0xFF939BAC),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, {required this.color, required this.background});

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _FilterTab extends StatelessWidget {
  const _FilterTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: active ? _purple : _muted,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        textStyle: TextStyle(
          fontSize: 11,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      child: Text(label),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      color: const Color(0xFFF9FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 17),
      child: const Row(
        children: [
          Expanded(flex: 5, child: _HeaderCell('TÊN ĐỀ THI')),
          Expanded(flex: 2, child: _HeaderCell('TRẠNG THÁI')),
          Expanded(flex: 1, child: _HeaderCell('LƯỢT THI')),
          Expanded(flex: 1, child: _HeaderCell('ĐIỂM TB /100')),
          Expanded(flex: 2, child: _HeaderCell('NGÀY TẠO')),
          SizedBox(width: 32),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: _muted,
        fontSize: 9,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _ExamRow extends StatelessWidget {
  const _ExamRow({
    required this.exam,
    required this.onOpen,
    required this.onPreview,
    required this.onImport,
    required this.onDelete,
  });

  final _Exam exam;
  final VoidCallback onOpen;
  final VoidCallback onPreview;
  final VoidCallback onImport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpen,
      child: Container(
        height: 63,
        padding: const EdgeInsets.symmetric(horizontal: 17),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _line)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  Container(
                    width: 31,
                    height: 31,
                    decoration: BoxDecoration(
                      color: _palePurple,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.description_outlined,
                      color: _purple,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exam.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${exam.code} · ${exam.published ? 'Cập nhật' : '${exam.questionCount}/100 câu · ${exam.issueCount} lỗi'} ${exam.updated}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _Badge(
                  exam.published ? 'Đã xuất bản' : 'Bản nháp',
                  color: exam.published ? _green : _muted,
                  background: exam.published ? _paleGreen : _canvas,
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                exam.published ? '${exam.attempts}' : '—',
                style: const TextStyle(color: _ink, fontSize: 10),
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                exam.average,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                exam.updated,
                style: const TextStyle(color: _muted, fontSize: 10),
              ),
            ),
            SizedBox(
              width: 32,
              child: PopupMenuButton<String>(
                tooltip: 'Tác vụ với ${exam.title}',
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_horiz, color: _muted, size: 18),
                onSelected: (value) {
                  switch (value) {
                    case 'preview':
                      onPreview();
                    case 'import':
                      onImport();
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'preview',
                    child: Text('Xem trước đề'),
                  ),
                  if (!exam.published) ...[
                    const PopupMenuItem(
                      value: 'import',
                      child: Text('Nhập nội dung'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Xóa bản nháp'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IssueCard extends StatelessWidget {
  const _IssueCard({required this.issue, required this.onTap});

  final _ImportIssue issue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _paleRed,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, color: _red, size: 15),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      issue.location,
                      style: const TextStyle(color: _red, fontSize: 9),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      issue.title,
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      issue.description,
                      style: const TextStyle(color: _muted, fontSize: 9),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(
                  foregroundColor: _red,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  minimumSize: const Size(48, 29),
                  textStyle: const TextStyle(fontSize: 9),
                ),
                child: const Text('Sửa lỗi'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditQuestionDialog extends StatefulWidget {
  const _EditQuestionDialog({required this.question});

  final ExamQuestion question;

  @override
  State<_EditQuestionDialog> createState() => _EditQuestionDialogState();
}

class _EditQuestionDialogState extends State<_EditQuestionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _promptController = TextEditingController(
    text: widget.question.prompt,
  );
  late final _optionControllers = {
    for (final key in ['A', 'B', 'C', 'D'])
      key: TextEditingController(text: widget.question.options[key] ?? ''),
  };
  late final _explanationController = TextEditingController(
    text: widget.question.explanation,
  );
  late String _answer = ['A', 'B', 'C', 'D'].contains(widget.question.answer)
      ? widget.question.answer
      : 'A';

  @override
  void dispose() {
    _promptController.dispose();
    for (final controller in _optionControllers.values) {
      controller.dispose();
    }
    _explanationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Chỉnh sửa câu ${widget.question.number}'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _promptController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Nội dung câu hỏi',
                    alignLabelWithHint: true,
                  ),
                  validator: _requiredQuestionField,
                ),
                const SizedBox(height: 12),
                for (final key in ['A', 'B', 'C', 'D']) ...[
                  TextFormField(
                    controller: _optionControllers[key],
                    decoration: InputDecoration(labelText: 'Lựa chọn $key'),
                    validator: _requiredQuestionField,
                  ),
                  const SizedBox(height: 10),
                ],
                DropdownButtonFormField<String>(
                  initialValue: _answer,
                  decoration: const InputDecoration(labelText: 'Đáp án đúng'),
                  items: [
                    for (final key in ['A', 'B', 'C', 'D'])
                      DropdownMenuItem(value: key, child: Text(key)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _answer = value);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _explanationController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Lời giải',
                    alignLabelWithHint: true,
                  ),
                  validator: _requiredQuestionField,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Các thay đổi sẽ được lưu trên máy chủ. Tệp Word gốc không bị thay đổi.',
                  style: TextStyle(color: _muted, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: _save, child: const Text('Lưu thay đổi')),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      ExamQuestion(
        number: widget.question.number,
        prompt: _promptController.text.trim(),
        options: {
          for (final key in ['A', 'B', 'C', 'D'])
            key: _optionControllers[key]!.text.trim(),
        },
        answer: _answer,
        explanation: _explanationController.text.trim(),
        passageNumber: widget.question.passageNumber,
      ),
    );
  }
}

String? _requiredQuestionField(String? value) =>
    value == null || value.trim().isEmpty
    ? 'Trường này không được để trống.'
    : null;

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.success,
    required this.title,
    required this.message,
    this.action,
  });

  final bool success;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = success ? _green : _red;
    final background = success ? _paleGreen : _paleRed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            success ? Icons.verified_outlined : Icons.shield_outlined,
            color: color,
            size: 17,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: TextStyle(color: color, fontSize: 9, height: 1.4),
                ),
                if (action != null) ...[const SizedBox(height: 6), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({
    required this.number,
    required this.label,
    required this.complete,
  });

  final String number;
  final String label;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 10,
          backgroundColor: complete ? _purple : const Color(0xFFE8EAF0),
          child: Text(
            number,
            style: TextStyle(
              color: complete ? Colors.white : _muted,
              fontSize: 9,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: complete ? _purple : _muted,
            fontWeight: complete ? FontWeight.w600 : FontWeight.w400,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _PreviewStat extends StatelessWidget {
  const _PreviewStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: _purple, size: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: _muted, fontSize: 8)),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
