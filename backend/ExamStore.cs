using System.IO.Compression;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml;
using System.Xml.Linq;

namespace Readia.Api;

public sealed class ExamStore
{
    public const long MaximumFileSizeBytes = 20 * 1024 * 1024;

    private const string WordNamespace =
        "http://schemas.openxmlformats.org/wordprocessingml/2006/main";

    private static readonly JsonSerializerOptions JsonOptions =
        new(JsonSerializerDefaults.Web) { WriteIndented = true };

    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly string _dataDirectory;
    private readonly string _uploadDirectory;
    private readonly string _indexPath;
    private readonly ILogger<ExamStore> _logger;
    private List<ExamRecord>? _records;

    public ExamStore(IWebHostEnvironment environment, ILogger<ExamStore> logger)
    {
        _dataDirectory = Path.Combine(environment.ContentRootPath, "App_Data");
        _uploadDirectory = Path.Combine(_dataDirectory, "uploads");
        _indexPath = Path.Combine(_dataDirectory, "exams.json");
        _logger = logger;
    }

    public async Task<QuestionUpdateResult> UpdateQuestionAsync(
        Guid id,
        int questionNumber,
        UpdateExamQuestionRequest request,
        CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var records = await GetRecordsAsync(cancellationToken);
            var record = records.FirstOrDefault(item => item.Id == id);
            if (record is null)
            {
                return QuestionUpdateResult.NotFound;
            }

            if (record.IsPublished)
            {
                return QuestionUpdateResult.Published;
            }

            var question = record.Questions.FirstOrDefault(item => item.Number == questionNumber);
            if (question is null)
            {
                return QuestionUpdateResult.QuestionNotFound;
            }

            question.Prompt = request.Prompt?.Trim() ?? string.Empty;
            question.Options = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (var key in new[] { "A", "B", "C", "D" })
            {
                if (request.Options.TryGetValue(key, out var value))
                {
                    question.Options[key] = value.Trim();
                }
            }
            question.Answer = request.Answer?.Trim().ToUpperInvariant() ?? string.Empty;
            question.Explanation = request.Explanation?.Trim() ?? string.Empty;
            question.LastOptionKey = null;
            record.HasManualEdits = true;
            record.UpdatedAt = DateTimeOffset.UtcNow;
            ApplyAnalysis(record, AnalyzeEditedContent(record));
            await SaveRecordsAsync(records, cancellationToken);
            return QuestionUpdateResult.Updated;
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<IReadOnlyList<ExamSummary>> ListAsync(CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            return (await GetRecordsAsync(cancellationToken))
                .OrderByDescending(record => record.UpdatedAt)
                .Select(ToSummary)
                .ToArray();
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<ExamDetail?> GetAsync(Guid id, CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var record = (await GetRecordsAsync(cancellationToken))
                .FirstOrDefault(item => item.Id == id);
            return record is null ? null : ToDetail(record);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<ExamStats> GetStatsAsync(CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var records = await GetRecordsAsync(cancellationToken);
            return new ExamStats(
                records.Count,
                records.Count(record => record.IsPublished),
                records.Count(record => !record.IsPublished),
                records.Sum(record => record.Attempts),
                records.Where(record => record.IsPublished && record.AverageScore.HasValue)
                    .Select(record => record.AverageScore!.Value)
                    .DefaultIfEmpty()
                    .Average());
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<IReadOnlyList<StudentExamSummary>> ListStudentExamsAsync(
        CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            return (await GetRecordsAsync(cancellationToken))
                .Where(IsAvailableToStudents)
                .OrderBy(record => record.Title, StringComparer.Ordinal)
                .Select(record => new StudentExamSummary(
                    record.Id,
                    record.Title,
                    record.Code,
                    record.QuestionCount,
                    record.Attempts,
                    record.AverageScore))
                .ToArray();
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<StudentExam?> GetStudentExamAsync(
        Guid id,
        CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var record = (await GetRecordsAsync(cancellationToken))
                .FirstOrDefault(item => item.Id == id && IsAvailableToStudents(item));
            return record is null
                ? null
                : new StudentExam(
                    record.Id,
                    record.Title,
                    record.Code,
                    record.QuestionCount,
                    75,
                    record.Questions.Select(question => new StudentQuestion(
                        question.Number,
                        question.Prompt,
                        question.Options,
                        question.PassageNumber)).ToArray(),
                    record.Passages);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<SubmitAttemptResult> SubmitAttemptAsync(
        Guid id,
        SubmitAttemptRequest request,
        CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var records = await GetRecordsAsync(cancellationToken);
            var record = records.FirstOrDefault(item => item.Id == id && IsAvailableToStudents(item));
            if (record is null)
            {
                return SubmitAttemptResult.NotFound;
            }

            if (request.Answers.Keys.Any(number =>
                record.Questions.All(question => question.Number != number)) ||
                request.Answers.Values.Any(answer =>
                    answer is not ("A" or "B" or "C" or "D")))
            {
                return SubmitAttemptResult.InvalidAnswers;
            }

            var results = record.Questions.Select(question =>
            {
                request.Answers.TryGetValue(question.Number, out var selectedAnswer);
                return new StudentQuestionResult(
                    question.Number,
                    question.Prompt,
                    question.Options,
                    selectedAnswer,
                    question.Answer,
                    string.Equals(selectedAnswer, question.Answer, StringComparison.Ordinal),
                    question.Explanation);
            }).ToArray();
            var correctCount = results.Count(result => result.IsCorrect);
            var score = record.Questions.Count == 0
                ? 0
                : Math.Round(correctCount * 100.0 / record.Questions.Count, 1);
            var submittedAt = DateTimeOffset.UtcNow;
            var attempt = new ExamAttemptRecord
            {
                Id = Guid.NewGuid(),
                SubmittedAt = submittedAt,
                CorrectCount = correctCount,
                Score = score,
                TotalQuestions = record.Questions.Count
            };
            record.AttemptResults.Add(attempt);
            var previousAttempts = record.Attempts;
            record.Attempts++;
            record.AverageScore = previousAttempts == 0 || record.AverageScore is null
                ? score
                : ((record.AverageScore.Value * previousAttempts) + score) / record.Attempts;
            record.UpdatedAt = submittedAt;
            await SaveRecordsAsync(records, cancellationToken);
            return SubmitAttemptResult.Completed(new StudentAttemptResult(
                attempt.Id,
                record.Id,
                record.Title,
                record.Code,
                correctCount,
                record.Questions.Count,
                score,
                submittedAt,
                results));
        }
        finally
        {
            _gate.Release();
        }
    }

    public Task<ExamDetail> ImportAsync(
        string fileName,
        Stream content,
        CancellationToken cancellationToken) =>
        CreateOrReplaceAsync(null, fileName, content, cancellationToken);

    public async Task<ExamDetail?> ReplaceDocumentAsync(
        Guid id,
        string fileName,
        Stream content,
        CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var records = await GetRecordsAsync(cancellationToken);
            var record = records.FirstOrDefault(item => item.Id == id);
            if (record is null || record.IsPublished)
            {
                return null;
            }

            var bytes = await ReadDocumentAsync(content, cancellationToken);
            var analysis = AnalyzeDocument(bytes);
            await SaveDocumentAsync(id, bytes, cancellationToken);

            record.FileName = Path.GetFileName(fileName);
            record.UpdatedAt = DateTimeOffset.UtcNow;
            record.HasManualEdits = false;
            ApplyAnalysis(record, analysis);
            await SaveRecordsAsync(records, cancellationToken);
            return ToDetail(record);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<ExamDetail?> ValidateAsync(Guid id, CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var records = await GetRecordsAsync(cancellationToken);
            var record = records.FirstOrDefault(item => item.Id == id);
            if (record is null)
            {
                return null;
            }

            var path = GetDocumentPath(id);
            if (!File.Exists(path))
            {
                throw new InvalidOperationException(
                    $"The source document for exam {id} is missing from storage.");
            }

            var analysis = record.HasManualEdits
                ? AnalyzeEditedContent(record)
                : AnalyzeDocument(await File.ReadAllBytesAsync(path, cancellationToken));
            record.UpdatedAt = DateTimeOffset.UtcNow;
            ApplyAnalysis(record, analysis);
            await SaveRecordsAsync(records, cancellationToken);
            return ToDetail(record);
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<PublishResult> PublishAsync(Guid id, CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var records = await GetRecordsAsync(cancellationToken);
            var record = records.FirstOrDefault(item => item.Id == id);
            if (record is null)
            {
                return PublishResult.NotFound;
            }

            if (record.Issues.Count != 0 || record.QuestionCount != 100)
            {
                return PublishResult.Invalid;
            }

            record.IsPublished = true;
            record.UpdatedAt = DateTimeOffset.UtcNow;
            await SaveRecordsAsync(records, cancellationToken);
            return PublishResult.Published;
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<DeleteResult> DeleteAsync(Guid id, CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var records = await GetRecordsAsync(cancellationToken);
            var record = records.FirstOrDefault(item => item.Id == id);
            if (record is null)
            {
                return DeleteResult.NotFound;
            }

            if (record.IsPublished)
            {
                return DeleteResult.Published;
            }

            records.Remove(record);
            var path = GetDocumentPath(id);
            if (File.Exists(path))
            {
                File.Delete(path);
            }

            await SaveRecordsAsync(records, cancellationToken);
            return DeleteResult.Deleted;
        }
        finally
        {
            _gate.Release();
        }
    }

    private async Task<ExamDetail> CreateOrReplaceAsync(
        Guid? id,
        string fileName,
        Stream content,
        CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var records = await GetRecordsAsync(cancellationToken);
            var bytes = await ReadDocumentAsync(content, cancellationToken);
            var analysis = AnalyzeDocument(bytes);
            var examId = id ?? Guid.NewGuid();
            var record = new ExamRecord
            {
                Id = examId,
                Code = NextCode(records),
                Title = $"TOEIC Reading — Đề {NextCodeNumber(records):00}",
                FileName = Path.GetFileName(fileName),
                UpdatedAt = DateTimeOffset.UtcNow
            };

            await SaveDocumentAsync(examId, bytes, cancellationToken);
            ApplyAnalysis(record, analysis);
            records.Add(record);
            await SaveRecordsAsync(records, cancellationToken);
            return ToDetail(record);
        }
        finally
        {
            _gate.Release();
        }
    }

    private async Task<List<ExamRecord>> GetRecordsAsync(CancellationToken cancellationToken)
    {
        if (_records is not null)
        {
            return _records;
        }

        Directory.CreateDirectory(_uploadDirectory);
        if (!File.Exists(_indexPath))
        {
            _records = [];
            return _records;
        }

        await using var stream = File.OpenRead(_indexPath);
        _records = await JsonSerializer.DeserializeAsync<List<ExamRecord>>(
            stream,
            JsonOptions,
            cancellationToken) ?? [];
        return _records;
    }

    private async Task SaveRecordsAsync(
        List<ExamRecord> records,
        CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(_dataDirectory);
        var temporaryPath = $"{_indexPath}.{Guid.NewGuid():N}.tmp";
        try
        {
            await using (var stream = File.Create(temporaryPath))
            {
                await JsonSerializer.SerializeAsync(stream, records, JsonOptions, cancellationToken);
            }

            File.Move(temporaryPath, _indexPath, overwrite: true);
            _records = records;
        }
        finally
        {
            if (File.Exists(temporaryPath))
            {
                File.Delete(temporaryPath);
            }
        }
    }

    private async Task SaveDocumentAsync(
        Guid id,
        byte[] bytes,
        CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(_uploadDirectory);
        await File.WriteAllBytesAsync(GetDocumentPath(id), bytes, cancellationToken);
    }

    private string GetDocumentPath(Guid id) =>
        Path.Combine(_uploadDirectory, $"{id:N}.docx");

    private static async Task<byte[]> ReadDocumentAsync(
        Stream content,
        CancellationToken cancellationToken)
    {
        await using var buffer = new MemoryStream();
        var chunk = new byte[81920];
        while (true)
        {
            var read = await content.ReadAsync(chunk, cancellationToken);
            if (read == 0)
            {
                break;
            }

            if (buffer.Length + read > MaximumFileSizeBytes)
            {
                throw new InvalidDataException("The .docx file exceeds the 20 MB limit.");
            }

            await buffer.WriteAsync(chunk.AsMemory(0, read), cancellationToken);
        }

        if (buffer.Length == 0)
        {
            throw new InvalidDataException("The .docx file is empty.");
        }

        return buffer.ToArray();
    }

    private static DocumentAnalysis AnalyzeDocument(byte[] bytes)
    {
        var issues = new List<ExamIssue>();
        var questions = new List<ExamQuestion>();
        var passages = new List<ExamPassage>();

        try
        {
            using var archive = new ZipArchive(new MemoryStream(bytes), ZipArchiveMode.Read);
            var documentEntry = archive.GetEntry("word/document.xml");
            if (documentEntry is null)
            {
                throw new InvalidDataException("This file is not a valid Word .docx document.");
            }

            using var documentStream = documentEntry.Open();
            using var reader = XmlReader.Create(documentStream, new XmlReaderSettings
            {
                DtdProcessing = DtdProcessing.Prohibit,
                XmlResolver = null
            });
            var document = XDocument.Load(reader);
            var word = XNamespace.Get(WordNamespace);
            var paragraphs = document.Descendants(word + "p")
                .Select(paragraph => string.Concat(paragraph.Descendants(word + "t")
                    .Select(text => text.Value)).Trim())
                .Where(text => text.Length > 0)
                .ToArray();
            var usesTaggedQuestionFormat = paragraphs.Any(text =>
                Regex.IsMatch(text, @"^\[Q:\d+\]", RegexOptions.CultureInvariant));

            ExamQuestion? currentQuestion = null;
            ExamPassage? currentPassage = null;
            var passageIsOpen = false;
            var section = ContentSection.None;

            for (var index = 0; index < paragraphs.Length; index++)
            {
                var text = paragraphs[index];
                var lineNumber = index + 1;
                if (usesTaggedQuestionFormat &&
                    text.StartsWith("[END]", StringComparison.Ordinal))
                {
                    break;
                }

                var taggedQuestion = usesTaggedQuestionFormat
                    ? Regex.Match(text, @"^\[Q:(\d+)\]", RegexOptions.CultureInvariant)
                    : Match.Empty;
                if (taggedQuestion.Success)
                {
                    currentQuestion = new ExamQuestion
                    {
                        Number = int.Parse(taggedQuestion.Groups[1].Value),
                        PassageNumber = currentPassage?.Number
                    };
                    questions.Add(currentQuestion);
                    section = ContentSection.Question;
                    continue;
                }

                if (usesTaggedQuestionFormat && text == "[/Q]")
                {
                    currentQuestion = null;
                    section = ContentSection.None;
                    continue;
                }

                if (usesTaggedQuestionFormat && text == "[/PASSAGE]")
                {
                    passageIsOpen = false;
                    section = ContentSection.None;
                    continue;
                }

                if (usesTaggedQuestionFormat &&
                    Regex.IsMatch(text, @"^\[(PART|GROUP):", RegexOptions.CultureInvariant))
                {
                    currentQuestion = null;
                    currentPassage = null;
                    passageIsOpen = false;
                    section = ContentSection.None;
                    continue;
                }

                var tag = Regex.Match(
                    text,
                    @"^\[(PASSAGES?|QUESTION|OPTION|ANSWER|EXPLANATION|TEXT|KEY|HINT|[A-D])\]\s*(.*)$",
                    RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

                if (!tag.Success)
                {
                    AppendContent(text, section, currentQuestion, currentPassage);
                    continue;
                }

                var body = tag.Groups[2].Value.Trim();
                switch (tag.Groups[1].Value.ToUpperInvariant())
                {
                    case "PASSAGE":
                    case "PASSAGES":
                        currentPassage = new ExamPassage
                        {
                            Number = passages.Count + 1,
                            Content = body
                        };
                        passages.Add(currentPassage);
                        currentQuestion = null;
                        passageIsOpen = true;
                        section = ContentSection.Passage;
                        break;
                    case "QUESTION":
                        var numberMatch = Regex.Match(body, @"^\s*(\d+)[.):]?\s*(.*)$");
                        var number = numberMatch.Success
                            ? int.Parse(numberMatch.Groups[1].Value)
                            : questions.Count + 1;
                        var prompt = numberMatch.Success
                            ? numberMatch.Groups[2].Value.Trim()
                            : body;
                        currentQuestion = new ExamQuestion
                        {
                            Number = number,
                            Prompt = prompt,
                            PassageNumber = currentPassage?.Number
                        };
                        questions.Add(currentQuestion);
                        section = ContentSection.Question;
                        break;
                    case "TEXT":
                        if (currentQuestion is not null)
                        {
                            currentQuestion.Prompt = body;
                            section = ContentSection.Question;
                        }
                        else if (passageIsOpen && currentPassage is not null)
                        {
                            currentPassage.Content = JoinContent(currentPassage.Content, body);
                            section = ContentSection.Passage;
                        }
                        break;
                    case "OPTION":
                    case "A":
                    case "B":
                    case "C":
                    case "D":
                        if (currentQuestion is null)
                        {
                            issues.Add(new ExamIssue(
                                lineNumber, null, "option-without-question",
                                "OPTION không thuộc câu hỏi",
                                "Thêm [QUESTION] trước các lựa chọn.",
                                text));
                            section = ContentSection.None;
                            break;
                        }

                        var optionKey = tag.Groups[1].Value.ToUpperInvariant();
                        var optionText = body;
                        if (optionKey == "OPTION")
                        {
                            var optionMatch = Regex.Match(
                                body,
                                @"^([A-D])\s*[.):\-]?\s*(.*)$",
                                RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
                            if (!optionMatch.Success)
                            {
                                issues.Add(new ExamIssue(
                                    lineNumber, currentQuestion.Number, "invalid-option",
                                    "Nhãn [OPTION] không hợp lệ",
                                    "Lựa chọn phải bắt đầu bằng A, B, C hoặc D.",
                                    text));
                                section = ContentSection.None;
                                break;
                            }

                            optionKey = optionMatch.Groups[1].Value.ToUpperInvariant();
                            optionText = optionMatch.Groups[2].Value.Trim();
                        }

                        if (!currentQuestion.Options.TryAdd(optionKey, optionText))
                        {
                            issues.Add(new ExamIssue(
                                lineNumber, currentQuestion.Number, "duplicate-option",
                                $"Trùng nhãn [OPTION] {optionKey}",
                                "Mỗi câu hỏi có duy nhất 4 lựa chọn A, B, C, D.",
                                text));
                        }

                        section = ContentSection.Option;
                        currentQuestion.LastOptionKey = optionKey;
                        break;
                    case "ANSWER":
                    case "KEY":
                        if (currentQuestion is null)
                        {
                            issues.Add(new ExamIssue(
                                lineNumber, null, "answer-without-question",
                                "ANSWER không thuộc câu hỏi",
                                "Thêm [QUESTION] trước đáp án.",
                                text));
                            section = ContentSection.None;
                            break;
                        }

                        currentQuestion.Answer = Regex.Match(
                            body, @"\b([A-D])\b", RegexOptions.IgnoreCase)
                            .Groups[1].Value.ToUpperInvariant();
                        currentQuestion.AnswerLine = lineNumber;
                        section = ContentSection.Answer;
                        break;
                    case "EXPLANATION":
                    case "HINT":
                        if (currentQuestion is null)
                        {
                            issues.Add(new ExamIssue(
                                lineNumber, null, "explanation-without-question",
                                "EXPLANATION không thuộc câu hỏi",
                                "Thêm [QUESTION] trước phần giải thích.",
                                text));
                            section = ContentSection.None;
                            break;
                        }

                        currentQuestion.Explanation = body;
                        currentQuestion.ExplanationLine = lineNumber;
                        section = ContentSection.Explanation;
                        break;
                }
            }

            if (questions.Count != 100)
            {
                issues.Add(new ExamIssue(
                    1, null, "question-count",
                    $"Số câu hỏi không hợp lệ ({questions.Count}/100)",
                    "Đề TOEIC Reading phải có đúng 100 câu được đánh dấu [QUESTION].",
                    string.Empty));
            }

            foreach (var question in questions)
            {
                var missingOptions = new[] { "A", "B", "C", "D" }
                    .Where(option => !question.Options.ContainsKey(option))
                    .ToArray();
                if (missingOptions.Length > 0)
                {
                    issues.Add(new ExamIssue(
                        question.AnswerLine ?? question.ExplanationLine ?? 1,
                        question.Number,
                        "missing-options",
                        $"Thiếu lựa chọn {string.Join(", ", missingOptions)}",
                        "Mỗi câu hỏi phải có đủ bốn tag [OPTION] A, B, C và D.",
                        string.Empty));
                }

                if (question.Answer is not ("A" or "B" or "C" or "D") ||
                    !question.Options.ContainsKey(question.Answer))
                {
                    issues.Add(new ExamIssue(
                        question.AnswerLine ?? 1,
                        question.Number,
                        "invalid-answer",
                        "Đáp án đúng không hợp lệ",
                        "Tag [ANSWER] phải chỉ tới một lựa chọn A–D đã tồn tại.",
                        question.Answer));
                }

                if (string.IsNullOrWhiteSpace(question.Explanation))
                {
                    issues.Add(new ExamIssue(
                        question.ExplanationLine ?? 1,
                        question.Number,
                        "missing-explanation",
                        "Thiếu tag [EXPLANATION]",
                        "Câu hỏi chưa có phần lời giải bắt buộc.",
                        string.Empty));
                }
            }
        }
        catch (InvalidDataException)
        {
            throw;
        }
        catch (Exception exception) when (
            exception is InvalidDataException or XmlException or IOException or
                ArgumentException or NotSupportedException)
        {
            throw new InvalidDataException(
                "The selected file is not a readable Word .docx document.", exception);
        }

        return new DocumentAnalysis(questions, passages, issues);
    }

    private static void AppendContent(
        string text,
        ContentSection section,
        ExamQuestion? question,
        ExamPassage? passage)
    {
        switch (section)
        {
            case ContentSection.Passage when passage is not null:
                passage.Content = JoinContent(passage.Content, text);
                break;
            case ContentSection.Question when question is not null:
                question.Prompt = JoinContent(question.Prompt, text);
                break;
            case ContentSection.Option when question is not null &&
                                             question.LastOptionKey is not null:
                question.Options[question.LastOptionKey] =
                    JoinContent(question.Options[question.LastOptionKey], text);
                break;
            case ContentSection.Explanation when question is not null:
                question.Explanation = JoinContent(question.Explanation, text);
                break;
        }
    }

    private static string JoinContent(string current, string next) =>
        string.IsNullOrWhiteSpace(current) ? next : $"{current}\n{next}";

    private static void ApplyAnalysis(ExamRecord record, DocumentAnalysis analysis)
    {
        record.Questions = analysis.Questions;
        record.Passages = analysis.Passages;
        record.Issues = analysis.Issues;
        record.QuestionCount = analysis.Questions.Count;
    }

    private static bool IsAvailableToStudents(ExamRecord record) =>
        record.IsPublished && record.Issues.Count == 0 && record.QuestionCount == 100;

    private static DocumentAnalysis AnalyzeEditedContent(ExamRecord record)
    {
        var retainedIssues = record.Issues
            .Where(issue => issue.Code is not (
                "question-count" or "missing-question-text" or "missing-options" or
                "invalid-answer" or "missing-explanation"))
            .ToList();
        var issues = retainedIssues;
        if (record.Questions.Count != 100)
        {
            issues.Add(new ExamIssue(
                1, null, "question-count",
                $"Số câu hỏi không hợp lệ ({record.Questions.Count}/100)",
                "Đề TOEIC Reading phải có đúng 100 câu được đánh dấu [QUESTION].",
                string.Empty));
        }

        foreach (var question in record.Questions)
        {
            if (string.IsNullOrWhiteSpace(question.Prompt))
            {
                issues.Add(new ExamIssue(
                    1,
                    question.Number,
                    "missing-question-text",
                    "Thiếu nội dung câu hỏi",
                    "Mỗi câu hỏi phải có nội dung.",
                    string.Empty));
            }

            var missingOptions = new[] { "A", "B", "C", "D" }
                .Where(option =>
                    !question.Options.TryGetValue(option, out var value) ||
                    string.IsNullOrWhiteSpace(value))
                .ToArray();
            if (missingOptions.Length > 0)
            {
                issues.Add(new ExamIssue(
                    question.AnswerLine ?? question.ExplanationLine ?? 1,
                    question.Number,
                    "missing-options",
                    $"Thiếu lựa chọn {string.Join(", ", missingOptions)}",
                    "Mỗi câu hỏi phải có đủ bốn lựa chọn A, B, C và D.",
                    string.Empty));
            }

            if (question.Answer is not ("A" or "B" or "C" or "D") ||
                !question.Options.ContainsKey(question.Answer))
            {
                issues.Add(new ExamIssue(
                    question.AnswerLine ?? 1,
                    question.Number,
                    "invalid-answer",
                    "Đáp án đúng không hợp lệ",
                    "Đáp án đúng phải chỉ tới một lựa chọn A–D đã tồn tại.",
                    question.Answer));
            }

            if (string.IsNullOrWhiteSpace(question.Explanation))
            {
                issues.Add(new ExamIssue(
                    question.ExplanationLine ?? 1,
                    question.Number,
                    "missing-explanation",
                    "Thiếu lời giải",
                    "Câu hỏi chưa có phần lời giải bắt buộc.",
                    string.Empty));
            }
        }

        return new DocumentAnalysis(record.Questions, record.Passages, issues);
    }

    private static ExamSummary ToSummary(ExamRecord record) => new(
        record.Id,
        record.Title,
        record.Code,
        record.FileName,
        record.IsPublished,
        record.UpdatedAt,
        record.QuestionCount,
        record.Attempts,
        record.AverageScore,
        record.Issues.Count);

    private static ExamDetail ToDetail(ExamRecord record) => new(
        record.Id,
        record.Title,
        record.Code,
        record.FileName,
        record.IsPublished,
        record.UpdatedAt,
        record.QuestionCount,
        record.Attempts,
        record.AverageScore,
        record.Issues.Count,
        record.Issues,
        record.Questions,
        record.Passages);

    private static int NextCodeNumber(IEnumerable<ExamRecord> records) =>
        records.Select(record => Regex.Match(record.Code, @"^RD-(\d+)$"))
            .Where(match => match.Success)
            .Select(match => int.Parse(match.Groups[1].Value))
            .DefaultIfEmpty(0)
            .Max() + 1;

    private static string NextCode(IEnumerable<ExamRecord> records) =>
        $"RD-{NextCodeNumber(records):00}";

    private enum ContentSection
    {
        None,
        Passage,
        Question,
        Option,
        Answer,
        Explanation
    }

    private sealed record DocumentAnalysis(
        List<ExamQuestion> Questions,
        List<ExamPassage> Passages,
        List<ExamIssue> Issues);
}

public sealed class ExamRecord
{
    public Guid Id { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Code { get; set; } = string.Empty;
    public string FileName { get; set; } = string.Empty;
    public DateTimeOffset UpdatedAt { get; set; }
    public bool IsPublished { get; set; }
    public bool HasManualEdits { get; set; }
    public int QuestionCount { get; set; }
    public int Attempts { get; set; }
    public double? AverageScore { get; set; }
    public List<ExamIssue> Issues { get; set; } = [];
    public List<ExamQuestion> Questions { get; set; } = [];
    public List<ExamPassage> Passages { get; set; } = [];
    public List<ExamAttemptRecord> AttemptResults { get; set; } = [];
}

public sealed class ExamAttemptRecord
{
    public Guid Id { get; set; }
    public DateTimeOffset SubmittedAt { get; set; }
    public int CorrectCount { get; set; }
    public int TotalQuestions { get; set; }
    public double Score { get; set; }
}

public sealed class ExamQuestion
{
    public int Number { get; set; }
    public string Prompt { get; set; } = string.Empty;
    public Dictionary<string, string> Options { get; set; } = new(StringComparer.Ordinal);
    public string Answer { get; set; } = string.Empty;
    public string Explanation { get; set; } = string.Empty;
    public int? PassageNumber { get; set; }
    public int? AnswerLine { get; set; }
    public int? ExplanationLine { get; set; }
    public string? LastOptionKey { get; set; }
}

public sealed class ExamPassage
{
    public int Number { get; set; }
    public string Content { get; set; } = string.Empty;
}

public sealed record ExamIssue(
    int Line,
    int? QuestionNumber,
    string Code,
    string Title,
    string Description,
    string Example);

public sealed record ExamSummary(
    Guid Id,
    string Title,
    string Code,
    string FileName,
    bool IsPublished,
    DateTimeOffset UpdatedAt,
    int QuestionCount,
    int Attempts,
    double? AverageScore,
    int IssueCount);

public sealed record ExamDetail(
    Guid Id,
    string Title,
    string Code,
    string FileName,
    bool IsPublished,
    DateTimeOffset UpdatedAt,
    int QuestionCount,
    int Attempts,
    double? AverageScore,
    int IssueCount,
    IReadOnlyList<ExamIssue> Issues,
    IReadOnlyList<ExamQuestion> Questions,
    IReadOnlyList<ExamPassage> Passages);

public sealed record ExamStats(
    int TotalExams,
    int PublishedExams,
    int DraftExams,
    int MonthlyAttempts,
    double AverageScore);

public enum PublishResult
{
    NotFound,
    Invalid,
    Published
}

public enum DeleteResult
{
    NotFound,
    Published,
    Deleted
}

public sealed class UpdateExamQuestionRequest
{
    public string? Prompt { get; init; }
    public Dictionary<string, string> Options { get; init; } = new(StringComparer.Ordinal);
    public string? Answer { get; init; }
    public string? Explanation { get; init; }
}

public enum QuestionUpdateResult
{
    NotFound,
    QuestionNotFound,
    Published,
    Updated
}

public sealed record StudentExamSummary(
    Guid Id,
    string Title,
    string Code,
    int QuestionCount,
    int Attempts,
    double? AverageScore);

public sealed record StudentQuestion(
    int Number,
    string Prompt,
    IReadOnlyDictionary<string, string> Options,
    int? PassageNumber);

public sealed record StudentExam(
    Guid Id,
    string Title,
    string Code,
    int QuestionCount,
    int DurationMinutes,
    IReadOnlyList<StudentQuestion> Questions,
    IReadOnlyList<ExamPassage> Passages);

public sealed class SubmitAttemptRequest
{
    public Dictionary<int, string> Answers { get; init; } = [];
}

public sealed record StudentQuestionResult(
    int Number,
    string Prompt,
    IReadOnlyDictionary<string, string> Options,
    string? SelectedAnswer,
    string CorrectAnswer,
    bool IsCorrect,
    string Explanation);

public sealed record StudentAttemptResult(
    Guid AttemptId,
    Guid ExamId,
    string ExamTitle,
    string ExamCode,
    int CorrectCount,
    int TotalQuestions,
    double Score,
    DateTimeOffset SubmittedAt,
    IReadOnlyList<StudentQuestionResult> Questions);

public sealed record SubmitAttemptResult(
    SubmitAttemptStatus Status,
    StudentAttemptResult? Attempt = null)
{
    public static SubmitAttemptResult NotFound { get; } =
        new(SubmitAttemptStatus.NotFound);
    public static SubmitAttemptResult InvalidAnswers { get; } =
        new(SubmitAttemptStatus.InvalidAnswers);
    public static SubmitAttemptResult Completed(StudentAttemptResult attempt) =>
        new(SubmitAttemptStatus.Completed, attempt);
}

public enum SubmitAttemptStatus
{
    NotFound,
    InvalidAnswers,
    Completed
}
