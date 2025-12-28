using UrlShortener.API;
using UrlShortener.Application;
using UrlShortener.Infrastructure;

var builder = WebApplication.CreateBuilder(args);

builder.LoadMonitoring();

builder.Services.AddInfrastructure(builder.Configuration);

builder.Services.AddApplication();

builder.Services.AddAPI();

var app = builder.Build();

app.LoadAPI();

app.MapEndpoints();

app.Run();
