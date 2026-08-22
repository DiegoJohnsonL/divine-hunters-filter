using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;

internal static class DivineHuntersUpdaterProgram
{
    private const string LatestReleaseApi = "https://api.github.com/repos/DiegoJohnsonL/divine-hunters-filter/releases/latest";
    private const string InstallerAssetName = "DivineHuntersSetup.exe";

    public static int Main(string[] args)
    {
        if (args.Length != 2 || !string.Equals(args[0], "--target", StringComparison.OrdinalIgnoreCase))
            return 2;

        string targetFolder;
        try
        {
            targetFolder = Path.GetFullPath(args[1]);
        }
        catch
        {
            return 2;
        }

        return RunUpdate(targetFolder);
    }

    private static int RunUpdate(string targetFolder)
    {
        try
        {
            Directory.CreateDirectory(StateFolder);
            using (FileStream updateLock = AcquireUpdateLock())
            {
                if (updateLock == null)
                {
                    Log("Another update check is already running.");
                    return 0;
                }

                Version installedVersion = ReadInstalledVersion();
                Dictionary<string, object> release = GetLatestRelease();
                string tag = ReadString(release, "tag_name");
                Version latestVersion = ParseVersion(tag);
                if (latestVersion <= installedVersion)
                {
                    Log("No update needed. Installed " + installedVersion + ", latest " + latestVersion + ".");
                    return 0;
                }

                if (IsPathOfExileRunning())
                {
                    Log("Path of Exile 2 is running; update postponed.");
                    return 0;
                }

                Dictionary<string, object> asset = FindInstallerAsset(release);
                string downloadUrl = ReadString(asset, "browser_download_url");
                string digest = ReadString(asset, "digest");
                if (string.IsNullOrWhiteSpace(downloadUrl))
                    throw new InvalidOperationException("The latest release has no installer download URL.");

                string downloadPath = Path.Combine(Path.GetTempPath(), "DivineHuntersSetup-" + Guid.NewGuid().ToString("N") + ".exe");
                try
                {
                    Download(downloadUrl, downloadPath);
                    VerifySha256(downloadPath, digest);
                    int exitCode = RunInstallerUpdate(downloadPath, targetFolder);
                    if (exitCode != 0)
                        throw new InvalidOperationException("The installer update returned exit code " + exitCode + ".");

                    File.WriteAllText(VersionPath, latestVersion.ToString(3), Encoding.UTF8);
                    Log("Updated to " + tag + ".");
                }
                finally
                {
                    TryDelete(downloadPath);
                }
            }
            return 0;
        }
        catch (Exception ex)
        {
            Log("Update failed: " + ex.Message);
            return 1;
        }
    }

    private static string StateFolder
    {
        get
        {
                string overrideFolder = Environment.GetEnvironmentVariable("DIVINEHUNTERS_UPDATER_STATE");
            if (!string.IsNullOrWhiteSpace(overrideFolder))
                return overrideFolder;

            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "DivineHuntersFilter");
        }
    }

    private static string VersionPath
    {
        get { return Path.Combine(StateFolder, "installed-version.txt"); }
    }

    private static string LogPath
    {
        get { return Path.Combine(StateFolder, "updater.log"); }
    }

    private static string LockPath
    {
        get { return Path.Combine(StateFolder, "update.lock"); }
    }

    private static FileStream AcquireUpdateLock()
    {
        try
        {
            return new FileStream(LockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        }
        catch (IOException)
        {
            return null;
        }
    }

    private static Version ReadInstalledVersion()
    {
        try
        {
            Version version;
            if (File.Exists(VersionPath) && Version.TryParse(File.ReadAllText(VersionPath).Trim(), out version))
                return version;
        }
        catch
        {
            // A missing or damaged state file simply causes a normal update check.
        }
        return new Version(0, 0, 0);
    }

    private static Dictionary<string, object> GetLatestRelease()
    {
        string apiUrl = Environment.GetEnvironmentVariable("DIVINEHUNTERS_UPDATE_API");
        if (string.IsNullOrWhiteSpace(apiUrl))
            apiUrl = LatestReleaseApi;

        using (WebClient client = new WebClient())
        {
            client.Headers[HttpRequestHeader.Accept] = "application/vnd.github+json";
            client.Headers[HttpRequestHeader.UserAgent] = "DivineHuntersUpdater/" + BuildInfo.Version;
            client.Headers["X-GitHub-Api-Version"] = "2022-11-28";
            string json = client.DownloadString(apiUrl);
            JavaScriptSerializer serializer = new JavaScriptSerializer();
            return serializer.DeserializeObject(json) as Dictionary<string, object>;
        }
    }

    private static Dictionary<string, object> FindInstallerAsset(Dictionary<string, object> release)
    {
        object rawAssets;
        if (!release.TryGetValue("assets", out rawAssets))
            throw new InvalidOperationException("The latest release has no assets.");

        object[] assets = rawAssets as object[];
        if (assets != null)
        {
            foreach (object rawAsset in assets)
            {
                Dictionary<string, object> asset = rawAsset as Dictionary<string, object>;
                if (asset != null && string.Equals(ReadString(asset, "name"), InstallerAssetName, StringComparison.OrdinalIgnoreCase))
                    return asset;
            }
        }
        throw new InvalidOperationException("The latest release has no " + InstallerAssetName + " asset.");
    }

    private static string ReadString(Dictionary<string, object> values, string key)
    {
        object value;
        return values != null && values.TryGetValue(key, out value) && value != null
            ? Convert.ToString(value)
            : string.Empty;
    }

    private static Version ParseVersion(string tag)
    {
        string value = (tag ?? string.Empty).Trim();
        if (value.StartsWith("v", StringComparison.OrdinalIgnoreCase))
            value = value.Substring(1);

        Version version;
        if (!Version.TryParse(value, out version))
            throw new InvalidOperationException("The latest release tag is not a valid version: " + tag);
        return version;
    }

    private static void Download(string url, string destination)
    {
        using (WebClient client = new WebClient())
        {
            client.Headers[HttpRequestHeader.UserAgent] = "DivineHuntersUpdater/" + BuildInfo.Version;
            client.DownloadFile(url, destination);
        }
    }

    private static void VerifySha256(string path, string digest)
    {
        if (string.IsNullOrWhiteSpace(digest))
            throw new InvalidOperationException("The release asset has no SHA-256 digest.");

        string expected = digest.Trim();
        if (expected.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase))
            expected = expected.Substring("sha256:".Length);

        using (SHA256 sha256 = SHA256.Create())
        using (FileStream input = File.OpenRead(path))
        {
            string actual = ToHex(sha256.ComputeHash(input));
            if (!string.Equals(actual, expected, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("The downloaded installer failed its SHA-256 check.");
        }
    }

    private static string ToHex(byte[] bytes)
    {
        StringBuilder builder = new StringBuilder(bytes.Length * 2);
        foreach (byte value in bytes)
            builder.Append(value.ToString("x2"));
        return builder.ToString();
    }

    private static int RunInstallerUpdate(string installerPath, string targetFolder)
    {
        ProcessStartInfo startInfo = new ProcessStartInfo
        {
            FileName = installerPath,
            Arguments = "--update " + QuoteArgument(targetFolder),
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = Path.GetDirectoryName(installerPath)
        };
        using (Process process = Process.Start(startInfo))
        {
            process.WaitForExit();
            return process.ExitCode;
        }
    }

    private static string QuoteArgument(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    private static bool IsPathOfExileRunning()
    {
        foreach (Process process in Process.GetProcesses())
        {
            try
            {
                if (process.ProcessName.StartsWith("PathOfExile", StringComparison.OrdinalIgnoreCase))
                    return true;
            }
            catch
            {
                // A process can disappear between enumeration and inspection.
            }
            finally
            {
                process.Dispose();
            }
        }
        return false;
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (!string.IsNullOrWhiteSpace(path) && File.Exists(path))
                File.Delete(path);
        }
        catch
        {
            // Temporary cleanup is best effort.
        }
    }

    private static void Log(string message)
    {
        try
        {
            Directory.CreateDirectory(StateFolder);
            File.AppendAllText(LogPath, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " " + message + Environment.NewLine);
        }
        catch
        {
            // The updater is intentionally silent if its log cannot be written.
        }
    }
}
