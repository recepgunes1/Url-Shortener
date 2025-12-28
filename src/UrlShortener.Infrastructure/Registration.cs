using Microsoft.AspNetCore.Builder;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Npgsql;
using OpenTelemetry;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Serilog;
using StackExchange.Redis;
using UrlShortener.Application.Abstracts;
using UrlShortener.Application.Extensions;
using UrlShortener.Infrastructure.Contexts;
using UrlShortener.Infrastructure.Services;

namespace UrlShortener.Infrastructure;

public static class Registration
{
    public static void AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration
    )
    {
        services.AddDbContextPool<AppDbContext>(p =>
        {
            p.UseNpgsql(
                configuration.GetOrThrowException<string>("ConnectionStrings:Database"),
                o => o.UseQuerySplittingBehavior(QuerySplittingBehavior.SplitQuery)
            );
        });
        services.AddScoped<IAppDbContext>(sp => sp.GetRequiredService<AppDbContext>());

        services.AddSingleton<IConnectionMultiplexer>(_ =>
            ConnectionMultiplexer.Connect(
                configuration.GetOrThrowException<string>("ConnectionStrings:Redis")
            )
        );
        services.AddSingleton<ICacheService, CacheService>();
        services
            .AddHealthChecks()
            .AddRedis(configuration.GetOrThrowException<string>("ConnectionStrings:Redis"))
            .AddDbContextCheck<AppDbContext>();
    }

    public static void ApplyMigrations(this WebApplication? application)
    {
        ArgumentNullException.ThrowIfNull(application);
        using var scope = application.Services.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        ArgumentNullException.ThrowIfNull(dbContext);
        if (dbContext.Database.GetPendingMigrations().Any())
            dbContext.Database.Migrate();
    }

    public static void LoadMonitoring(this WebApplicationBuilder builder)
    {
        var serviceName = "UrlShortener";

        builder.Logging.ClearProviders();

        builder.Services.AddSerilog(p =>
        {
            p.MinimumLevel.Information();
            p.WriteTo.Console();
            p.WriteTo.OpenTelemetry(opts =>
            {
                opts.ResourceAttributes = new Dictionary<string, object>
                {
                    ["service.name"] = serviceName,
                    ["service.instance.id"] = Environment.MachineName,
                };
            });
        });

        builder.Logging.AddOpenTelemetry(logging =>
        {
            logging.IncludeScopes = true;
            logging.IncludeFormattedMessage = true;
            logging.ParseStateValues = true;
        });

        builder
            .Services.AddOpenTelemetry()
            .ConfigureResource(res =>
            {
                res.Clear();
                res.AddService(
                    serviceName: serviceName,
                    serviceInstanceId: Environment.MachineName
                );
            })
            .WithMetrics(metrics =>
                metrics
                    .AddHttpClientInstrumentation()
                    .AddAspNetCoreInstrumentation()
                    .AddNpgsqlInstrumentation()
                    .AddRuntimeInstrumentation()
                    .AddProcessInstrumentation()
                    .AddEventCountersInstrumentation()
                    .AddSqlClientInstrumentation()
            )
            .WithTracing(tracing =>
                tracing
                    .AddHttpClientInstrumentation()
                    .AddAspNetCoreInstrumentation()
                    .AddNpgsql()
                    .AddRedisInstrumentation()
                    .AddEntityFrameworkCoreInstrumentation()
                    .AddSqlClientInstrumentation()
                    .AddGrpcClientInstrumentation()
                    .AddGrpcCoreInstrumentation()
            )
            .WithLogging()
            .UseOtlpExporter();
    }
}
