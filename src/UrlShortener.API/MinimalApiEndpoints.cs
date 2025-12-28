using UrlShortener.Application.Commands;
using UrlShortener.Application.Queries;

namespace UrlShortener.API;

public static class MinimalApiEndpoints
{
    public static void MapEndpoints(this WebApplication app)
    {
        var apiV1Group = app.MapGroup("/api/v1");

        apiV1Group.MapPost(
            "/shorten-url",
            async (
                CreateShortenedUrlRequest request,
                CreateShortenedUrlRequestHandler handler,
                CancellationToken cancellationToken
            ) =>
            {
                var result = await handler.InvokeAsync(request, cancellationToken);
                return Results.Ok(result);
            }
        );

        apiV1Group.MapGet(
            "/urls",
            async (
                [AsParameters] GetUrlRequest request,
                GetUrlRequestHandler handler,
                CancellationToken cancellationToken
            ) =>
            {
                var result = await handler.InvokeAsync(request, cancellationToken);
                return Results.Ok(result);
            }
        );

        apiV1Group.MapGet(
            "/shortened-urls",
            async (
                [AsParameters] GetShortCodeRequest request,
                GetShortCodeRequestHandler handler,
                CancellationToken cancellationToken
            ) =>
            {
                var result = await handler.InvokeAsync(request, cancellationToken);
                return Results.Ok(result);
            }
        );
    }
}
