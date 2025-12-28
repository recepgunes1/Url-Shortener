using Microsoft.Extensions.Configuration;

namespace UrlShortener.Application.Extensions;

public static class ConfigurationExtensions
{
    public static T GetOrThrowException<T>(this IConfiguration configuration, string key)
    {
        return configuration.GetValue<T>(key) ?? throw new KeyNotFoundException(key);
    }
}
