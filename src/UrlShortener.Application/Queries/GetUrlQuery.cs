using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using UrlShortener.Application.Abstracts;
using UrlShortener.Application.Extensions;

namespace UrlShortener.Application.Queries;

public sealed record GetUrlRequest(string ShortCode);

public sealed class GetUrlRequestHandler(
    IAppDbContext appDbContext,
    ICacheService cacheService,
    IConfiguration configuration
)
{
    public async Task<string> InvokeAsync(
        GetUrlRequest request,
        CancellationToken cancellationToken
    )
    {
        var url = await cacheService.GetAsync(request.ShortCode);

        if (!string.IsNullOrWhiteSpace(url))
            return url;

        var entity = await appDbContext.ShortenedUrls.FirstOrDefaultAsync(
            p => p.ShortCode == request.ShortCode,
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

        return entity.Url;
    }
}
