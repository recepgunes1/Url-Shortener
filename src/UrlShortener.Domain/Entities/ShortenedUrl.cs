using UrlShortener.Domain.Core;

namespace UrlShortener.Domain.Entities;

public sealed class ShortenedUrl : Entity
{
    public string Url { get; set; } = null!;
    public string ShortCode { get; set; } = null!;

    private ShortenedUrl() { }

    public static ShortenedUrl Create(string url, string shortCode)
    {
        if (string.IsNullOrWhiteSpace(url))
            throw new Exception("URL cannot be empty");

        if (!Uri.TryCreate(url, UriKind.Absolute, out _))
            throw new Exception("Invalid URL format");

        if (string.IsNullOrWhiteSpace(shortCode))
            throw new Exception("Short code must be between 3 and 10 characters");

        return new ShortenedUrl { Url = url, ShortCode = shortCode };
    }
}
