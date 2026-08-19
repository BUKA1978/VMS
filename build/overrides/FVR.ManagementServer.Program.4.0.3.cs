using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using FVR.ManagementServer.Data;
using FVR.ManagementServer.Models;
using FVR.ManagementServer.Services;

var logDir = Path.Combine(
    Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
    "FVR VMS",
    "Logs");
Directory.CreateDirectory(logDir);
var lifecycleLog = Path.Combine(logDir, "management-lifecycle.log");

void LifecycleLog(string message)
{
    try
    {
        File.AppendAllText(
            lifecycleLog,
            $"{DateTimeOffset.Now:O} PID={Environment.ProcessId} {message}{Environment.NewLine}",
            Encoding.UTF8);
    }
    catch
    {
        // A falha no log nunca deve derrubar o Management Server.
    }
}

Directory.SetCurrentDirectory(AppContext.BaseDirectory);
LifecycleLog($"PROCESS START. BaseDirectory={AppContext.BaseDirectory}; CurrentDirectory={Environment.CurrentDirectory}; User={Environment.UserName}");

AppDomain.CurrentDomain.UnhandledException += (_, e) =>
{
    LifecycleLog($"UNHANDLED EXCEPTION. Terminating={e.IsTerminating}; Exception={e.ExceptionObject}");
};

TaskScheduler.UnobservedTaskException += (_, e) =>
{
    LifecycleLog($"UNOBSERVED TASK EXCEPTION. Exception={e.Exception}");
    e.SetObserved();
};

try
{
    var builder = WebApplication.CreateBuilder(new WebApplicationOptions
    {
        Args = args,
        ContentRootPath = AppContext.BaseDirectory
    });

    builder.Services.AddWindowsService(options => options.ServiceName = "FVR Management Server");
    builder.WebHost.UseUrls("http://0.0.0.0:5000");
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

    app.Lifetime.ApplicationStarted.Register(() => LifecycleLog("APPLICATION STARTED"));
    app.Lifetime.ApplicationStopping.Register(() => LifecycleLog("APPLICATION STOPPING"));
    app.Lifetime.ApplicationStopped.Register(() => LifecycleLog("APPLICATION STOPPED"));

    using (var scope = app.Services.CreateScope())
    {
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        Exception? lastError = null;
        var connected = false;

        for (var attempt = 1; attempt <= 45; attempt++)
        {
            try
            {
                await db.Database.OpenConnectionAsync();
                await db.Database.CloseConnectionAsync();
                connected = true;
                LifecycleLog($"DATABASE CONNECTION OK on attempt {attempt}");
                break;
            }
            catch (Exception ex)
            {
                lastError = ex;
                LifecycleLog($"DATABASE CONNECTION FAILED attempt {attempt}: {ex.GetType().Name}: {ex.Message}");
                if (attempt < 45)
                    await Task.Delay(TimeSpan.FromSeconds(1));
            }
        }

        if (!connected)
            throw new InvalidOperationException("Não foi possível conectar ao banco FVR VMS após 45 tentativas.", lastError);

        var adminUsername = config["BootstrapAdmin:Username"] ?? "admin";
        var adminPassword = config["BootstrapAdmin:Password"] ?? "FVR@2026!";
        var admin = await db.Users.FirstOrDefaultAsync(u => u.Username == adminUsername);

        if (admin is null)
        {
            db.Users.Add(new User
            {
                Username = adminUsername,
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(adminPassword, workFactor: 12),
                FullName = "Administrador FVR",
                Active = true,
                IsAdmin = true
            });
        }
        else
        {
            admin.Active = true;
            admin.IsAdmin = true;
            if (!BCrypt.Net.BCrypt.Verify(adminPassword, admin.PasswordHash))
                admin.PasswordHash = BCrypt.Net.BCrypt.HashPassword(adminPassword, workFactor: 12);
        }

        await db.SaveChangesAsync();
        LifecycleLog("ADMIN BOOTSTRAP OK");
    }

    if (app.Environment.IsDevelopment())
    {
        app.UseSwagger();
        app.UseSwaggerUI();
    }

    app.UseCors("ClientApps");
    app.UseAuthentication();
    app.UseAuthorization();

    app.MapGet("/health", () => Results.Ok(new
    {
        status = "ok",
        product = "FVR VMS",
        version = "4.0.3",
        service = "Management Server",
        pid = Environment.ProcessId,
        utc = DateTimeOffset.UtcNow
    })).AllowAnonymous();

    app.MapControllers();

    LifecycleLog("ENTERING RunAsync");
    await app.RunAsync();
    LifecycleLog("RunAsync RETURNED normally");
}
catch (Exception ex)
{
    LifecycleLog($"FATAL EXCEPTION: {ex}");
    throw;
}
finally
{
    LifecycleLog("PROCESS EXITING");
}
