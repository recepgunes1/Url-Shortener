using Microsoft.EntityFrameworkCore;
using UrlShortener.Application.Abstracts;
using UrlShortener.Domain.Entities;

namespace UrlShortener.Infrastructure.Contexts;

public sealed class AppDbContext(DbContextOptions<AppDbContext> dbContextOptions)
    : DbContext(dbContextOptions),
        IAppDbContext
{
    public DbSet<ShortenedUrl> ShortenedUrls { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
        base.OnModelCreating(modelBuilder);
    }
}
