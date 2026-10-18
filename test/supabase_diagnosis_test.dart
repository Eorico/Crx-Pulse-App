import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crx_pulse/core/supabase_diagnosis.dart';

/// The Test Components console showed nothing and gave no clue why,
/// because every failure was collapsed into one hardcoded "Can't reach
/// the cloud" message or swallowed by `catch (_) {}`. These assert that
/// the four failures that actually happen are told apart, since that
/// distinction is the whole fix.
void main() {
  SupabaseDiagnosis diag(Object e) =>
      SupabaseDiagnosis.from(e, what: 'read the device log');

  group('schema not applied — the most likely cause', () {
    test('undefined_table (42P01) is reported as a schema problem', () {
      final d = diag(const PostgrestException(
        message: 'relation "public.device_logs" does not exist',
        code: '42P01',
      ));

      expect(d.fault, SupabaseFault.schemaOutOfDate);
      expect(d.isSchemaProblem, isTrue);
      expect(d.fix, contains('supabase_schema.sql'));
      // The raw error must survive into the detail line, so a report
      // says which table rather than just "it broke".
      expect(d.detail, contains('device_logs'));
    });

    test('undefined_column (42703) — the commands.value case', () {
      // This is what you get from running an older schema: the table
      // exists, but `value` does not, so log_stream inserts fail.
      final d = diag(const PostgrestException(
        message: 'column "value" of relation "commands" does not exist',
        code: '42703',
      ));

      expect(d.fault, SupabaseFault.schemaOutOfDate);
      expect(d.fix, contains('supabase_schema.sql'));
    });

    test("PostgREST's schema-cache miss on a brand-new table", () {
      final d = diag(const PostgrestException(
        message: "Could not find the table 'public.device_logs' in the schema cache",
        code: 'PGRST205',
      ));

      expect(d.fault, SupabaseFault.schemaOutOfDate);
    });
  });

  test('RLS refusal is NOT mistaken for a schema problem', () {
    final d = diag(const PostgrestException(
      message: 'new row violates row-level security policy for table "commands"',
      code: '42501',
    ));

    expect(d.fault, SupabaseFault.notPermitted);
    expect(d.isSchemaProblem, isFalse);
    expect(d.fix, contains('paired'));
  });

  group('transport failures are the only ones called "offline"', () {
    test('SocketException', () {
      expect(diag(const SocketException('no route')).fault, SupabaseFault.offline);
    });

    test('TimeoutException', () {
      expect(diag(TimeoutException('slow')).fault, SupabaseFault.offline);
    });

    test('failed host lookup', () {
      expect(diag('Failed host lookup: supabase.co').fault, SupabaseFault.offline);
    });
  });

  test('expired session is distinguishable from a refusal', () {
    final d = diag(const AuthException('JWT expired'));
    expect(d.fault, SupabaseFault.notSignedIn);
    expect(d.fix, contains('Sign out'));
  });

  test('an unrecognised database error stays unknown, not mislabelled', () {
    final d = diag(const PostgrestException(
      message: 'deadlock detected',
      code: '40P01',
    ));

    expect(d.fault, SupabaseFault.unknown);
    expect(d.isSchemaProblem, isFalse);
    // Still actionable: the real text is preserved.
    expect(d.detail, contains('deadlock'));
  });

  test('summary names the operation, so the message reads as a sentence', () {
    final d = SupabaseDiagnosis.from(
      const PostgrestException(message: 'x does not exist', code: '42P01'),
      what: 'send the command',
    );
    expect(d.summary, contains('send the command'));
  });

  test('combined joins summary and fix for one-shot messages', () {
    final d = diag(const PostgrestException(
      message: 'relation does not exist',
      code: '42P01',
    ));
    expect(d.combined, startsWith(d.summary));
    expect(d.combined, contains(d.fix!));
  });

  test('every fault maps to a non-empty, user-facing summary', () {
    // Guards against a new SupabaseFault being added without a message.
    for (final e in <Object>[
      const PostgrestException(message: 'does not exist', code: '42P01'),
      const PostgrestException(message: 'row-level security', code: '42501'),
      const AuthException('nope'),
      const SocketException('nope'),
      'something else entirely',
    ]) {
      final d = diag(e);
      expect(d.summary, isNotEmpty);
      expect(d.detail, isNotEmpty);
    }
  });
}
