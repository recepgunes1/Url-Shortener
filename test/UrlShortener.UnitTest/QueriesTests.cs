using Microsoft.Extensions.Configuration;
using Moq;
using UrlShortener.Application.Abstracts;
using UrlShortener.Application.Queries;
using UrlShortener.Domain.Entities;

namespace UrlShortener.UnitTest;

[TestFixture]
public class QueriesTests
{
    [Test]
    public async Task GetShortCodeQuery_WithValidUrl_ShouldReturnShortCode()
    {
        // Arrange
        var mockCacheService = new Mock<ICacheService>();

        var configDict = new Dictionary<string, string> { { "Url:CacheExpiresInDays", "1" } };

        var configuration = new ConfigurationBuilder().AddInMemoryCollection(configDict!).Build();

        await using var dbContext = Utils.CreateDbContext();

        // Seed the database with a shortened URL
        var shortenedUrl = ShortenedUrl.Create("https://www.example.com/some/long/url", "abc123");

        dbContext.ShortenedUrls.Add(shortenedUrl);
        await dbContext.SaveChangesAsync();

        var handler = new GetShortCodeRequestHandler(
            dbContext,
            mockCacheService.Object,
            configuration
        );

        var request = new GetShortCodeRequest("https://www.example.com/some/long/url");
        var cancellationToken = CancellationToken.None;

        // Act
        var result = await handler.InvokeAsync(request, cancellationToken);

        // Assert
        Assert.That(result, Is.EqualTo("abc123"));
        mockCacheService.Verify(
            x =>
                x.AddAsync(
                    It.Is<string>(u => u == shortenedUrl.Url),
                    It.Is<string>(sc => sc == shortenedUrl.ShortCode),
                    It.IsAny<TimeSpan>()
                ),
            Times.Once
        );
    }

    [Test]
    public async Task GetUrlQuery_WithValidShortCodeInCache_ShouldReturnUrlFromCache()
    {
        // Arrange
        var mockCacheService = new Mock<ICacheService>();
        mockCacheService
            .Setup(x => x.GetAsync(It.IsAny<string>()))
            .ReturnsAsync("https://www.example.com/some/long/url");

        var configDict = new Dictionary<string, string> { { "Url:CacheExpiresInDays", "1" } };

        var configuration = new ConfigurationBuilder().AddInMemoryCollection(configDict!).Build();

        await using var dbContext = Utils.CreateDbContext();

        var handler = new GetUrlRequestHandler(dbContext, mockCacheService.Object, configuration);

        var request = new GetUrlRequest("abc123");
        var cancellationToken = CancellationToken.None;

        // Act
        var result = await handler.InvokeAsync(request, cancellationToken);

        // Assert
        Assert.That(result, Is.EqualTo("https://www.example.com/some/long/url"));
        mockCacheService.Verify(x => x.GetAsync(It.Is<string>(sc => sc == "abc123")), Times.Once);
    }

    [Test]
    public async Task GetUrlQuery_WithValidShortCodeNotInCache_ShouldReturnUrlFromDatabase()
    {
        // Arrange
        var mockCacheService = new Mock<ICacheService>();
        mockCacheService.Setup(x => x.GetAsync(It.IsAny<string>())).ReturnsAsync((string?)null);

        var configDict = new Dictionary<string, string> { { "Url:CacheExpiresInDays", "1" } };
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(configDict!).Build();

        await using var dbContext = Utils.CreateDbContext();

        var shortenedUrl = ShortenedUrl.Create("https://www.example.com/long/url", "abc123");
        dbContext.ShortenedUrls.Add(shortenedUrl);
        await dbContext.SaveChangesAsync();

        var handler = new GetUrlRequestHandler(dbContext, mockCacheService.Object, configuration);
        var request = new GetUrlRequest("abc123");

        // Act
        var result = await handler.InvokeAsync(request, CancellationToken.None);

        // Assert
        Assert.That(result, Is.EqualTo("https://www.example.com/long/url")); // Not "abc123"
    }
}
