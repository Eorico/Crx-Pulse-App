import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What went wrong talking to Supabase, in terms the user can act on.
///
/// This exists because the first cut of Test Components swallowed every
/// failure into one of two useless outcomes: a hardcoded "Can't reach
/// the cloud — check this phone's connection", or `catch (_) {}` and
/// silence. A missing table, a missing column, an RLS refusal and a
/// genuinely offline phone all looked identical — so when the console
/// showed nothing there was no way to tell which it was.
enum SupabaseFault {
  /// The table or column does not exist: `supabase_schema.sql` has not
  /// been run (or not re-run since the last change).
  schemaOutOfDate,

  /// Row Level Security refused it, or the device is not paired to this
  /// account.
  notPermitted,

  /// Not signed in.
  notSignedIn,

  /// The phone could not reach Supabase at all.
  offline,

  /// Reached it, got an error we do not specifically recognise.
  unknown,
}

/// A classified failure, with the message to show and the fix to offer.
class SupabaseDiagnosis {
  final SupabaseFault fault;

  /// One line naming what is wrong.
  final String summary;

  /// What the user should do about it, or null when there is nothing
  /// actionable.
  final String? fix;

  /// The underlying error text, for the detail line / logs.
  final String detail;

  const SupabaseDiagnosis({
    required this.fault,
    required this.summary,
    required this.detail,
    this.fix,
  });

  bool get isSchemaProblem => fault == SupabaseFault.schemaOutOfDate;

  /// Classify anything thrown by a Supabase call.
  ///
  /// [what] names the operation, e.g. "read the device log", so the
  /// summary reads as a sentence.
  factory SupabaseDiagnosis.from(Object error, {required String what}) {
    // ── Postgres / PostgREST ──
    if (error is PostgrestException) {
      final code = error.code ?? '';
      final message = error.message;
      final detail = code.isEmpty ? message : '$code: $message';

      // 42P01 undefined_table, 42703 undefined_column.
      // PGRST205/PGRST202: PostgREST cannot find the table/function in
      // its schema cache, which is what a brand-new table looks like
      // until the cache reloads.
      const schemaCodes = {'42P01', '42703', 'PGRST205', 'PGRST202'};
      final looksMissing = schemaCodes.contains(code) ||
          message.contains('does not exist') ||
          message.contains('could not find') ||
          message.contains('schema cache');

      if (looksMissing) {
        return SupabaseDiagnosis(
          fault: SupabaseFault.schemaOutOfDate,
          summary: 'The database is missing a table or column this screen '
              'needs, so it cannot $what.',
          fix: 'Open the Supabase dashboard → SQL Editor and run '
              'supabase/supabase_schema.sql. It is safe to re-run.',
          detail: detail,
        );
      }

      // 42501 insufficient_privilege; RLS refusals also surface as this
      // or as a "violates row-level security policy" message.
      if (code == '42501' || message.contains('row-level security')) {
        return SupabaseDiagnosis(
          fault: SupabaseFault.notPermitted,
          summary: 'The database refused the request, so it cannot $what.',
          fix: 'Check this device is paired to your account in the Setup '
              'tab, and that the policies in supabase_schema.sql have '
              'been applied.',
          detail: detail,
        );
      }

      return SupabaseDiagnosis(
        fault: SupabaseFault.unknown,
        summary: 'The database returned an error, so it cannot $what.',
        detail: detail,
      );
    }

    // ── auth ──
    if (error is AuthException) {
      return SupabaseDiagnosis(
        fault: SupabaseFault.notSignedIn,
        summary: 'Your session is no longer valid, so it cannot $what.',
        fix: 'Sign out and sign back in.',
        detail: error.message,
      );
    }

    // ── transport ──
    if (error is SocketException ||
        error is TimeoutException ||
        error is HttpException ||
        error.toString().contains('Failed host lookup') ||
        error.toString().contains('ClientException')) {
      return SupabaseDiagnosis(
        fault: SupabaseFault.offline,
        summary: "Can't reach Supabase, so it cannot $what.",
        fix: "Check this phone's internet connection.",
        detail: error.toString(),
      );
    }

    return SupabaseDiagnosis(
      fault: SupabaseFault.unknown,
      summary: 'Something went wrong, so it cannot $what.',
      detail: error.toString(),
    );
  }

  /// Summary plus fix, for a one-shot message like a snackbar.
  String get combined => fix == null ? summary : '$summary $fix';

  @override
  String toString() => '$fault: $summary ($detail)';
}
