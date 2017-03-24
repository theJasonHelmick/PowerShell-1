#if CORECLR
using System;
using Microsoft.ApplicationInsights;
using Microsoft.ApplicationInsights.DataContracts;
using Microsoft.ApplicationInsights.Extensibility;
using System.Management.Automation;
using System.Security.Cryptography;
using System.Collections.Generic;
using System.Reflection;
using System.IO;
using Environment = System.Management.Automation.Environment;

namespace Microsoft.PowerShell
{
    /// <summary>
    /// send telemetry for console host startup
    /// We're not using the current TelemetryAPI objects because it is
    /// assuming a ETW approach and that is not available x-plat
    /// </summary>
    public class ApplicationInsightsTelemetry
    {
        // Telemetry client should be reused if we start sending more telemetry
        private static TelemetryClient telemetryClient = null;

        // This is set to be sure that the telemetry is quickly delivered
        // TODO: This should be removed when we get closer to production
        private static bool developerMode = true;

        // PSCoreInsight2 telemetry key
        private const string psCoreTelemetryKey = "ee4b2115-d347-47b0-adb6-b19c2c763808";

        // Create a hash of the System.Management assembly;
        private static string GetSmaHash()
        {
            string hash;
            try {
                var csp = SHA256.Create();
                string path = typeof(PSObject).GetTypeInfo().Assembly.Location;
                byte[] smaBytes = File.ReadAllBytes(path);
                byte[] smaCksum = csp.ComputeHash(smaBytes);
                hash = BitConverter.ToString(smaCksum).Replace("-","");
            }
            catch {
                hash = "unknown";
            }

            return hash;
        }

        /// <summary>
        /// Send the telemetry
        ///
        /// <param name="eventName">
        /// The name of the event captured by ApplicationInsights
        /// </param>
        ///
        /// <param name="payload">
        /// This represents the data that we want to track
        /// it is the customDimensions column in the ApplicationInsights datatable
        /// </param>
        ///
        /// </summary>
        private static void SendTelemetry(string eventName, Dictionary<string,string>payload)
        {
            if ( string.IsNullOrEmpty(eventName) )
            {
                throw new ArgumentNullException("eventName");
            }

            string shouldSendTelemetry = Environment.GetEnvironmentVariable("NOPSCORETELEMETRY");
            // if NOPSCORETELEMETRY is true, then don't send telemetry
            // This is temporary until we have RFC0015-PowerShell-StartupConfig settled.
            // https://github.com/PowerShell/PowerShell-RFC/blob/master/1-Draft/RFC0015-PowerShell-StartupConfig.md
            // this is an environment variable which would need to be set before powershell is started
            if ( ! String.IsNullOrEmpty(shouldSendTelemetry) && shouldSendTelemetry.Equals("true",StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            TelemetryConfiguration.Active.InstrumentationKey = psCoreTelemetryKey;
            TelemetryConfiguration.Active.TelemetryChannel.DeveloperMode = developerMode;
            if ( telemetryClient == null )
            {
                telemetryClient = new TelemetryClient();
            }

            telemetryClient.TrackEvent(eventName, payload, null);
        }

        /// <summary>
        /// Create the startup payload and send it up
        /// </summary>
        public static void SendPSCoreStartupTelemetry()
        {
            var properties = new Dictionary<string, string>();
            properties.Add("SMAHash", GetSmaHash());
            properties.Add("GitCommitID", PSVersionInfo.GitCommitId);
            string OSVersion;
            try {
                OSVersion = Environment.OSVersion.VersionString;
            }
            catch {
                OSVersion = "unknown";
            }
            properties.Add("OSVersionInfo", OSVersion);
            SendTelemetry("PSCoreStartup", properties);
        }
    }
}
#endif
