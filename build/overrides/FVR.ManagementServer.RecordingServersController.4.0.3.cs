using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using FVR.ManagementServer.Data;
using FVR.ManagementServer.DTOs;
using FVR.ManagementServer.Models;

namespace FVR.ManagementServer.Controllers;

[ApiController]
[Authorize]
[Route("api/[controller]")]
public class RecordingServersController : ControllerBase
{
    private readonly AppDbContext _db;
    public RecordingServersController(AppDbContext db) => _db = db;

    [HttpGet]
    public async Task<ActionResult<IEnumerable<RecordingServerResponse>>> GetAll()
    {
        var servers = await _db.RecordingServers.AsNoTracking().ToListAsync();
        return Ok(servers.Select(Map));
    }

    [HttpPost]
    [Authorize(Policy = "ServerManage")]
    public async Task<ActionResult<RecordingServerResponse>> Create(CreateRecordingServerRequest req)
    {
        var apiKey = Guid.NewGuid().ToString("N");
        var server = new RecordingServer
        {
            Name = req.Name,
            Hostname = req.Hostname,
            Port = req.Port,
            ApiKeyHash = BCrypt.Net.BCrypt.HashPassword(apiKey),
            Status = "offline"
        };
        _db.RecordingServers.Add(server);
        await _db.SaveChangesAsync();
        return Ok(new { server = Map(server), apiKey });
    }

    [HttpPost("{id:guid}/rotate-api-key")]
    [Authorize(Policy = "ServerManage")]
    public async Task<IActionResult> RotateApiKey(Guid id)
    {
        var server = await _db.RecordingServers.FindAsync(id);
        if (server is null)
            return NotFound();

        var apiKey = Guid.NewGuid().ToString("N");
        server.ApiKeyHash = BCrypt.Net.BCrypt.HashPassword(apiKey);
        server.Status = "offline";
        await _db.SaveChangesAsync();
        return Ok(new { apiKey });
    }

    [HttpPost("{id:guid}/heartbeat")]
    [AllowAnonymous]
    public async Task<IActionResult> Heartbeat(Guid id, [FromHeader(Name = "X-Api-Key")] string apiKey)
    {
        var server = await _db.RecordingServers.FindAsync(id);
        if (server is null || !BCrypt.Net.BCrypt.Verify(apiKey, server.ApiKeyHash))
            return Unauthorized();

        server.LastHeartbeat = DateTimeOffset.UtcNow;
        server.Status = "online";
        await _db.SaveChangesAsync();
        return Ok();
    }

    [HttpGet("{id:guid}/cameras")]
    [AllowAnonymous]
    public async Task<ActionResult<IEnumerable<object>>> GetAssignedCameras(Guid id,
        [FromHeader(Name = "X-Api-Key")] string apiKey)
    {
        var server = await _db.RecordingServers.FindAsync(id);
        if (server is null || !BCrypt.Net.BCrypt.Verify(apiKey, server.ApiKeyHash))
            return Unauthorized();

        var cameras = await _db.Cameras
            .Where(c => c.RecordingServerId == id)
            .AsNoTracking()
            .ToListAsync();

        var result = cameras.Select(c => new
        {
            c.Id,
            c.Name,
            c.IpAddress,
            c.RtspUrl,
            c.OnvifUrl,
            c.Username,
            Password = string.IsNullOrEmpty(c.PasswordEnc) ? null : Models.CryptoHelper.Decrypt(c.PasswordEnc),
            c.Codec,
            c.PtzEnabled,
            c.Enabled,
            RetentionDays = 30
        });

        return Ok(result);
    }

    private static RecordingServerResponse Map(RecordingServer s) => new(
        s.Id, s.Name, s.Hostname, s.Port, s.Status, s.LastHeartbeat
    );
}
