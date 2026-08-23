using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Web.Script.Serialization;

internal sealed class FilterChannelResult
{
    public bool Changed { get; set; }
    public int ChangedFiles { get; set; }
    public string ChannelTag { get; set; }
    public string FilterDigest { get; set; }
}

internal static class FilterChannelClient
{
    private const string DefaultChannelApi =
        "https://api.github.com/repos/DiegoJohnsonL/divine-hunters-filter/releases/tags/filter-latest";
    private const string FilterAssetName = "DivineHunters.filter";
    private const string FilterFileName = "Divine Hunters.filter";
    private const string LegacyFilterFileName = "FinancialAdvisor Filter.filter";
    private const int MaxFilterBackups = 1;

    // Sounds are installed before the filter. If publication is interrupted, an old
    // filter can safely use new sounds; a new filter is never installed without all
    // of the assets it references already present and verified.
    private static readonly string[] RequiredAssets =
    {
        "hibdivine.mp3",
        "HibOmenLight.mp3",
        "Echoes.mp3",
        "OmenOfTheLiege.mp3",
        "OrbOfAnnulment.mp3",
        FilterAssetName
    };

    static FilterChannelClient()
    {
        ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
    }

    public static FilterChannelResult InstallLatest(string targetFolder, Action<string> log)
    {
        if (string.IsNullOrWhiteSpace(targetFolder))
            throw new InvalidOperationException("The filter destination is empty.");

        targetFolder = Path.GetFullPath(targetFolder);
        Directory.CreateDirectory(targetFolder);

        Dictionary<string, object> release = ReadRelease();
        string channelTag = ReadString(release, "tag_name");
        if (!string.Equals(channelTag, "filter-latest", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("The GitHub filter channel returned an unexpected tag: " + channelTag);

        Dictionary<string, Dictionary<string, object>> assets = IndexAssets(release);
        Dictionary<string, string> expectedDigests = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (string name in RequiredAssets)
        {
            Dictionary<string, object> asset;
            if (!assets.TryGetValue(name, out asset))
                throw new InvalidOperationException("The filter channel is missing required asset: " + name);
            expectedDigests[name] = ParseDigest(ReadString(asset, "digest"), name);
        }

        List<string> changed = new List<string>();
        foreach (string name in RequiredAssets)
        {
            string destination = Path.Combine(targetFolder, GetDestinationName(name));
            if (!File.Exists(destination) || !DigestMatches(destination, expectedDigests[name]))
                changed.Add(name);
        }

        if (changed.Count == 0)
        {
            if (log != null)
                log("Filter channel is current (" + ShortDigest(expectedDigests[FilterAssetName]) + ").");
            return new FilterChannelResult
            {
                Changed = false,
                ChangedFiles = 0,
                ChannelTag = channelTag,
                FilterDigest = expectedDigests[FilterAssetName]
            };
        }

        string temporaryFolder = Path.Combine(
            Path.GetTempPath(),
            "DivineHuntersFilter-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(temporaryFolder);

        try
        {
            // Download and verify every changed asset before touching the game folder.
            foreach (string name in changed)
            {
                Dictionary<string, object> asset = assets[name];
                string downloadUrl = ReadString(asset, "browser_download_url");
                if (string.IsNullOrWhiteSpace(downloadUrl))
                    throw new InvalidOperationException("The filter channel has no download URL for " + name + ".");

                string downloaded = Path.Combine(temporaryFolder, name);
                Download(downloadUrl, downloaded);
                VerifySha256(downloaded, expectedDigests[name], name);
                if (string.Equals(name, FilterAssetName, StringComparison.OrdinalIgnoreCase))
                    ValidateFilter(downloaded);
                else
                    ValidateAudio(downloaded, name);
            }

            if (changed.Contains(FilterAssetName))
                BackupCurrentFilter(targetFolder);

            // RequiredAssets deliberately places the filter last.
            foreach (string name in RequiredAssets)
            {
                if (!changed.Contains(name))
                    continue;
                AtomicInstall(
                    Path.Combine(temporaryFolder, name),
                    Path.Combine(targetFolder, GetDestinationName(name)));
            }

            string legacyPath = Path.Combine(targetFolder, LegacyFilterFileName);
            if (File.Exists(legacyPath) && File.Exists(Path.Combine(targetFolder, FilterFileName)))
                File.Delete(legacyPath);

            if (log != null)
                log("Installed " + changed.Count + " filter-channel file(s); filter " +
                    ShortDigest(expectedDigests[FilterAssetName]) + ".");

            return new FilterChannelResult
            {
                Changed = true,
                ChangedFiles = changed.Count,
                ChannelTag = channelTag,
                FilterDigest = expectedDigests[FilterAssetName]
            };
        }
        finally
        {
            TryDeleteDirectory(temporaryFolder);
        }
    }

    private static Dictionary<string, object> ReadRelease()
    {
        string apiUrl = Environment.GetEnvironmentVariable("DIVINEHUNTERS_FILTER_CHANNEL_API");
        if (string.IsNullOrWhiteSpace(apiUrl))
            apiUrl = DefaultChannelApi;

        using (WebClient client = CreateClient(apiUrl))
        {
            string json = client.DownloadString(apiUrl);
            JavaScriptSerializer serializer = new JavaScriptSerializer();
            Dictionary<string, object> release = serializer.DeserializeObject(json) as Dictionary<string, object>;
            if (release == null)
                throw new InvalidOperationException("The GitHub filter channel returned invalid JSON.");
            return release;
        }
    }

    private static Dictionary<string, Dictionary<string, object>> IndexAssets(Dictionary<string, object> release)
    {
        object rawAssets;
        if (!release.TryGetValue("assets", out rawAssets))
            throw new InvalidOperationException("The filter channel has no assets.");

        object[] list = rawAssets as object[];
        if (list == null)
            throw new InvalidOperationException("The filter channel asset list is invalid.");

        Dictionary<string, Dictionary<string, object>> result =
            new Dictionary<string, Dictionary<string, object>>(StringComparer.OrdinalIgnoreCase);
        foreach (object raw in list)
        {
            Dictionary<string, object> asset = raw as Dictionary<string, object>;
            string name = ReadString(asset, "name");
            if (!string.IsNullOrWhiteSpace(name))
                result[name] = asset;
        }
        return result;
    }

    private static string ReadString(Dictionary<string, object> values, string key)
    {
        object value;
        return values != null && values.TryGetValue(key, out value) && value != null
            ? Convert.ToString(value)
            : string.Empty;
    }

    private static string GetDestinationName(string assetName)
    {
        return string.Equals(assetName, FilterAssetName, StringComparison.OrdinalIgnoreCase)
            ? FilterFileName
            : assetName;
    }

    private static WebClient CreateClient(string url)
    {
        WebClient client = new WebClient();
        Uri uri;
        if (Uri.TryCreate(url, UriKind.Absolute, out uri) &&
            (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps))
        {
            client.Headers[HttpRequestHeader.Accept] = "application/vnd.github+json";
            client.Headers[HttpRequestHeader.UserAgent] = "DivineHuntersFilter/" + BuildInfo.Version;
            client.Headers["X-GitHub-Api-Version"] = "2022-11-28";
        }
        return client;
    }

    private static void Download(string url, string destination)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(destination));
        using (WebClient client = CreateClient(url))
            client.DownloadFile(url, destination);
    }

    private static string ParseDigest(string digest, string assetName)
    {
        if (string.IsNullOrWhiteSpace(digest))
            throw new InvalidOperationException("GitHub supplied no SHA-256 digest for " + assetName + ".");

        string value = digest.Trim();
        if (value.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase))
            value = value.Substring("sha256:".Length);
        if (value.Length != 64)
            throw new InvalidOperationException("GitHub supplied an invalid SHA-256 digest for " + assetName + ".");
        for (int index = 0; index < value.Length; index++)
        {
            if (!Uri.IsHexDigit(value[index]))
                throw new InvalidOperationException("GitHub supplied an invalid SHA-256 digest for " + assetName + ".");
        }
        return value.ToLowerInvariant();
    }

    private static bool DigestMatches(string path, string expected)
    {
        return string.Equals(ComputeSha256(path), expected, StringComparison.OrdinalIgnoreCase);
    }

    private static void VerifySha256(string path, string expected, string assetName)
    {
        if (!DigestMatches(path, expected))
            throw new InvalidOperationException("The downloaded " + assetName + " failed its SHA-256 check.");
    }

    private static string ComputeSha256(string path)
    {
        using (SHA256 sha256 = SHA256.Create())
        using (FileStream input = File.OpenRead(path))
        {
            byte[] bytes = sha256.ComputeHash(input);
            StringBuilder builder = new StringBuilder(bytes.Length * 2);
            foreach (byte value in bytes)
                builder.Append(value.ToString("x2"));
            return builder.ToString();
        }
    }

    private static string ShortDigest(string digest)
    {
        return digest.Length > 12 ? digest.Substring(0, 12) : digest;
    }

    private static void ValidateFilter(string path)
    {
        FileInfo info = new FileInfo(path);
        if (info.Length < 100000)
            throw new InvalidOperationException("The downloaded filter is unexpectedly small.");

        string text;
        try
        {
            byte[] bytes = File.ReadAllBytes(path);
            text = new UTF8Encoding(false, true).GetString(bytes);
        }
        catch (DecoderFallbackException)
        {
            throw new InvalidOperationException("The downloaded filter is not valid UTF-8.");
        }

        string[] requiredMarkers =
        {
            "# NeverSink's Indepth Loot Filter - for Path of Exile 2",
            "# CUSTOMIZED COPY - built on stock 6-UBER-PLUS-STRICT.",
            "# [CUSTOM][ECONOMY] Live lineage support pickup policy",
            "# [CUSTOM][ECONOMY] Live essence pickup policy",
            "# [CUSTOM][ECONOMY] Live unique pickup policy",
            "Hide # [CUSTOM][ECONOMY] visible unique bases below"
        };
        foreach (string marker in requiredMarkers)
        {
            if (text.IndexOf(marker, StringComparison.Ordinal) < 0)
                throw new InvalidOperationException("The downloaded filter failed validation; missing marker: " + marker);
        }
        if (text.IndexOf('\0') >= 0 || text.IndexOf('\uFFFD') >= 0)
            throw new InvalidOperationException("The downloaded filter contains invalid characters.");
    }

    private static void ValidateAudio(string path, string name)
    {
        if (new FileInfo(path).Length < 1024)
            throw new InvalidOperationException("The downloaded sound is unexpectedly small: " + name);
    }

    private static void BackupCurrentFilter(string targetFolder)
    {
        string filterPath = Path.Combine(targetFolder, FilterFileName);
        string legacyPath = Path.Combine(targetFolder, LegacyFilterFileName);
        string source = File.Exists(filterPath) ? filterPath : File.Exists(legacyPath) ? legacyPath : null;
        if (source == null)
            return;

        string backup = filterPath + ".before-divinehunters-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".bak";
        File.Copy(source, backup, true);
        PruneFilterBackups(targetFolder, filterPath);
    }

    private static void PruneFilterBackups(string targetFolder, string filterPath)
    {
        FileInfo[] backups;
        try
        {
            backups = new DirectoryInfo(targetFolder).GetFiles(Path.GetFileName(filterPath) + ".before-divinehunters-*.bak");
        }
        catch
        {
            return;
        }

        Array.Sort(backups, delegate(FileInfo left, FileInfo right)
        {
            int compare = right.LastWriteTimeUtc.CompareTo(left.LastWriteTimeUtc);
            return compare != 0 ? compare : StringComparer.OrdinalIgnoreCase.Compare(right.Name, left.Name);
        });
        for (int index = MaxFilterBackups; index < backups.Length; index++)
        {
            try { backups[index].Delete(); }
            catch { }
        }
    }

    private static void AtomicInstall(string source, string destination)
    {
        string staged = destination + ".download-" + Guid.NewGuid().ToString("N");
        File.Copy(source, staged, true);
        try
        {
            if (File.Exists(destination))
                File.Replace(staged, destination, null, true);
            else
                File.Move(staged, destination);
        }
        finally
        {
            try { if (File.Exists(staged)) File.Delete(staged); }
            catch { }
        }
    }

    private static void TryDeleteDirectory(string path)
    {
        try
        {
            if (!string.IsNullOrWhiteSpace(path) && Directory.Exists(path))
                Directory.Delete(path, true);
        }
        catch
        {
            // Temporary cleanup is best effort.
        }
    }
}
