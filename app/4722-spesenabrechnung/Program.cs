// Spesenabrechnung (system_id 4722) - deliberately minimal ASP.NET Core
// Minimal API, in-memory store, no database. OpenTelemetry is wired
// via the SDK directly (OpenTelemetry.Instrumentation.AspNetCore
// covers the HTTP layer automatically) rather than a separate
// auto-instrumentation agent - simpler to set up reliably on Windows
// than the .NET auto-instrumentation bundle, and just as complete for
// a single ASP.NET Core app. Runs as a real Windows Service via
// UseWindowsService(), same spirit as the Linux/Java demos running as
// systemd services.
using System.Collections.Concurrent;
using System.Diagnostics;
using Microsoft.Extensions.Hosting.WindowsServices;
using OpenTelemetry.Logs;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

var builder = WebApplication.CreateBuilder(args);
builder.Host.UseWindowsService();

var resourceBuilder = ResourceBuilder.CreateDefault()
    .AddService("spesenabrechnung");

builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .SetResourceBuilder(resourceBuilder)
        .AddAspNetCoreInstrumentation()
        .AddSource("spesenabrechnung")
        .AddOtlpExporter())
    .WithMetrics(metrics => metrics
        .SetResourceBuilder(resourceBuilder)
        .AddAspNetCoreInstrumentation()
        .AddRuntimeInstrumentation()
        .AddOtlpExporter());

builder.Logging.AddOpenTelemetry(logging =>
{
    logging.SetResourceBuilder(resourceBuilder);
    logging.AddOtlpExporter();
});

var app = builder.Build();
var logger = app.Logger;
var activitySource = new ActivitySource("spesenabrechnung");

var expenses = new ConcurrentDictionary<int, Expense>();
var nextId = 1;

app.MapGet("/expenses", () => expenses.Values.OrderBy(e => e.Id));

app.MapPost("/expenses", (ExpenseRequest request) =>
{
    // schema/core.yaml's correlation.request_id (Baggage Schema,
    // required_for: http-services) - set on Activity.Baggage (BCL,
    // W3C-Baggage-compliant, would propagate to any downstream call
    // this handler ever makes, though it doesn't call any other app
    // today) and explicitly as a span tag + log line, since neither
    // the SDK nor the collector copies Baggage onto attributes
    // automatically - only application code that's actually current
    // can do that.
    var requestId = Guid.NewGuid().ToString();
    Activity.Current?.AddBaggage("correlation.request_id", requestId);
    Activity.Current?.SetTag("correlation.request_id", requestId);

    var id = Interlocked.Increment(ref nextId);
    var expense = new Expense(id, request.Description, request.Amount);
    expenses[id] = expense;
    logger.LogInformation("Created expense {Id}: {Description} ({Amount} CHF) [correlation.request_id={RequestId}]", id, request.Description, request.Amount, requestId);
    return Results.Created($"/expenses/{id}", expense);
});

app.MapGet("/health", () => Results.Ok("ok"));

// Traffic generator - always something to see without needing external load.
_ = Task.Run(async () =>
{
    var descriptions = new[] { "Bahnticket", "Hotelübernachtung", "Kundenessen", "Taxifahrt", "Büromaterial" };
    var random = new Random();
    while (true)
    {
        await Task.Delay(TimeSpan.FromSeconds(5));
        using var activity = activitySource.StartActivity("traffic-generator tick");
        try
        {
            var description = descriptions[random.Next(descriptions.Length)];
            var amount = Math.Round(random.NextDouble() * 200, 2);
            var id = Interlocked.Increment(ref nextId);
            var expense = new Expense(id, description, amount);
            expenses[id] = expense;
            logger.LogInformation("Created expense {Id}: {Description} ({Amount} CHF)", id, description, amount);
        }
        catch (Exception ex)
        {
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            logger.LogError(ex, "Traffic generator tick failed");
        }
    }
});

app.Run();

record Expense(int Id, string Description, double Amount);
record ExpenseRequest(string Description, double Amount);
