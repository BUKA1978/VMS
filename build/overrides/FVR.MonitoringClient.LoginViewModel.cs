using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using FVR.MonitoringClient.Services;

namespace FVR.MonitoringClient.ViewModels;

public partial class LoginViewModel : ObservableObject
{
    private readonly ApiClient _apiClient;
    private readonly SessionService _session;

    [ObservableProperty] private string _serverAddress = string.Empty;
    [ObservableProperty] private string _username = string.Empty;
    [ObservableProperty] private string _errorMessage = string.Empty;
    [ObservableProperty] private bool _isBusy;

    public event Action? LoginSucceeded;

    public LoginViewModel(ApiClient apiClient, SessionService session)
    {
        _apiClient = apiClient;
        _session = session;
        ServerAddress = _apiClient.BaseUrl;
        Username = "admin";
    }

    [RelayCommand]
    private async Task LoginAsync(string password)
    {
        if (string.IsNullOrWhiteSpace(ServerAddress))
        {
            ErrorMessage = "Informe o endereço do Management Server.";
            return;
        }

        if (string.IsNullOrWhiteSpace(Username) || string.IsNullOrWhiteSpace(password))
        {
            ErrorMessage = "Informe usuário e senha.";
            return;
        }

        IsBusy = true;
        ErrorMessage = string.Empty;

        try
        {
            _apiClient.SetBaseUrl(ServerAddress);
            ServerAddress = _apiClient.BaseUrl;

            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(8));
            var available = await _apiClient.IsManagementServerAvailableAsync(cts.Token);
            if (!available)
            {
                ErrorMessage = $"Management Server não encontrado em {ServerAddress}. " +
                               "Verifique o IP, a porta 5000 e se o serviço FVR Management Server está em execução.";
                return;
            }

            var result = await _apiClient.LoginAsync(Username, password);
            if (result is null)
            {
                ErrorMessage = "Management Server encontrado, mas usuário ou senha são inválidos.";
                return;
            }

            _session.SetSession(result);
            LoginSucceeded?.Invoke();
        }
        catch (ArgumentException ex)
        {
            ErrorMessage = ex.Message;
        }
        catch (Exception ex)
        {
            ErrorMessage = $"Falha ao conectar ao Management Server: {ex.Message}";
        }
        finally
        {
            IsBusy = false;
        }
    }
}
