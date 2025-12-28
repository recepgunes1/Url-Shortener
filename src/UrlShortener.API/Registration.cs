using Scalar.AspNetCore;
using Serilog;
using UrlShortener.API.Infrastructure;
using UrlShortener.Infrastructure;

namespace UrlShortener.API;

public static class Registration
{
    public static void AddAPI(this IServiceCollection services)
    {
        services.AddOpenApi();

        services.AddExceptionHandler<GlobalExceptionHandler>();
    }

    public static void LoadAPI(this WebApplication? app)
    {
        ArgumentNullException.ThrowIfNull(app);

        app.UseExceptionHandler(_ => { });

        app.ApplyMigrations();

        if (!app.Environment.IsProduction())
        {
            app.MapOpenApi();
            app.MapScalarApiReference(p =>
            {
                p.DarkMode = true;
                p.HideDarkModeToggle = true;
                p.HideModels = true;
                p.HideSearch = true;
                p.Favicon = null;
            });
        }

        app.UseSerilogRequestLogging();
    }
}
