namespace UrlShortener.Application.Abstracts;

public interface ICacheService
{
    Task AddAsync(string url, string shortCode, TimeSpan timeSpan);
    Task<string?> GetAsync(string shortCode);
}
