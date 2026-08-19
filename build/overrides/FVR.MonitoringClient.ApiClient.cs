using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using FVR.MonitoringClient.Models;

namespace FVR.MonitoringClient.Services;

public class ApiClient
{
    private HttpClient _http = new();
    private string? _bearerToken;
    private readonly string _settingsFile;

    public string BaseUrl { get; private set; }

    public ApiClient(string baseUrl)
    {
        var settingsDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "FVR VMS");
        Directory.CreateDirectory(settingsDir);
        _settingsFile = Path.Combine(settingsDir, "management-server.txt");

        var saved = File.Exists(_settingsFile)
            ? File.ReadAllText(_settingsFile).Trim()
            : string.Empty;

        BaseUrl = NormalizeBaseUrl(string.IsNullOrWhiteSpace(saved) ? baseUrl : saved);
        RecreateHttpClient();
    }

    public static string NormalizeBaseUrl(string input)
    {
        var value = (input ?? string.Empty).Trim();
        if (string.IsNullOrWhiteSpace(value))
            value = "127.0.0.1";

        if (!value.Contains("://", StringComparison.Ordinal))
            value = "http://" + value;

        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri))
            throw new ArgumentException("Endereço do Management Server inválido.");

        var builder = new UriBuilder(uri)
        {
            Scheme = string.IsNullOrWhiteSpace(uri.Scheme) ? "http" : uri.Scheme,
            Path = string.Empty,
            Query = string.Empty,
            Fragment = string.Empty
        };

        if (uri.IsDefaultPort)
            builder.Port = 5000;

        return builder.Uri.GetLeftPart(UriPartial.Authority).TrimEnd('/');
    }

    public void SetBaseUrl(string baseUrl, bool persist = true)
    {
        var normalized = NormalizeBaseUrl(baseUrl);
        if (string.Equals(BaseUrl, normalized, StringComparison.OrdinalIgnoreCase))
        {
            if (persist) PersistServer(normalized);
            return;
        }

        BaseUrl = normalized;
        RecreateHttpClient();
        if (persist) PersistServer(normalized);
    }

    private void PersistServer(string server)
    {
        try
        {
            File.WriteAllText(_settingsFile, server);
        }
        catch
        {
            // Falha ao salvar preferência não deve impedir o login.
        }
    }

    private void RecreateHttpClient()
    {
        _http.Dispose();
        _http = new HttpClient
        {
            BaseAddress = new Uri(BaseUrl),
            Timeout = TimeSpan.FromSeconds(8)
        };

        if (!string.IsNullOrWhiteSpace(_bearerToken))
            _http.DefaultRequestHeaders.Authorization =
                new AuthenticationHeaderValue("Bearer", _bearerToken);
    }

    public void SetBearerToken(string? token)
    {
        _bearerToken = token;
        _http.DefaultRequestHeaders.Authorization =
            token is null ? null : new AuthenticationHeaderValue("Bearer", token);
    }

    public async Task<bool> IsManagementServerAvailableAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            using var resp = await _http.GetAsync("/health", cancellationToken);
            return resp.IsSuccessStatusCode;
        }
        catch
        {
            return false;
        }
    }

    public async Task<LoginResult?> LoginAsync(string username, string password)
    {
        var resp = await _http.PostAsJsonAsync("/api/auth/login", new { username, password });
        if (!resp.IsSuccessStatusCode) return null;
        return await resp.Content.ReadFromJsonAsync<LoginResult>();
    }

    public async Task<LoginResult?> RefreshAsync(string refreshToken)
    {
        var resp = await _http.PostAsJsonAsync("/api/auth/refresh", refreshToken);
        if (!resp.IsSuccessStatusCode) return null;
        return await resp.Content.ReadFromJsonAsync<LoginResult>();
    }

    public async Task<List<CameraDto>> GetCamerasAsync()
    {
        var result = await _http.GetFromJsonAsync<List<CameraDto>>("/api/cameras");
        return result ?? new List<CameraDto>();
    }

    public async Task<List<EventDto>> GetRecentEventsAsync(int take = 100)
    {
        var result = await _http.GetFromJsonAsync<List<EventDto>>($"/api/events?take={take}");
        return result ?? new List<EventDto>();
    }

    public async Task AcknowledgeEventAsync(Guid eventId)
    {
        await _http.PostAsync($"/api/events/{eventId}/acknowledge", null);
    }

    public async Task<List<RecordingSegmentDto>> GetRecordingsAsync(Guid cameraId, DateTimeOffset from, DateTimeOffset to)
    {
        var url = $"/api/recordings?cameraId={cameraId}&from={Uri.EscapeDataString(from.ToString("o"))}&to={Uri.EscapeDataString(to.ToString("o"))}";
        var result = await _http.GetFromJsonAsync<List<RecordingSegmentDto>>(url);
        return result ?? new List<RecordingSegmentDto>();
    }
}
