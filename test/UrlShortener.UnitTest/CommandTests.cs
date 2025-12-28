using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Moq;
using UrlShortener.Application.Abstracts;
using UrlShortener.Application.Commands;

namespace UrlShortener.UnitTest;

[TestFixture]
public class CommandTests
{
    [Test]
    public async Task CreateShortenedUrlCommand_WithValidUrl_ShouldCreateShortenedUrl()
    {
        // Arrange
        var mockCacheService = new Mock<ICacheService>();

        var configDict = new Dictionary<string, string>
        {
            { "Url:CodeLength", "6" },
            { "Url:CacheExpiresInDays", "1" },
        };

        var configuration = new ConfigurationBuilder().AddInMemoryCollection(configDict!).Build();

        await using var dbContext = Utils.CreateDbContext();

        var handler = new CreateShortenedUrlRequestHandler(
            dbContext,
            mockCacheService.Object,
            configuration
        );

        var request = new CreateShortenedUrlRequest("https://www.example.com/some/long/url");
        var cancellationToken = CancellationToken.None;

        // Act
        var result = await handler.InvokeAsync(request, cancellationToken);

        // Assert
        Assert.That(result, Is.Not.Null);
        Assert.That(result, Is.Not.Empty);
        Assert.That(result, Has.Length.EqualTo(6));

        var savedUrl = await dbContext.ShortenedUrls.FirstOrDefaultAsync(
            x => x.ShortCode == result,
            cancellationToken
        );

        Assert.That(savedUrl, Is.Not.Null);
        Assert.That(savedUrl.Url, Is.EqualTo(request.Url));
    }
}
