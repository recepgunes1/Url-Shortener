using StackExchange.Redis;
using UrlShortener.Application.Abstracts;

namespace UrlShortener.Infrastructure.Services;

public sealed class CacheService(IConnectionMultiplexer connectionMultiplexer) : ICacheService
{
    public async Task AddAsync(string url, string shortCode, TimeSpan timeSpan)
    {
        var database = connectionMultiplexer.GetDatabase();
        await database.StringSetAsync(shortCode, url, timeSpan);
    }

    public async Task<string?> GetAsync(string shortCode)
    {
        var database = connectionMultiplexer.GetDatabase();
        var redisValue = await database.StringGetAsync(shortCode);
        return redisValue.HasValue ? redisValue.ToString() : null;
    }
}
