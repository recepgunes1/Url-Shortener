using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using UrlShortener.Application.Abstracts;
using UrlShortener.Application.Extensions;

namespace UrlShortener.Application.Queries;

public sealed record GetShortCodeRequest(string Url);

public sealed class GetShortCodeRequestHandler(
    IAppDbContext appDbContext,
    ICacheService cacheService,
    IConfiguration configuration
)
{
    public async Task<string> InvokeAsync(
        GetShortCodeRequest request,
        CancellationToken cancellationToken
    )
    {
        var entity = await appDbContext.ShortenedUrls.FirstOrDefaultAsync(
            p => p.Url == request.Url,
            cancellationToken
        );

        if (entity == null)
        {
            throw new Exception("Shortened url not found");
        }

        await cacheService.AddAsync(
            entity.Url,
            entity.ShortCode,
            TimeSpan.FromDays(configuration.GetOrThrowException<int>("Url:CacheExpiresInDays"))
        );

        return entity.ShortCode;
    }
}
