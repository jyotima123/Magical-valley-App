import 'package:amplitude_flutter/amplitude.dart';
import 'package:amplitude_flutter/configuration.dart';
import 'package:amplitude_flutter/events/base_event.dart';
import 'package:amplitude_flutter/events/identify.dart';
import 'package:logging/logging.dart';

class AmplitudeService {
  AmplitudeService._();
  static final AmplitudeService instance = AmplitudeService._();

  static const _apiKey = '72b33fa71f39283c4728ccbca72ca4b1';

  late final Amplitude _amplitude;
  final _log = Logger('AmplitudeService');
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _amplitude = Amplitude(Configuration(apiKey: _apiKey));
    await _amplitude.isBuilt;
    _initialized = true;
    _log.info('Amplitude initialized');
  }

  Future<void> setUserId(String? userId) async {
    if (!_initialized) return;
    await _amplitude.setUserId(userId);
  }

  Future<void> setUserProperties(Map<String, dynamic> properties) async {
    if (!_initialized) return;
    final identify = Identify();
    properties.forEach((key, value) {
      identify.set(key, value);
    });
    await _amplitude.identify(identify);
  }

  Future<void> logEvent(
    String eventType, {
    Map<String, dynamic>? eventProperties,
  }) async {
    if (!_initialized) return;
    await _amplitude.track(
      BaseEvent(eventType, eventProperties: eventProperties),
    );
    _log.fine('Amplitude event: $eventType $eventProperties');
  }

  Future<void> reset() async {
    if (!_initialized) return;
    await _amplitude.reset();
  }
}
