// lib/testability/testability_server.dart
// Lightweight localhost-only HTTP server for LLM-driven integration tests.
// Only runs in debug and profile builds — NEVER in release.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'screen_state_registry.dart';

class TestabilityServer {
  TestabilityServer._();

  static HttpServer? _server;
  static const int defaultPort = 8765;

  static Future<void> start({int port = defaultPort}) async {
    if (kReleaseMode) return;

    try {
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: true,
      );
      debugPrint('[Testability] Server started → http://127.0.0.1:$port');
      _server!.listen(
        _handleRequest,
        onError: (e) => debugPrint('[Testability] Server error: $e'),
      );
    } catch (e) {
      debugPrint('[Testability] Failed to start: $e');
    }
  }

  static Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  static Future<void> _handleRequest(HttpRequest req) async {
    final res = req.response;
    res.headers
      ..set('Content-Type', 'application/json')
      ..set('Access-Control-Allow-Origin', '*');

    try {
      if (req.method == 'GET' && req.uri.path == '/ping') {
        res.statusCode = HttpStatus.ok;
        res.write(jsonEncode({
          'status': 'ok',
          'mode': kProfileMode ? 'profile' : 'debug',
        }));
      } else if (req.method == 'GET' && req.uri.path == '/screen') {
        res.statusCode = HttpStatus.ok;
        res.write(ScreenStateRegistry.instance.current.toJsonString());
      } else {
        res.statusCode = HttpStatus.notFound;
        res.write(jsonEncode({'error': 'Available: GET /ping  GET /screen'}));
      }
    } catch (e) {
      res.statusCode = HttpStatus.internalServerError;
      res.write(jsonEncode({'error': e.toString()}));
    }

    await res.close();
  }
}
