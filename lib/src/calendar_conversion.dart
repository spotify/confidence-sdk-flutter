import 'dart:convert';

import 'package:flutter/services.dart';

import 'resolver.dart';
import 'snapshot.dart';

const _channel = MethodChannel(
  'confidence_openfeature_provider/legacy_calendar',
);

/// Only legacy calendar values cross the platform channel. Foundation decodes
/// its original DateComponents representation and applies the native SDK's
/// current-calendar/current-time-zone conversion at delivery time.
Future<Object?> eventWireValue(Object? value) async {
  final dates = <String>[];
  void collect(Object? value) {
    switch (value) {
      case CalendarDate():
        dates.add(jsonEncode(value.components));
      case Map<String, Object?>():
        value.values.forEach(collect);
      case List<Object?>():
        value.forEach(collect);
    }
  }

  collect(value);
  if (dates.isEmpty) return wireValue(value);
  try {
    final converted = await _channel.invokeListMethod<String>(
      'convertDates',
      dates,
    );
    if (converted == null || converted.length != dates.length) {
      throw const FormatException('Invalid calendar conversion response.');
    }
    var index = 0;
    Object? replace(Object? value) => switch (value) {
      CalendarDate() => converted[index++],
      Map<String, Object?>() => value.map(
        (key, child) => MapEntry(key, replace(child)),
      ),
      List<Object?>() => value.map(replace).toList(),
      _ => wireValue(value),
    };
    return replace(value);
  } on PlatformException {
    throw const FormatException('Legacy calendar conversion failed.');
  } on MissingPluginException {
    throw const FormatException('Legacy calendar conversion unavailable.');
  }
}
