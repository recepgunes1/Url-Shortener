using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using UrlShortener.Application.Abstracts;
using UrlShortener.Application.Extensions;
using UrlShortener.Domain.Entities;

namespace UrlShortener.Application.Commands;

public sealed record CreateShortenedUrlRequest(string Url);

public sealed class CreateShortenedUrlRequestHandler(
    IAppDbContext appDbContext,
    ICacheService cacheService,
    IConfiguration configuration
)
{
    public async Task<string> InvokeAsync(
        CreateShortenedUrlRequest request,
        CancellationToken cancellationToken
    )
    {
        var urlExist = await appDbContext.ShortenedUrls.AnyAsync(
            p => p.Url == request.Url,
            cancellationToken
        );
        if (urlExist)
        {
            throw new Exception("Url already exists");
        }

        var shortCode = GenerateShortCode();
        while (true)
        {
            var shortCodeExist = await appDbContext.ShortenedUrls.AnyAsync(
                p => p.ShortCode == shortCode,
                cancellationToken
            );
            if (!shortCodeExist)
                break;
            shortCode = GenerateShortCode();
        }

        var entity = ShortenedUrl.Create(request.Url, shortCode);

        await appDbContext.ShortenedUrls.AddAsync(entity, cancellationToken);

        await appDbContext.SaveChangesAsync(cancellationToken);

        await cacheService.AddAsync(
            request.Url,
            shortCode,
            TimeSpan.FromDays(configuration.GetOrThrowException<int>("Url:CacheExpiresInDays"))
        );

        return shortCode;
    }

    private string GenerateShortCode()
    {
        const string chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        var codeLength = configuration.GetOrThrowException<int>("Url:CodeLength");
        var result = new char[codeLength];
        using var rng = RandomNumberGenerator.Create();
        var tokenData = new byte[codeLength];
        rng.GetBytes(tokenData);
        for (var i = 0; i < codeLength; i++)
        {
            result[i] = chars[tokenData[i] % chars.Length];
        }
        return new string(result);
    }
}
