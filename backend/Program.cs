using Microsoft.AspNetCore.Http.Features;
using System.Net;
using Readia.Api;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenApi();
builder.Services.Configure<FormOptions>(options =>
{
    options.MultipartBodyLengthLimit = ExamStore.MaximumFileSizeBytes + 1024 * 1024;
});
builder.Services.AddCors(options =>
{
    options.AddPolicy("FlutterWeb", policy =>
        policy.SetIsOriginAllowed(origin =>
            {
                if (origin is "http://127.0.0.1:8765" or
                    "http://localhost:8765" or
                    "http://localhost:5134")
                {
                    return true;
                }

                return builder.Environment.IsDevelopment() &&
                    Uri.TryCreate(origin, UriKind.Absolute, out var uri) &&
                    uri.Scheme == Uri.UriSchemeHttp &&
                    (uri.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase) ||
                     (IPAddress.TryParse(uri.Host, out var address) &&
                      IPAddress.IsLoopback(address)));
            })
            .AllowAnyHeader()
            .AllowAnyMethod());
});
builder.Services.AddSingleton<ExamStore>();

var app = builder.Build();

app.UseCors("FlutterWeb");

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));

app.MapGet("/api/exams", async (ExamStore store, CancellationToken cancellationToken) =>
    Results.Ok(await store.ListAsync(cancellationToken)));

app.MapGet("/api/exams/{id:guid}", async (
    Guid id,
    ExamStore store,
    CancellationToken cancellationToken) =>
{
    var exam = await store.GetAsync(id, cancellationToken);
    return exam is null ? Results.NotFound() : Results.Ok(exam);
});

app.MapGet("/api/stats", async (ExamStore store, CancellationToken cancellationToken) =>
    Results.Ok(await store.GetStatsAsync(cancellationToken)));

app.MapGet("/api/student/exams", async (
    ExamStore store,
    CancellationToken cancellationToken) =>
    Results.Ok(await store.ListStudentExamsAsync(cancellationToken)));

app.MapGet("/api/student/exams/{id:guid}", async (
    Guid id,
    ExamStore store,
    CancellationToken cancellationToken) =>
{
    var exam = await store.GetStudentExamAsync(id, cancellationToken);
    return exam is null ? Results.NotFound() : Results.Ok(exam);
});

app.MapPost("/api/student/exams/{id:guid}/attempts", async (
    Guid id,
    SubmitAttemptRequest request,
    ExamStore store,
    CancellationToken cancellationToken) =>
{
    if (request.Answers is null)
    {
        return Results.BadRequest(new { error = "Answers must be provided as question-number selections." });
    }

    var result = await store.SubmitAttemptAsync(id, request, cancellationToken);
    return result.Status switch
    {
        SubmitAttemptStatus.NotFound => Results.NotFound(new
        {
            error = "This exam is not available to students."
        }),
        SubmitAttemptStatus.InvalidAnswers => Results.BadRequest(new
        {
            error = "Answers must reference questions in this exam and use options A–D."
        }),
        SubmitAttemptStatus.Completed => Results.Ok(result.Attempt),
        _ => Results.Problem("Unexpected attempt submission result.")
    };
});

app.MapPost("/api/exams/import", async (
    HttpRequest request,
    ExamStore store,
    CancellationToken cancellationToken) =>
{
    if (!request.HasFormContentType)
    {
        return Results.BadRequest(new { error = "Expected multipart form data with a file field." });
    }

    var form = await request.ReadFormAsync(cancellationToken);
    var file = form.Files.GetFile("file");
    if (file is null)
    {
        return Results.BadRequest(new { error = "Choose a .docx file in the 'file' field." });
    }

    if (!Path.GetExtension(file.FileName).Equals(".docx", StringComparison.OrdinalIgnoreCase))
    {
        return Results.BadRequest(new { error = "Only .docx files are supported." });
    }

    if (file.Length is <= 0 or > ExamStore.MaximumFileSizeBytes)
    {
        return Results.BadRequest(new { error = "The .docx file must be between 1 byte and 20 MB." });
    }

    try
    {
        await using var stream = file.OpenReadStream();
        var result = await store.ImportAsync(file.FileName, stream, cancellationToken);
        return Results.Created($"/api/exams/{result.Id}", result);
    }
    catch (InvalidDataException exception)
    {
        return Results.BadRequest(new { error = exception.Message });
    }
});

app.MapPut("/api/exams/{id:guid}/document", async (
    Guid id,
    HttpRequest request,
    ExamStore store,
    CancellationToken cancellationToken) =>
{
    if (!request.HasFormContentType)
    {
        return Results.BadRequest(new { error = "Expected multipart form data with a file field." });
    }

    var form = await request.ReadFormAsync(cancellationToken);
    var file = form.Files.GetFile("file");
    if (file is null)
    {
        return Results.BadRequest(new { error = "Choose a .docx file in the 'file' field." });
    }

    if (!Path.GetExtension(file.FileName).Equals(".docx", StringComparison.OrdinalIgnoreCase))
    {
        return Results.BadRequest(new { error = "Only .docx files are supported." });
    }

    if (file.Length is <= 0 or > ExamStore.MaximumFileSizeBytes)
    {
        return Results.BadRequest(new { error = "The .docx file must be between 1 byte and 20 MB." });
    }

    try
    {
        await using var stream = file.OpenReadStream();
        var result = await store.ReplaceDocumentAsync(id, file.FileName, stream, cancellationToken);
        return result is null ? Results.NotFound() : Results.Ok(result);
    }
    catch (InvalidDataException exception)
    {
        return Results.BadRequest(new { error = exception.Message });
    }
});

app.MapPut("/api/exams/{id:guid}/questions/{questionNumber:int}", async (
    Guid id,
    int questionNumber,
    UpdateExamQuestionRequest request,
    ExamStore store,
    CancellationToken cancellationToken) =>
{
    if (request.Options is null || request.Options.Values.Any(value => value is null))
    {
        return Results.BadRequest(new { error = "Each question must include valid option values." });
    }

    var result = await store.UpdateQuestionAsync(id, questionNumber, request, cancellationToken);
    return result switch
    {
        QuestionUpdateResult.NotFound => Results.NotFound(),
        QuestionUpdateResult.QuestionNotFound => Results.NotFound(new
        {
            error = $"Question {questionNumber} was not found in this exam."
        }),
        QuestionUpdateResult.Published => Results.Conflict(new
        {
            error = "Published exams cannot be edited."
        }),
        QuestionUpdateResult.Updated => Results.Ok(await store.GetAsync(id, cancellationToken)),
        _ => Results.Problem("Unexpected question update result.")
    };
});

app.MapPost("/api/exams/{id:guid}/validate", async (
    Guid id,
    ExamStore store,
    CancellationToken cancellationToken) =>
{
    var result = await store.ValidateAsync(id, cancellationToken);
    return result is null ? Results.NotFound() : Results.Ok(result);
});

app.MapPost("/api/exams/{id:guid}/publish", async (
    Guid id,
    ExamStore store,
    CancellationToken cancellationToken) =>
{
    var result = await store.PublishAsync(id, cancellationToken);
    return result switch
    {
        PublishResult.NotFound => Results.NotFound(),
        PublishResult.Invalid => Results.Conflict(new
        {
            error = "Fix all document validation issues before publishing."
        }),
        PublishResult.Published => Results.Ok(await store.GetAsync(id, cancellationToken)),
        _ => Results.Problem("Unexpected publish result.")
    };
});

app.MapDelete("/api/exams/{id:guid}", async (
    Guid id,
    ExamStore store,
    CancellationToken cancellationToken) =>
{
    var result = await store.DeleteAsync(id, cancellationToken);
    return result switch
    {
        DeleteResult.NotFound => Results.NotFound(),
        DeleteResult.Published => Results.Conflict(new
        {
            error = "Published exams cannot be deleted."
        }),
        DeleteResult.Deleted => Results.NoContent(),
        _ => Results.Problem("Unexpected delete result.")
    };
});

app.Run();
