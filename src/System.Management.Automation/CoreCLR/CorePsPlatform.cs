// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

using Microsoft.Win32;
using Microsoft.Win32.SafeHandles;
using System.Linq;

namespace System.Management.Automation
{
    /// <summary>
    /// These are platform abstractions and platform specific implementations.
    /// </summary>
    public static class Platform
    {

        /// <summary>
        /// Resource enum for Linux
        /// </summary>
        public enum ResourceForUlimit
        {
            /// <summary> cpu time per process </summary>
            CpuTime               = 0,
            /// <summary> file size </summary>
            FileSize              = 1,
            /// <summary> data segment size </summary>
            DataSegmentSize       = 2,
            /// <summary> stack size </summary>
            StackSize             = 3,
            /// <summary> core file size </summary>
            CoreFileSize          = 4,
            /// <summary> address space (resident set size) </summary>
            AddresSpaceSize       = 5,
#if LUNUX_ULIMIT
            /// <summary> number of processes </summary>
            NumberOfProcesses     = 6,
            /// <summary> number of open files </summary>
            NumberOfOpenFiles     = 7,
            /// <summary> locked-in-memory address space </summary>
            LockedMemory          = 8,
            /// <summary> address space limit </summary>
            MaximumAddressSpace   = 9,
            /// <summary>Maximum file lock</summary>
            FileLock              = 10,
            /// <summary>Maximum number of pending signals</summary>
            MaximumPendingSignals = 11,
            /// <summary>Maximum POSIX message queue size in bytes</summary>
            MessageQueueSize      = 12,
            /// <summary>Maximum nice priority allowed </summary>
            MaximumNice           = 13,
            /// <summary>Maximum real-time priority</summary>
            RealTimePriority      = 14,
            /// <summary>
            /// Maximum CPU time in µs that a process scheduled under a real-time
            /// scheduling policy may consume without making a blocking system
            /// call before being forcibly descheduled.
            /// </summary>
            RealTimeCpu           = 15,
#elif MACOS_ULIMIT
            /// <summary> locked in memory space</summary>
            LockedMemory          = 6,
            /// <summary> number of processes </summary>
            NumberOfProcesses     = 7,
            /// <summary> number of open files </summary>
            NumberOfOpenFiles     = 8,
#endif
        }
        /// <summary>
        /// Resource information
        /// </summary>
        public class ResourceLimitInfo
        {
            /// <summary>
            /// The command used to retrieve the value of the resource
            /// </summary>
            public ResourceForUlimit Resource;
            /// <summary>
            /// the current limit
            /// </summary>
            public ulong Current;
            /// <summary>
            /// the maximum limit
            /// </summary>
            public ulong Maximum;
        }

        private static string _tempDirectory = null;

        /// <summary>
        /// True if the current platform is Linux.
        /// </summary>
        public static bool IsLinux
        {
            get
            {
                return RuntimeInformation.IsOSPlatform(OSPlatform.Linux);
            }
        }

        /// <summary>
        /// True if the current platform is macOS.
        /// </summary>
        public static bool IsMacOS
        {
            get
            {
                return RuntimeInformation.IsOSPlatform(OSPlatform.OSX);
            }
        }

        /// <summary>
        /// True if the current platform is Windows.
        /// </summary>
        public static bool IsWindows
        {
            get
            {
                return RuntimeInformation.IsOSPlatform(OSPlatform.Windows);
            }
        }

        /// <summary>get the size of a pipe buffer</summary>
        public static int PipeSize
        {
            get {
                return Unix.GetPipeBufSize();
            }
        }

        /// <summary>
        /// True if PowerShell was built targeting .NET Core.
        /// </summary>
        public static bool IsCoreCLR
        {
            get
            {
                return true;
            }
        }

        /// <summary>
        /// True if the underlying system is NanoServer.
        /// </summary>
        public static bool IsNanoServer
        {
            get
            {
#if UNIX
                return false;
#else
                if (_isNanoServer.HasValue) { return _isNanoServer.Value; }

                _isNanoServer = false;
                using (RegistryKey regKey = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Server\ServerLevels"))
                {
                    if (regKey != null)
                    {
                        object value = regKey.GetValue("NanoServer");
                        if (value != null && regKey.GetValueKind("NanoServer") == RegistryValueKind.DWord)
                        {
                            _isNanoServer = (int)value == 1;
                        }
                    }
                }

                return _isNanoServer.Value;
#endif
            }
        }

        /// <summary>
        /// True if the underlying system is IoT.
        /// </summary>
        public static bool IsIoT
        {
            get
            {
#if UNIX
                return false;
#else
                if (_isIoT.HasValue) { return _isIoT.Value; }

                _isIoT = false;
                using (RegistryKey regKey = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion"))
                {
                    if (regKey != null)
                    {
                        object value = regKey.GetValue("ProductName");
                        if (value != null && regKey.GetValueKind("ProductName") == RegistryValueKind.String)
                        {
                            _isIoT = string.Equals("IoTUAP", (string)value, StringComparison.OrdinalIgnoreCase);
                        }
                    }
                }

                return _isIoT.Value;
#endif
            }
        }

        /// <summary>
        /// True if underlying system is Windows Desktop.
        /// </summary>
        public static bool IsWindowsDesktop
        {
            get
            {
#if UNIX
                return false;
#else
                if (_isWindowsDesktop.HasValue) { return _isWindowsDesktop.Value; }

                _isWindowsDesktop = !IsNanoServer && !IsIoT;
                return _isWindowsDesktop.Value;
#endif
            }
        }

#if UNIX
        /// <summary>
        /// Return the umask value
        /// </summary>
        public static ushort Umask
        {
            get
            {
                return Unix.GetUmask();
            }
            set
            {
                Unix.SetUmask(value);
            }
        }
#endif

        /// <summary>
        /// Get the current resource limits for Mac
        /// </summary>
        public static ResourceLimitInfo GetResourceLimit(ResourceForUlimit command)
        {
            Unix.NativeMethods.rlimit r;
            Unix.NativeMethods.getrlimit((int)command, out r);
            ResourceLimitInfo rli = Unix.NativeMethods.rlimitToResourceLimitInfo((int)command, r);
            return rli;
        }
        /// <summary>
        /// Get the current resource limits for Mac
        /// </summary>
        public static void SetResourceLimit(Platform.ResourceLimitInfo rli)
        {
            Unix.NativeMethods.rlimit r = Unix.NativeMethods.ResourceLimitInfoTorlimit(rli);
            long result = Unix.NativeMethods.setrlimit((int)rli.Resource, out r);
            if ( result != 0 ) {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
        }

#if !UNIX
        private static bool? _isNanoServer = null;
        private static bool? _isIoT = null;
        private static bool? _isWindowsDesktop = null;
#endif

        // format files
        internal static List<string> FormatFileNames = new List<string>
            {
                "Certificate.format.ps1xml",
                "Diagnostics.format.ps1xml",
                "DotNetTypes.format.ps1xml",
                "Event.format.ps1xml",
                "FileSystem.format.ps1xml",
                "Help.format.ps1xml",
                "HelpV3.format.ps1xml",
                "PowerShellCore.format.ps1xml",
                "PowerShellTrace.format.ps1xml",
                "Registry.format.ps1xml",
                "WSMan.format.ps1xml"
            };

        /// <summary>
        /// Some common environment variables used in PS have different
        /// names in different OS platforms.
        /// </summary>
        internal static class CommonEnvVariableNames
        {
#if UNIX
            internal const string Home = "HOME";
#else
            internal const string Home = "USERPROFILE";
#endif
        }

        /// <summary>
        /// Remove the temporary directory created for the current process.
        /// </summary>
        internal static void RemoveTemporaryDirectory()
        {
            if (_tempDirectory == null)
            {
                return;
            }

            try
            {
                Directory.Delete(_tempDirectory, true);
            }
            catch
            {
                // ignore if there is a failure
            }

            _tempDirectory = null;
        }

        /// <summary>
        /// Get a temporary directory to use for the current process.
        /// </summary>
        internal static string GetTemporaryDirectory()
        {
            if (_tempDirectory != null)
            {
                return _tempDirectory;
            }

            _tempDirectory = PsUtils.GetTemporaryDirectory();
            return _tempDirectory;
        }

#if UNIX
        /// <summary>
        /// X Desktop Group configuration type enum.
        /// </summary>
        public enum XDG_Type
        {
            /// <summary> XDG_CONFIG_HOME/powershell </summary>
            CONFIG,
            /// <summary> XDG_CACHE_HOME/powershell </summary>
            CACHE,
            /// <summary> XDG_DATA_HOME/powershell </summary>
            DATA,
            /// <summary> XDG_DATA_HOME/powershell/Modules </summary>
            USER_MODULES,
            /// <summary> /usr/local/share/powershell/Modules </summary>
            SHARED_MODULES,
            /// <summary> XDG_CONFIG_HOME/powershell </summary>
            DEFAULT
        }

        /// <summary>
        /// Function for choosing directory location of PowerShell for profile loading.
        /// </summary>
        public static string SelectProductNameForDirectory(Platform.XDG_Type dirpath)
        {
            // TODO: XDG_DATA_DIRS implementation as per GitHub issue #1060

            string xdgconfighome = System.Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
            string xdgdatahome = System.Environment.GetEnvironmentVariable("XDG_DATA_HOME");
            string xdgcachehome = System.Environment.GetEnvironmentVariable("XDG_CACHE_HOME");
            string envHome = System.Environment.GetEnvironmentVariable(CommonEnvVariableNames.Home);
            if (envHome == null)
            {
                envHome = GetTemporaryDirectory();
            }

            string xdgConfigHomeDefault = Path.Combine(envHome, ".config", "powershell");
            string xdgDataHomeDefault = Path.Combine(envHome, ".local", "share", "powershell");
            string xdgModuleDefault = Path.Combine(xdgDataHomeDefault, "Modules");
            string xdgCacheDefault = Path.Combine(envHome, ".cache", "powershell");

            switch (dirpath)
            {
                case Platform.XDG_Type.CONFIG:
                    // the user has set XDG_CONFIG_HOME corresponding to profile path
                    if (string.IsNullOrEmpty(xdgconfighome))
                    {
                        // xdg values have not been set
                        return xdgConfigHomeDefault;
                    }

                    else
                    {
                        return Path.Combine(xdgconfighome, "powershell");
                    }

                case Platform.XDG_Type.DATA:
                    // the user has set XDG_DATA_HOME corresponding to module path
                    if (string.IsNullOrEmpty(xdgdatahome))
                    {
                        // create the xdg folder if needed
                        if (!Directory.Exists(xdgDataHomeDefault))
                        {
                            try
                            {
                                Directory.CreateDirectory(xdgDataHomeDefault);
                            }
                            catch (UnauthorizedAccessException)
                            {
                                // service accounts won't have permission to create user folder
                                return GetTemporaryDirectory();
                            }
                        }

                        return xdgDataHomeDefault;
                    }
                    else
                    {
                        return Path.Combine(xdgdatahome, "powershell");
                    }

                case Platform.XDG_Type.USER_MODULES:
                    // the user has set XDG_DATA_HOME corresponding to module path
                    if (string.IsNullOrEmpty(xdgdatahome))
                    {
                        // xdg values have not been set
                        if (!Directory.Exists(xdgModuleDefault)) // module folder not always guaranteed to exist
                        {
                            try
                            {
                                Directory.CreateDirectory(xdgModuleDefault);
                            }
                            catch (UnauthorizedAccessException)
                            {
                                // service accounts won't have permission to create user folder
                                return GetTemporaryDirectory();
                            }
                        }

                        return xdgModuleDefault;
                    }
                    else
                    {
                        return Path.Combine(xdgdatahome, "powershell", "Modules");
                    }

                case Platform.XDG_Type.SHARED_MODULES:
                    return "/usr/local/share/powershell/Modules";

                case Platform.XDG_Type.CACHE:
                    // the user has set XDG_CACHE_HOME
                    if (string.IsNullOrEmpty(xdgcachehome))
                    {
                        // xdg values have not been set
                        if (!Directory.Exists(xdgCacheDefault)) // module folder not always guaranteed to exist
                        {
                            try
                            {
                                Directory.CreateDirectory(xdgCacheDefault);
                            }
                            catch (UnauthorizedAccessException)
                            {
                                // service accounts won't have permission to create user folder
                                return GetTemporaryDirectory();
                            }
                        }

                        return xdgCacheDefault;
                    }

                    else
                    {
                        if (!Directory.Exists(Path.Combine(xdgcachehome, "powershell")))
                        {
                            try
                            {
                                Directory.CreateDirectory(Path.Combine(xdgcachehome, "powershell"));
                            }
                            catch (UnauthorizedAccessException)
                            {
                                // service accounts won't have permission to create user folder
                                return GetTemporaryDirectory();
                            }
                        }

                        return Path.Combine(xdgcachehome, "powershell");
                    }

                case Platform.XDG_Type.DEFAULT:
                    // default for profile location
                    return xdgConfigHomeDefault;

                default:
                    // xdgConfigHomeDefault needs to be created in the edge case that we do not have the folder or it was deleted
                    // This folder is the default in the event of all other failures for data storage
                    if (!Directory.Exists(xdgConfigHomeDefault))
                    {
                        try
                        {
                            Directory.CreateDirectory(xdgConfigHomeDefault);
                        }
                        catch
                        {
                            Console.Error.WriteLine("Failed to create default data directory: " + xdgConfigHomeDefault);
                        }
                    }

                    return xdgConfigHomeDefault;
            }
        }
#endif

        /// <summary>
        /// The code is copied from the .NET implementation.
        /// </summary>
        internal static string GetFolderPath(System.Environment.SpecialFolder folder)
        {
            return InternalGetFolderPath(folder);
        }

        /// <summary>
        /// The API set 'api-ms-win-shell-shellfolders-l1-1-0.dll' was removed from NanoServer, so we cannot depend on 'SHGetFolderPathW'
        /// to get the special folder paths. Instead, we need to rely on the basic environment variables to get the special folder paths.
        /// </summary>
        /// <returns>
        /// The path to the specified system special folder, if that folder physically exists on your computer.
        /// Otherwise, an empty string (string.Empty).
        /// </returns>
        private static string InternalGetFolderPath(System.Environment.SpecialFolder folder)
        {
            string folderPath = null;
#if UNIX
            string envHome = System.Environment.GetEnvironmentVariable(Platform.CommonEnvVariableNames.Home);
            if (envHome == null)
            {
                envHome = Platform.GetTemporaryDirectory();
            }

            switch (folder)
            {
                case System.Environment.SpecialFolder.ProgramFiles:
                    folderPath = "/bin";
                    if (!System.IO.Directory.Exists(folderPath)) { folderPath = null; }

                    break;
                case System.Environment.SpecialFolder.ProgramFilesX86:
                    folderPath = "/usr/bin";
                    if (!System.IO.Directory.Exists(folderPath)) { folderPath = null; }

                    break;
                case System.Environment.SpecialFolder.System:
                case System.Environment.SpecialFolder.SystemX86:
                    folderPath = "/sbin";
                    if (!System.IO.Directory.Exists(folderPath)) { folderPath = null; }

                    break;
                case System.Environment.SpecialFolder.Personal:
                    folderPath = envHome;
                    break;
                case System.Environment.SpecialFolder.LocalApplicationData:
                    folderPath = System.IO.Path.Combine(envHome, ".config");
                    if (!System.IO.Directory.Exists(folderPath))
                    {
                        try
                        {
                            System.IO.Directory.CreateDirectory(folderPath);
                        }
                        catch (UnauthorizedAccessException)
                        {
                            // directory creation may fail if the account doesn't have filesystem permission such as some service accounts
                            folderPath = string.Empty;
                        }
                    }

                    break;
                default:
                    throw new NotSupportedException();
            }
#else
            folderPath = System.Environment.GetFolderPath(folder);
#endif
            return folderPath ?? string.Empty;
        }

        // Platform methods prefixed NonWindows are:
        // - non-windows by the definition of the IsWindows method above
        // - here, because porting to Linux and other operating systems
        //   should not move the original Windows code out of the module
        //   it belongs to, so this way the windows code can remain in it's
        //   original source file and only the non-windows code has been moved
        //   out here
        // - only to be used with the IsWindows feature query, and only if
        //   no other more specific feature query makes sense

        internal static bool NonWindowsIsHardLink(ref IntPtr handle)
        {
            return Unix.IsHardLink(ref handle);
        }

        internal static bool NonWindowsIsHardLink(FileSystemInfo fileInfo)
        {
            return Unix.IsHardLink(fileInfo);
        }

        internal static string NonWindowsInternalGetTarget(string path)
        {
            return Unix.NativeMethods.FollowSymLink(path);
        }

        internal static string NonWindowsGetUserFromPid(int path)
        {
            return Unix.NativeMethods.GetUserFromPid(path);
        }

        internal static string NonWindowsInternalGetLinkType(FileSystemInfo fileInfo)
        {
            if (fileInfo.Attributes.HasFlag(System.IO.FileAttributes.ReparsePoint))
            {
                return "SymbolicLink";
            }

            if (NonWindowsIsHardLink(fileInfo))
            {
                return "HardLink";
            }

            return null;
        }

        internal static bool NonWindowsCreateSymbolicLink(string path, string target)
        {
            // Linux doesn't care if target is a directory or not
            return Unix.NativeMethods.CreateSymLink(path, target) == 0;
        }

        internal static bool NonWindowsCreateHardLink(string path, string strTargetPath)
        {
            return Unix.NativeMethods.CreateHardLink(path, strTargetPath) == 0;
        }

        internal static unsafe bool NonWindowsSetDate(DateTime dateToUse)
        {
            Unix.NativeMethods.UnixTm tm = Unix.NativeMethods.DateTimeToUnixTm(dateToUse);
            return Unix.NativeMethods.SetDate(&tm) == 0;
        }

        internal static bool NonWindowsIsSameFileSystemItem(string pathOne, string pathTwo)
        {
            return Unix.NativeMethods.IsSameFileSystemItem(pathOne, pathTwo);
        }

        internal static bool NonWindowsGetInodeData(string path, out System.ValueTuple<UInt64, UInt64> inodeData)
        {
            UInt64 device = 0UL;
            UInt64 inode = 0UL;
            var result = Unix.NativeMethods.GetInodeData(path, out device, out inode);

            inodeData = (device, inode);
            return result == 0;
        }

        internal static bool NonWindowsIsExecutable(string path)
        {
            return Unix.NativeMethods.IsExecutable(path);
        }

        internal static uint NonWindowsGetThreadId()
        {
            return Unix.NativeMethods.GetCurrentThreadId();
        }

        internal static int NonWindowsGetProcessParentPid(int pid)
        {
            return IsMacOS ? Unix.NativeMethods.GetPPid(pid) : Unix.GetProcFSParentPid(pid);
        }

        // Unix specific implementations of required functionality
        //
        // Please note that `Win32Exception(Marshal.GetLastWin32Error())`
        // works *correctly* on Linux in that it creates an exception with
        // the string perror would give you for the last set value of errno.
        // No manual mapping is required. .NET Core maps the Linux errno
        // to a PAL value and calls strerror_r underneath to generate the message.
        internal static class Unix
        {
            // This is a helper that attempts to map errno into a PowerShell ErrorCategory
            internal static ErrorCategory GetErrorCategory(int errno)
            {
                return (ErrorCategory)Unix.NativeMethods.GetErrorCategory(errno);
            }

            public static bool IsHardLink(ref IntPtr handle)
            {
                // TODO:PSL implement using fstat to query inode refcount to see if it is a hard link
                return false;
            }

            public static ushort GetUmask()
            {
                ushort mask = Unix.NativeMethods.umask(0);
                Unix.NativeMethods.umask(mask);
                return mask;
            }

            public static int GetPipeBufSize()
            {
                return (int)Unix.NativeMethods.PIPE_BUF();
            }

            public static ushort SetUmask(ushort mask)
            {
                return Unix.NativeMethods.umask(mask);
            }

            public static bool IsHardLink(FileSystemInfo fs)
            {
                if (!fs.Exists || (fs.Attributes & FileAttributes.Directory) == FileAttributes.Directory)
                {
                    return false;
                }

                int count;
                string filePath = fs.FullName;
                int ret = NativeMethods.GetLinkCount(filePath, out count);
                if (ret == 0)
                {
                    return count > 1;
                }
                else
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }
            }

            public static int GetProcFSParentPid(int pid)
            {
                const int invalidPid = -1;
                // read /proc/<pid>/stat
                // 4th column will contain the ppid, 92 in the example below
                // ex: 93 (bash) S 92 93 2 4294967295 ...

                var path = $"/proc/{pid}/stat";
                try
                {
                    var stat = System.IO.File.ReadAllText(path);
                    var parts = stat.Split(new[] { ' ' }, 5);
                    if (parts.Length < 5)
                    {
                        return invalidPid;
                    }

                    return Int32.Parse(parts[3]);
                }
                catch (Exception)
                {
                    return invalidPid;
                }
            }

            internal static class NativeMethods
            {
                private const string psLib = "libpsl-native";

                // Ansi is a misnomer, it is hardcoded to UTF-8 on Linux and macOS

                // C bools are 1 byte and so must be marshaled as I1

                [DllImport(psLib, CharSet = CharSet.Ansi)]
                internal static extern int GetErrorCategory(int errno);

                [DllImport(psLib)]
                internal static extern int GetPPid(int pid);

                [DllImport(psLib, CharSet = CharSet.Ansi, SetLastError = true)]
                internal static extern int GetLinkCount([MarshalAs(UnmanagedType.LPStr)]string filePath, out int linkCount);

                [DllImport(psLib, CharSet = CharSet.Ansi, SetLastError = true)]
                [return: MarshalAs(UnmanagedType.I1)]
                internal static extern bool IsExecutable([MarshalAs(UnmanagedType.LPStr)]string filePath);

                [DllImport(psLib, CharSet = CharSet.Ansi)]
                internal static extern uint GetCurrentThreadId();

                // This is a struct tm from <time.h>
                [StructLayout(LayoutKind.Sequential)]
                internal unsafe struct UnixTm
                {
                    public int tm_sec;    /* Seconds (0-60) */
                    public int tm_min;    /* Minutes (0-59) */
                    public int tm_hour;   /* Hours (0-23) */
                    public int tm_mday;   /* Day of the month (1-31) */
                    public int tm_mon;    /* Month (0-11) */
                    public int tm_year;   /* Year - 1900 */
                    public int tm_wday;   /* Day of the week (0-6, Sunday = 0) */
                    public int tm_yday;   /* Day in the year (0-365, 1 Jan = 0) */
                    public int tm_isdst;  /* Daylight saving time */
                }

                internal static UnixTm DateTimeToUnixTm(DateTime date)
                {
                    UnixTm tm;
                    tm.tm_sec = date.Second;
                    tm.tm_min = date.Minute;
                    tm.tm_hour = date.Hour;
                    tm.tm_mday = date.Day;
                    tm.tm_mon = date.Month - 1; // needs to be 0 indexed
                    tm.tm_year = date.Year - 1900; // years since 1900
                    tm.tm_wday = 0; // this is ignored by mktime
                    tm.tm_yday = 0; // this is also ignored
                    tm.tm_isdst = date.IsDaylightSavingTime() ? 1 : 0;
                    return tm;
                }

                internal static rlimit ResourceLimitInfoTorlimit(ResourceLimitInfo rli)
                {
                    rlimit rl;
                    rl.rlim_cur = rli.Current;
                    rl.rlim_max = rli.Maximum;
                    return rl;
                }

                internal static unsafe ResourceLimitInfo rlimitToResourceLimitInfo(int command, rlimit rl)
                {
                    ResourceLimitInfo rli = new ResourceLimitInfo();
                    rli.Current = rl.rlim_cur;
                    rli.Maximum = rl.rlim_max;
                    rli.Resource = (ResourceForUlimit)command;
                    return rli;
                }

                [DllImport(psLib, CharSet = CharSet.Ansi, SetLastError = true)]
                internal static extern unsafe int SetDate(UnixTm* tm);

                [DllImport(psLib, CharSet = CharSet.Ansi, SetLastError = true)]
                internal static extern int CreateSymLink([MarshalAs(UnmanagedType.LPStr)]string filePath,
                                                         [MarshalAs(UnmanagedType.LPStr)]string target);

                [DllImport(psLib, CharSet = CharSet.Ansi, SetLastError = true)]
                internal static extern int CreateHardLink([MarshalAs(UnmanagedType.LPStr)]string filePath,
                                                          [MarshalAs(UnmanagedType.LPStr)]string target);

                [DllImport(psLib, CharSet = CharSet.Ansi, SetLastError = true)]
                [return: MarshalAs(UnmanagedType.LPStr)]
                internal static extern string FollowSymLink([MarshalAs(UnmanagedType.LPStr)]string filePath);

                [DllImport(psLib, CharSet = CharSet.Ansi, SetLastError = true)]
                [return: MarshalAs(UnmanagedType.LPStr)]
                internal static extern string GetUserFromPid(int pid);

                [DllImport(psLib, CharSet = CharSet.Ansi, SetLastError = true)]
                [return: MarshalAs(UnmanagedType.I1)]
                internal static extern bool IsSameFileSystemItem([MarshalAs(UnmanagedType.LPStr)]string filePathOne,
                                                                 [MarshalAs(UnmanagedType.LPStr)]string filePathTwo);

                [DllImport(psLib, CharSet = CharSet.Ansi, SetLastError = true)]
                internal static extern int GetInodeData([MarshalAs(UnmanagedType.LPStr)]string path,
                                                        out UInt64 device, out UInt64 inode);

                [StructLayout(LayoutKind.Sequential)]
                internal unsafe struct rlimit
                {
#if LINUX32BIT
                    public uint rlim_cur;
                    public uint rlim_max;
#else
                    public ulong rlim_cur;
                    public ulong rlim_max;
#endif
                }

                [DllImport("libc", CharSet = CharSet.Ansi, SetLastError = true)]
                internal static extern long setrlimit(int command, out rlimit limit);
                [DllImport("libc", CharSet = CharSet.Ansi, SetLastError = true)]
                internal static extern long getrlimit(int command, out rlimit limit);

                [DllImport("libc", CharSet = CharSet.Ansi, SetLastError = true)]
                internal static extern ushort umask (ushort mask);

                [DllImport("libc", CallingConvention = CallingConvention.Cdecl)]
                [return: MarshalAs(UnmanagedType.SysInt)]
                internal extern static IntPtr PIPE_BUF();
            }
        }
    }

#if UNIX
    /// <summary>a umask object with the 3 different presentations</summary>
    public class UmaskInfo
    {
        /// <summary>The traditional view</summary>
        public string Umask;
        /// <summary>The symbolic view</summary>
        public string Symbolic;
        /// <summary>As a decimal number</summary>
        public ushort AsDecimal;
        /// <summary>provide the default view</summary>
        public override string ToString()
        {
            return Umask;
        }

        /// <summary>constructor</summary>
        public UmaskInfo(ushort value)
        {
            string s = Convert.ToString(value, 8).PadLeft(4,'0');
            AsDecimal = value;
            Umask = s;
            Symbolic = ConvertToSymbolic(s);
        }
        private string ConvertToSymbolic(string s)
        {
            StringBuilder sb = new StringBuilder();
            char[] perms = s.ToCharArray();
            string[] permissions = new string[]{ "rwx", "rw", "rx", "r", "wx", "w", "x", "" };
            sb.Append("u=");
            int permVal = int.Parse(perms[1].ToString());
            sb.Append(permissions[permVal]);
            sb.Append(",g=");
            permVal = int.Parse(perms[2].ToString());
            sb.Append(permissions[permVal]);
            sb.Append(",o=");
            permVal = int.Parse(perms[3].ToString());
            sb.Append(permissions[permVal]);
            return sb.ToString();
        }
    }

    /// <summary>the Get-Umask cmdlet</summary>
    [Cmdlet("Get","Umask")]
    public class GetUmaskCommand : PSCmdlet
    {
        /// <summary>Emit the umask object</summary>
        protected override void EndProcessing()
        {
            var umask = Platform.Umask;
            WriteObject(new UmaskInfo(umask));
        }
    }

    /// <summary>the Get-Umask cmdlet</summary>
    [Cmdlet("Set","Umask", DefaultParameterSetName="Octal")]
    public class SetUmaskCommand : PSCmdlet
    {

        private readonly string SymbolicUsage = "no";
        private string[] _symbolic;
        /// <summary>Symbolic umask</summary>
        [Parameter(Mandatory=true,ParameterSetName="Symbolic")]
        [ValidateCount(1,3)]
        public string[] Symbolic {
            get { return _symbolic; }
            set {
                // Validate assignment here
                foreach ( string symbol in value ) {
                    if ( symbol.Length < 2 ) { throw new ArgumentException(SymbolicUsage); }
                    if ( ! ( symbol[0] == 'u' || symbol[0] == 'o' || symbol[0] == 'g')) { throw new ArgumentException(SymbolicUsage); }
                    if ( symbol[1] != '=' ) { throw new ArgumentException(SymbolicUsage); }
                    foreach ( char c in symbol.Substring(2).ToCharArray()) {
                        if ( ! (c == 'r' || c == 'w' || c == 'x') ) { throw new ArgumentException(SymbolicUsage); }
                    }
                }
                _symbolic = value;
            }
        }

        /// <summary>traditional umask view</summary>
        [Parameter(Mandatory=true,Position=0,ParameterSetName="Octal")]
        [ValidateLength(1,4)]
        [ValidatePattern("^[0-7]{1,4}$")]
        public string Umask { get; set; }
        /// <summary>Set the umask</summary>
        protected override void EndProcessing()
        {
            try {
                if ( String.Compare(this.ParameterSetName, "Symbolic") == 0 ) {
                    Umask = ConvertSymbolicUmaskToOctalUmask(Symbolic);
                }
                int umaskValue = Convert.ToInt16(Umask, 8);
                Platform.Umask = (ushort)umaskValue;
            }
            catch (Exception e) {
                ThrowTerminatingError(new ErrorRecord(e, "SetUmaskError", ErrorCategory.InvalidArgument, Umask));
            }
        }

        private string ConvertSymbolicUmaskToOctalUmask(string[]SymbolicUmask) {
            char []umask = new UmaskInfo(Platform.Umask).Umask.ToCharArray();
            int offset = 0;
            foreach ( string sUmask in SymbolicUmask ) {
                if (sUmask[0] == 'u' ) {
                    offset = 1;
                }
                else if ( sUmask[0] == 'g' ) {
                    offset = 2;
                }
                else if ( sUmask[0] == 'o' ) {
                    offset = 3;
                }
                byte val = 0;
                foreach ( char p in sUmask.Substring(2).ToCharArray()) {
                    switch (p) {
                        case 'r': val |= 4; break;
                        case 'w': val |= 2; break;
                        case 'x': val |= 1; break;
                        default: break;
                    }
                }
                int v = 7 - val;
                umask[offset] = Convert.ToChar(v.ToString());
            }
            return String.Join(null, umask);
        }
    }

    /// <summary>The Set-Ulimit cmdlet</summary>
    [Cmdlet("Set","Ulimit")]
    public class SetUlimitCommand : PSCmdlet
    {
        /// <summary>The resource to retrieve</summary>
        [Parameter(Position=0,Mandatory=true,ValueFromPipeline=true,ParameterSetName="ResourceInfo")]
        public Platform.ResourceLimitInfo ResourceInfo { get; set; }
        /// <summary>new setting</summary>
        [Parameter(Mandatory=true,ParameterSetName="Resource")]
        public Platform.ResourceForUlimit Resource { get; set; }

#if LINUX32BIT
        /// <summary>new 32bit value for current </summary>
        [Parameter(ParameterSetName="Resource")]
        public uint Current { get; set; }
        /// <summary>new 32bit value for maximum </summary>
        [Parameter(ParameterSetName="Resource")]
        public uint Maximum { get; set; }
#else
        /// <summary>new 64bit value for current </summary>
        [Parameter(ParameterSetName="Resource")]
        public ulong Current { get; set; }
        /// <summary>new 64bit value for maximum </summary>
        [Parameter(ParameterSetName="Resource")]
        public ulong Maximum { get; set; }
#endif

        /// <summary>Retrieve and return the resource value</summary>
        protected override void EndProcessing()
        {
            if ( ParameterSetName == "Resource" ) {
                Platform.ResourceLimitInfo rli = Platform.GetResourceLimit(Resource);
                ResourceInfo = new Platform.ResourceLimitInfo() {
                    Resource = Resource,
                    Current = Current != 0 ? Current : rli.Current,
                    Maximum = Maximum != 0 ? Maximum : rli.Maximum,
                };
            }
            try {
                Platform.SetResourceLimit(ResourceInfo);
            }
            catch (Exception e) {
                WriteError(new ErrorRecord(e, "Set-Ulimit", ErrorCategory.InvalidArgument, Resource));
            }
        }
    }

    /// <summary>The Get-Ulimit cmdlet</summary>
    [Cmdlet("Get","Ulimit",DefaultParameterSetName="Resource")]
    public class GetUlimitCommand : PSCmdlet
    {
        /// <summary>The resource to retrieve</summary>
        [Parameter(Position=0,Mandatory=true,ParameterSetName="All")]
        public SwitchParameter All { get; set; }

        /// <summary>The resource to retrieve</summary>
        [Parameter(Position=0,ParameterSetName="Resource")]
        public Platform.ResourceForUlimit[] Resource { get; set; } = { Platform.ResourceForUlimit.FileSize };

        /// <summary>Retrieve and return the resource value</summary>
        protected override void BeginProcessing()
        {
            if ( this.ParameterSetName == "All" ) {
                Resource = (Platform.ResourceForUlimit[])Enum.GetValues(typeof(Platform.ResourceForUlimit));
            }
        }
        /// <summary>Retrieve and return the resource value</summary>
        protected override void EndProcessing()
        {
            foreach ( Platform.ResourceForUlimit command in Resource) {
                WriteObject(Platform.GetResourceLimit(command));
            }
        }
    }

#endif
}
