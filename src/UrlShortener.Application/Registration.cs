using Microsoft.Extensions.DependencyInjection;
using UrlShortener.Application.Commands;
using UrlShortener.Application.Queries;

namespace UrlShortener.Application;

public static class Registration
{
    public static void AddApplication(this IServiceCollection services)
    {
        services.AddScoped<CreateShortenedUrlRequestHandler>();
        services.AddScoped<GetUrlRequestHandler>();
        services.AddScoped<GetShortCodeRequestHandler>();
    }
}
