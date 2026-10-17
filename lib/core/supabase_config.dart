/// CRX-Pulse — Supabase connection settings.
///
/// Fill these in from your Supabase dashboard:
///   Project Settings -> API -> Project URL        -> [url]
///   Project Settings -> API -> Project API keys    -> anon public -> [anonKey]
///
/// The anon key is safe to ship in the app — Row Level Security (the SQL
/// you ran in the dashboard) is what actually protects the data.
class SupabaseConfig {
  static const String url = 'https://qlrjplwxsgklawunuoey.supabase.co';
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFscmpwbHd4c2drbGF3dW51b2V5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE3MDUxMTQsImV4cCI6MjEwNzI4MTExNH0.BWiTxwr6kafN5EuyyEIsQZ0Ikd7QelARsJSMkNyVxh8';
}
