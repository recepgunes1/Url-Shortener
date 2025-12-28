using Microsoft.EntityFrameworkCore;
using UrlShortener.Domain.Entities;

namespace UrlShortener.Application.Abstracts;

public interface IAppDbContext
{
    DbSet<ShortenedUrl> ShortenedUrls { get; set; }
    Task<int> SaveChangesAsync(CancellationToken cancellationToken);
}
