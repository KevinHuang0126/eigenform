import Foundation

/// Connection details for the Supabase project. Fill in `projectURL` and
/// `anonKey` from the dashboard (Project Settings → API); until then the app
/// shows setup instructions instead of a sign-in form.
///
/// The anon key is safe to ship in the binary: it only grants what Row Level
/// Security and auth policies allow. Never put the service-role key here.
enum SupabaseConfig {
    static let projectURL = "https://xqmeujuulejzksdbmcai.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhxbWV1anV1bGVqemtzZGJtY2FpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM4ODI5MjksImV4cCI6MjA5OTQ1ODkyOX0.cxsWUjGZ1UYHtqa160D44wPPF_nRABuXwBb0ZUdouHM"

    /// Where Supabase redirects after OAuth and email links. Must appear in
    /// the dashboard's allowed redirect URLs (see docs/AUTH_SETUP.md).
    static let redirectURL = URL(string: "eigenform://auth-callback")!

    /// Recovery links carry a marker so the app knows to ask for a new
    /// password after the session lands, since the PKCE callback itself looks
    /// identical to any other sign-in.
    static let recoveryRedirectURL = URL(string: "eigenform://auth-callback?flow=recovery")!

    static var isConfigured: Bool {
        !projectURL.contains("YOUR-PROJECT-REF") && !anonKey.contains("YOUR-ANON-KEY")
    }
}
