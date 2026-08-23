using System;
using System.Diagnostics;
using System.IO;

internal static class DivineHuntersUpdaterProgram
{
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
                    Log("Another filter update check is already running.");
                    return 0;
                }

                if (IsPathOfExileRunning())
                {
                    Log("Path of Exile 2 is running; filter update postponed.");
                    return 0;
                }

                FilterChannelResult result = FilterChannelClient.InstallLatest(targetFolder, Log);
                File.WriteAllText(FilterDigestPath, result.FilterDigest);
            }
            return 0;
        }
        catch (Exception ex)
        {
            Log("Filter update failed: " + ex.Message);
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

    private static string FilterDigestPath
    {
        get { return Path.Combine(StateFolder, "installed-filter-sha256.txt"); }
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

    private static bool IsPathOfExileRunning()
    {
        if (string.Equals(Environment.GetEnvironmentVariable("DIVINEHUNTERS_SKIP_GAME_CHECK"), "1", StringComparison.Ordinal))
            return false;

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

    private static void Log(string message)
    {
        try
        {
            Directory.CreateDirectory(StateFolder);
            File.AppendAllText(
                LogPath,
                DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " " + message + Environment.NewLine);
        }
        catch
        {
            // The updater is intentionally silent if its log cannot be written.
        }
    }
}
