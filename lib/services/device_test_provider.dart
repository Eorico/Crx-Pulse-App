import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/firmware_spec.dart';
import '../core/supabase_diagnosis.dart';
import 'offline_device_link.dart';

/// Drives the feeder servo and the DC rotator directly, for the Test
/// Components screen.
///
/// Same transport as everything else: a row in `commands`, which the
/// ESP32 picks up on its next poll (~5 s). There is no faster path —
/// the phone has no direct link to the device — so the UI has to show
/// that a command is queued rather than pretending it is instant.
///
/// The firmware bounds both actuators itself: a test-opened servo
/// force-closes after [FirmwareSpec.servoTestAutoClose] and a
/// test-driven motor stops after [FirmwareSpec.motorTestTimeout]. That
/// is deliberate, and not something this class can turn off — an open
/// feeder door keeps dropping feed, and neither should be left running
/// because somebody closed the app.
class DeviceTestProvider extends ChangeNotifier {
  final SupabaseClient _sb = Supabase.instance.client;
  final OfflineDeviceLink? _deviceLink;

  DeviceTestProvider({OfflineDeviceLink? deviceLink})
      : _deviceLink = deviceLink;

  /// The last command sent, for the UI to echo back.
  String? lastAction;
  bool sending = false;

  /// Non-null when the last command failed. Carries the real reason and
  /// the fix — a generic "Could not send the command" made a missing
  /// `commands.value` column (i.e. the schema not being re-run) look
  /// like a mystery.
  SupabaseDiagnosis? diagnosis;

  String? get errorMessage => diagnosis?.combined;

  /// Rotator PWM the user has dialled in. Not the device's actual
  /// speed — that is only known from the log or the next reading.
  int motorPwm = 0;

  void setMotorPwm(int pwm) {
    motorPwm = pwm;
    notifyListeners();
  }

  Future<bool> openServo(String deviceId) =>
      _send(deviceId, DeviceCommand.servoOpen,
          label: 'Servo open (${FirmwareSpec.servoOpenAngle}°)');

  Future<bool> closeServo(String deviceId) =>
      _send(deviceId, DeviceCommand.servoClose,
          label: 'Servo close (${FirmwareSpec.servoClosedAngle}°)');

  /// Run the rotator at the currently selected speed. 0 stops it.
  Future<bool> runMotor(String deviceId) {
    final speed = FirmwareSpec.rotatorSpeedForPwm(motorPwm);
    return _send(deviceId, DeviceCommand.motorTest,
        value: motorPwm,
        label: motorPwm == 0
            ? 'Rotator stop'
            : 'Rotator ${speed.label} (PWM $motorPwm)');
  }

  Future<bool> stopMotor(String deviceId) {
    motorPwm = 0;
    return _send(deviceId, DeviceCommand.motorTest,
        value: 0, label: 'Rotator stop');
  }

  Future<bool> _send(String deviceId, String type,
      {int? value, required String label}) async {
    // While the only link is the board's own AP, a `commands` row would
    // never be picked up: the firmware only polls Supabase when it has a
    // route out. Send straight to the AP instead.
    if (_deviceLink?.isOfflineDirect == true) {
      sending = true;
      diagnosis = null;
      notifyListeners();
      try {
        final ok = await _deviceLink!.command(type, value: value);
        if (ok) {
          lastAction = label;
        } else {
          diagnosis = const SupabaseDiagnosis(
            fault: SupabaseFault.unknown,
            summary: 'The device did not acknowledge the command.',
            fix: 'Stay within range of the device WiFi and try again.',
            detail: 'POST /api/command failed',
          );
        }
        return ok;
      } finally {
        sending = false;
        notifyListeners();
      }
    }

    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      diagnosis = const SupabaseDiagnosis(
        fault: SupabaseFault.notSignedIn,
        summary: 'Not signed in, so the command cannot be sent.',
        fix: 'Sign out and sign back in.',
        detail: 'currentUser == null',
      );
      notifyListeners();
      return false;
    }

    sending = true;
    diagnosis = null;
    notifyListeners();

    try {
      await _sb.from('commands').insert({
        'device_id': deviceId,
        'user_id': uid,
        'type': type,
        if (value != null) 'value': value,
        'handled': false,
      });
      lastAction = label;
      return true;
    } catch (e) {
      diagnosis = SupabaseDiagnosis.from(e, what: 'send the command');
      return false;
    } finally {
      sending = false;
      notifyListeners();
    }
  }
}
