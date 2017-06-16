/********************************************************************++
Copyright (c) Microsoft Corporation.  All rights reserved.
--********************************************************************/

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Management.Automation;

namespace Microsoft.PowerShell
{
    /// <summary>
    /// The list of available file encodings
    /// </summary>
    public enum FileEncoding 
    {
        /// <summary>
        /// No encoding, or unset.
        /// </summary>
        Unknown,

        /// <summary>
        /// Unicode encoding.
        /// </summary>
        String,

        /// <summary>
        /// Unicode encoding.
        /// </summary>
        Unicode,

        /// <summary>
        /// Byte encoding.
        /// </summary>
        Byte,

        /// <summary>
        /// Big Endian Unicode encoding.
        /// </summary>
        BigEndianUnicode,

        /// <summary>
        /// Backward compatibility - UTF8 encoding without BOM
        /// </summary>
        UTF8,

        /// <summary>
        /// UTF8 encoding which includes BOM.
        /// </summary>
        UTF8BOM,

        /// <summary>
        /// UTF8 encoding without BOM.
        /// </summary>
        UTF8NoBOM,

        /// <summary>
        /// UTF7 encoding.
        /// </summary>
        UTF7,

        /// <summary>
        /// UTF32 encoding.
        /// </summary>
        UTF32,

        /// <summary>
        /// ASCII encoding.
        /// </summary>
        Ascii,

        /// <summary>
        /// Default encoding.
        /// </summary>
        Default,

        /// <summary>
        /// OEM encoding.
        /// </summary>
        Oem,

        /// <summary>
        /// Big Endian UTF32 encoding.
        /// </summary>
        BigEndianUTF32,

        /// <summary>
        /// Windows legacy encoding. This requires a cmdlet object to resolve.
        /// </summary>
        WindowsLegacy,
    }

    /// <summary>
    /// the helper class for determining encodings for PowerShell
    /// </summary>
    public static class PowerShellEncoding
    {
        /// <summary>
        /// translate a FileEncoding to an actual System.Text.Encoding
        /// <param name="TextEncoding">The enum value</param>
        /// </summary>
        public static Encoding GetEncoding(FileEncoding TextEncoding)
        {
            System.Text.Encoding result = ClrFacade.GetDefaultEncoding();;
            switch ( TextEncoding ) 
            {
                case FileEncoding.String:
                    result = Encoding.Unicode;
                    break;

                case FileEncoding.Unicode:
                    result = Encoding.Unicode;
                    break;

                case FileEncoding.BigEndianUnicode:
                    result = Encoding.BigEndianUnicode;
                    break;

                case FileEncoding.UTF8BOM:
                    result = Encoding.UTF8; // The default UTF8 encoder includes the BOM
                    break;

                case FileEncoding.Byte:
                    result = Encoding.Unicode;
                    break;

                case FileEncoding.UTF8:
                case FileEncoding.UTF8NoBOM:
                    result = new UTF8Encoding(false);
                    break;

                case FileEncoding.UTF7:
                    result = Encoding.UTF7;
                    break;

                case FileEncoding.UTF32:
                    result = Encoding.UTF32;
                    break;

                case FileEncoding.BigEndianUTF32:
                    result = Encoding.BigEndianUnicode;
                    break;

                case FileEncoding.Ascii:
                    result = Encoding.ASCII;
                    break;

                case FileEncoding.Default:
                    result = ClrFacade.GetDefaultEncoding();
                    break;

                case FileEncoding.Oem:
                    result = ClrFacade.GetOEMEncoding();
                    break;

                default:
                    break;
            }

            return result;
        } 

        // the way the encoding is implemented in PowerShell 5 and earlier
        // if the user sets the default encoding to WindowsLegacy, we will
        // be able to encode for that
        internal static Dictionary<String, Encoding> legacyEncodingMap =
            new Dictionary<string, Encoding>()
            {
                { "microsoft.powershell.commands.addcontentcommand", Encoding.ASCII },
                { "microsoft.powershell.commands.exportclixmlcommand", Encoding.Unicode },
                { "microsoft.powershell.commands.exportcsvcommand", Encoding.ASCII },
                { "microsoft.powershell.commands.exportpssessioncommand", Encoding.UTF8 }, // with BOM
                { "microsoft.powershell.commands.formathex", Encoding.ASCII },
                { "microsoft.powershell.commands.newmodulemanifiest", Encoding.Unicode },
                { "microsoft.powershell.commands.getcontentcommand", Encoding.ASCII },
                { "microsoft.powershell.commands.importcsvcommand", Encoding.ASCII },
                { "microsoft.powershell.commands.outfilecommand", Encoding.Unicode }, // This includes redirection
                { "microsoft.powershell.commands.setcontentcommand", Encoding.ASCII },
                { "microsoft.powershell.getfencodingcommand", Encoding.UTF32 },
            };

        internal static Encoding GetWindowsLegacyCmdletEncoding(Cmdlet c)
        {
            if ( c != null ) {
                string key = c.GetType().FullName.ToLower(CultureInfo.InvariantCulture);
                if ( legacyEncodingMap.ContainsKey(key)){
                    return legacyEncodingMap[key];
                }
            }
            return Encoding.Default;
        }

        /// <summary>
        /// Retrieve the encoding based on the Cmdlet and the Encoding 
        /// <param name="cmdlet">The cmdlet of interest</param>
        /// <param name="encoding">The Encoding parameter value</param>
        /// </summary>
        public static Encoding GetEncoding(Cmdlet cmdlet, FileEncoding encoding)
        {
            Encoding resolvedEncoding = ClrFacade.GetDefaultEncoding();
            FileEncoding encodingPreference = FileEncoding.Unknown;
            bool preferenceSetAndValid = false;


            // An encoding has been specified as a parameter (or the explicit parameter value is "Unknown")
            if ( encoding != FileEncoding.Unknown )
            {
                // If the encoding has been set to WindowsLegacy, we need to look up the actual encoding
                if ( encoding == FileEncoding.WindowsLegacy )
                {
                    resolvedEncoding = GetWindowsLegacyCmdletEncoding(cmdlet);
                }
                else
                {
                    resolvedEncoding = GetEncoding(encoding);
                }
            }
            else
            {
                // the parameter is not specifically set
                // Check the preference variable
                object tmp = cmdlet.Context.SessionState.PSVariable.GetValue("PSDefaultFileEncoding");
                // It doesn't matter if this fails
                LanguagePrimitives.TryConvertTo<FileEncoding>(tmp, out encodingPreference);
                preferenceSetAndValid = encodingPreference != FileEncoding.Unknown; // If set to unknown, we accept that it is unset
                // If the encoding preference has been set to WindowsLegacy, we need to look up the actual encoding
                if ( encodingPreference == FileEncoding.WindowsLegacy ) 
                {
                    resolvedEncoding = GetWindowsLegacyCmdletEncoding(cmdlet);
                }
                else if ( encodingPreference != FileEncoding.Unknown )
                {
                    resolvedEncoding = GetEncoding(encodingPreference);
                }
                // the final else would be set the encoding to ClrFacade.GetDefaultEncoding()
                // which was handled above
            }

            return resolvedEncoding; // GetEncoding(FileEncoding.UTF8NoBOM);
        }

        // [System.Text.Encoding]::GetEncodings() | ? { $_.GetEncoding().GetPreamble() } |
        //     Add-Member ScriptProperty Preamble { $this.GetEncoding().GetPreamble() -join "-" } -PassThru |
        //     Format-Table -Auto
        internal static Dictionary<String, FileEncoding> encodingMap =
            new Dictionary<string, FileEncoding>()
            {
                { "255-254", FileEncoding.Unicode },
                { "254-255", FileEncoding.BigEndianUnicode },
                { "255-254-0-0", FileEncoding.UTF32 },
                { "0-0-254-255", FileEncoding.BigEndianUTF32 },
                { "239-187-191", FileEncoding.UTF8 },
            };

        internal static char[] nonPrintableCharacters = {
            (char) 0, (char) 1, (char) 2, (char) 3, (char) 4, (char) 5, (char) 6, (char) 7, (char) 8,
            (char) 11, (char) 12, (char) 14, (char) 15, (char) 16, (char) 17, (char) 18, (char) 19, (char) 20,
            (char) 21, (char) 22, (char) 23, (char) 24, (char) 25, (char) 26, (char) 28, (char) 29, (char) 30,
            (char) 31, (char) 127, (char) 129, (char) 141, (char) 143, (char) 144, (char) 157 };

        // take a look at the file contents and guess at the best encoding
        // 
        internal static FileEncoding GetEncoding(string path)
        {
            if (!File.Exists(path))
            {
                return FileEncoding.Default;
            }

            byte[] initialBytes = new byte[100];
            int bytesRead = 0;

            try
            {
                using (FileStream stream = System.IO.File.OpenRead(path))
                {
                    using (BinaryReader reader = new BinaryReader(stream))
                    {
                        bytesRead = reader.Read(initialBytes, 0, 100);
                    }
                }
            }
            catch (IOException)
            {
                return FileEncoding.Default;
            }

            // Test for four-byte preambles
            string preamble = null;
            FileEncoding foundEncoding = FileEncoding.Default;

            if (bytesRead > 3)
            {
                preamble = String.Join("-", initialBytes[0], initialBytes[1], initialBytes[2], initialBytes[3]);

                if (encodingMap.TryGetValue(preamble, out foundEncoding))
                {
                    return foundEncoding;
                }
            }

            // Test for three-byte preambles
            if (bytesRead > 2)
            {
                preamble = String.Join("-", initialBytes[0], initialBytes[1], initialBytes[2]);
                if (encodingMap.TryGetValue(preamble, out foundEncoding))
                {
                    return foundEncoding;
                }
            }

            // Test for two-byte preambles
            if (bytesRead > 1)
            {
                preamble = String.Join("-", initialBytes[0], initialBytes[1]);
                if (encodingMap.TryGetValue(preamble, out foundEncoding))
                {
                    return foundEncoding;
                }
            }

            // Check for binary
            string initialBytesAsAscii = System.Text.Encoding.ASCII.GetString(initialBytes, 0, bytesRead);
            if (initialBytesAsAscii.IndexOfAny(nonPrintableCharacters) >= 0)
            {
                return FileEncoding.Byte;
            }

            // we couldn't determine anything from direct examination,
            // return UTF8 without a BOM which should be good for both Windows and Non-Windows
            return FileEncoding.UTF8NoBOM;
        }
    }

    /// <summary>
    /// testcmdlet
    /// </summary>
    [Cmdlet("get","fencoding")]
    public class getfencodingcommand : PSCmdlet
    {
        /// <summary>file encoding</summary>
        [Parameter]
        public FileEncoding MyEncoding;
        private StreamWriter _sw = null;
        private FileStream _fs;
        private FileInfo _readOnlyFileInfo = null;

        /// <summary>emit the encoding</summary>
        protected override void EndProcessing()
        {
            Encoding resolvedEncoding = PowerShellEncoding.GetEncoding(this, MyEncoding);
            PathUtils.MasterStreamOpen(
                this,
                "/tmp/test.txt",
                resolvedEncoding,
                false,
                false,
                true,
                false,
                out _fs,
                out _sw,
                out _readOnlyFileInfo,
                true);
            _sw.WriteLine("test");
            _sw.Flush();
            _sw.Close();
            _fs.Close();
            _fs.Dispose();
        }
    }
}

