using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using FVR.ManagementServer.Data;
using FVR.ManagementServer.Models;
using FVR.ManagementServer.Services;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddWindowsService(options => options.ServiceName = "FVR Management Server");
var config = builder.Configuration;

builder.Services.AddDbContext<AppDbContext>(opt =>
    opt.UseNpgsql(config.GetConnectionString("Default")));

CryptoHelper.Key = Encoding.UTF8.GetBytes(
    config["Security:CameraCredentialsKey"]
        ?? throw new InvalidOperationException("Security:CameraCredentialsKey não configurada"));

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(opt =>
    {
        opt.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = config["Jwt:Issuer"],
            ValidAudience = config["Jwt:Audience"],
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(config["Jwt:Key"]!))
        };
    });

builder.Services.AddAuthorization(opt =>
{
    opt.AddPolicy("CameraManage", p => p.RequireClaim("isAdmin", "True"));
    opt.AddPolicy("ServerManage", p => p.RequireClaim("isAdmin", "True"));
    opt.AddPolicy("UserManage", p => p.RequireClaim("isAdmin", "True"));
});

builder.Services.AddScoped<TokenService>();
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.AddCors(opt =>
{
    opt.AddPolicy("ClientApps", p => p
        .AllowAnyHeader()
        .AllowAnyMethod()
        .SetIsOriginAllowed(_ => true)
        .AllowCredentials());
});

var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    Exception? lastError = null;
    var connected = false;

    for (var attempt = 1; attempt <= 30; attempt++)
    {
        try
        {
            await db.Database.OpenConnectionAsync();
            await db.Database.CloseConnectionAsync();
            connected = true;
            break;
        }
        catch (Exception ex)
        {
            lastError = ex;
            if (attempt < 30)
                await Task.Delay(TimeSpan.FromSeconds(1));
        }
    }

    if (!connected)
        throw new InvalidOperationException("Não foi possível conectar ao banco FVR VMS após 30 tentativas.", lastError);

    var adminUsername = config["BootstrapAdmin:Username"] ?? "admin";
    var adminPassword = config["BootstrapAdmin:Password"] ?? "FVR@2026!";

    if (!await db.Users.AnyAsync(u => u.Username == adminUsername))
    {
        db.Users.Add(new User
        {
            Username = adminUsername,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(adminPassword, workFactor: 12),
            FullName = "Administrador FVR",
            Active = true,
            IsAdmin = true
        });
        await db.SaveChangesAsync();
    }
}

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors("ClientApps");
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

app.Run();
