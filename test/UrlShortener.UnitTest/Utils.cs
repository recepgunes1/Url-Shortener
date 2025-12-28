using Microsoft.EntityFrameworkCore;
using UrlShortener.Infrastructure.Contexts;

namespace UrlShortener.UnitTest;

public static class Utils
{
    public static AppDbContext CreateDbContext()
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase(databaseName: Guid.NewGuid().ToString())
            .Options;

        return new AppDbContext(options);
    }
}
