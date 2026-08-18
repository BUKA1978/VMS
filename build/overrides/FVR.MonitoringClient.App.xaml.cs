using System.Net.Http;
using System.Windows;
using LibVLCSharp.Shared;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using FVR.MonitoringClient.Services;
using FVR.MonitoringClient.ViewModels;
using FVR.MonitoringClient.Views;

namespace FVR.MonitoringClient;

public partial class App : System.Windows.Application
{
    public static IServiceProvider ServiceProvider { get; private set; } = default!;

    protected override void OnStartup(System.Windows.StartupEventArgs e)
    {
        base.OnStartup(e);

        Core.Initialize();

        var config = new ConfigurationBuilder()
            .SetBasePath(AppContext.BaseDirectory)
            .AddJsonFile("appsettings.json", optional: false)
            .Build();

        var services = new ServiceCollection();
        var managementServerUrl = config["ManagementServerUrl"] ?? "http://localhost:5000";

        services.AddSingleton(new ApiClient(managementServerUrl));
        services.AddSingleton<SessionService>();
        services.AddSingleton(new HttpClient { BaseAddress = new Uri(managementServerUrl) });
        services.AddSingleton<PtzService>();
        services.AddSingleton<MultiMonitorService>();
        services.AddSingleton(new LibVLC(enableDebugLogs: false));

        services.AddTransient<LoginViewModel>();
        services.AddTransient<MainViewModel>();
        services.AddTransient<LoginWindow>();
        services.AddTransient<MainWindow>();

        ServiceProvider = services.BuildServiceProvider();

        var login = ServiceProvider.GetRequiredService<LoginWindow>();
        login.Show();
    }
}
