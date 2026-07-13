import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../config/app_secrets.dart';
import '../models/mushroom_id_result.dart';

class OnlineIdentificationLocation {
  final String? country;
  final String? region;
  final double? latitude;
  final double? longitude;

  const OnlineIdentificationLocation({
    this.country,
    this.region,
    this.latitude,
    this.longitude,
  });

  Map<String, dynamic> toJson() {
    return {
      'country': country,
      'region': region,
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}

class OnlineIdentificationException implements Exception {
  final String code;
  final String message;

  const OnlineIdentificationException(this.code, this.message);

  @override
  String toString() => message;
}

class OnlineIdentificationService {
  OnlineIdentificationService({
    FirebaseAuth? firebaseAuth,
    FirebaseApp? firebaseApp,
    HttpClient? httpClient,
    String? mushroomIdApiKey,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _firebaseApp = firebaseApp ?? Firebase.app(),
        _httpClient = httpClient,
        _mushroomIdApiKey = mushroomIdApiKey;

  static final OnlineIdentificationService instance =
      OnlineIdentificationService();

  static const int maxImageBytes = 5 * 1024 * 1024;
  static const String _functionRegion = String.fromEnvironment(
    'MUSHROOM_ID_FUNCTION_REGION',
    defaultValue: 'australia-southeast1',
  );
  static const String _functionName = 'identifyMushroomOnline';
  static const String _kindwiseHost = 'mushroom.kindwise.com';
  static const String _kindwisePath = '/api/v1/identification';
  static const String _kindwiseDetails =
      'common_names,url,description,edibility,toxicity,look_alikes,taxonomy,rank';

  final FirebaseAuth _firebaseAuth;
  final FirebaseApp _firebaseApp;
  final HttpClient? _httpClient;
  final String? _mushroomIdApiKey;

  Future<MushroomIdResult> identifyPhoto({
    required String photoPath,
    OnlineIdentificationLocation? location,
  }) async {
    _debugLog('Online identification started');
    _debugLog('invocation type: http');
    _debugLog('function name: $_functionName');
    _debugLog('function region: $_functionRegion');
    final file = File(photoPath);
    final exists = await file.exists();
    _debugLog('image file exists: $exists');
    if (!exists) {
      throw const OnlineIdentificationException(
        'photo-missing',
        'Selected photo is no longer available.',
      );
    }
    final length = await file.length();
    _debugLog('image bytes length: $length');
    if (length <= 0) {
      throw const OnlineIdentificationException(
        'photo-empty',
        'Selected photo is empty.',
      );
    }
    if (length > maxImageBytes) {
      throw const OnlineIdentificationException(
        'image-too-large',
        'Image is too large for online identification. Choose a smaller photo.',
      );
    }

    final bytes = await file.readAsBytes();
    final imageBase64 = base64Encode(bytes);
    _debugLog('imageBase64 length: ${imageBase64.length}');
    final directApiKey =
        (_mushroomIdApiKey ?? AppSecrets.mushroomIdApiKey)?.trim();
    try {
      if (directApiKey != null && directApiKey.isNotEmpty) {
        _debugLog('direct Kindwise request selected');
        return await _identifyWithKindwise(
          imageBase64: imageBase64,
          apiKey: directApiKey,
        );
      }

      final user = _firebaseAuth.currentUser;
      if (user == null) {
        throw const OnlineIdentificationException(
          'auth-required',
          'Sign in before using online identification.',
        );
      }

      final token = await user.getIdToken();
      if (token == null || token.trim().isEmpty) {
        throw const OnlineIdentificationException(
          'auth-required',
          'Could not verify your sign-in for online identification.',
        );
      }

      final body = jsonEncode({
        'imageBase64': imageBase64,
        'location': location?.toJson(),
      });
      final client = _httpClient ?? HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      _debugLog('backend request started');
      final endpoint = _endpointUri();
      _debugLog('backend HTTP endpoint: $endpoint');
      try {
        final request = await client.postUrl(endpoint).timeout(
              const Duration(seconds: 20),
            );
        request.headers.contentType = ContentType.json;
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        request.add(utf8.encode(body));

        final response = await request.close().timeout(
              const Duration(seconds: 60),
            );
        final raw = await response.transform(utf8.decoder).join();
        _debugLog('backend response status: ${response.statusCode}');
        _debugLog(
          'backend response content-type: '
          '${response.headers.contentType?.mimeType ?? 'unknown'}',
        );
        final decoded = _tryDecodeResponse(raw);
        _debugLog('backend response was JSON: ${decoded != null}');

        if (response.statusCode < 200 || response.statusCode >= 300) {
          final backendError = _backendErrorCode(decoded);
          _debugLog(
            'backend response failure: '
            '${backendError ?? response.statusCode}',
          );
          final backendMessage = decoded?['message']?.toString();
          final message = _messageForBackendError(
            backendError,
            response.statusCode,
            backendMessage,
          );
          _debugLog(
            'backend error message: '
            '${backendMessage ?? message}',
          );
          throw OnlineIdentificationException(
            backendError ?? 'backend_unavailable',
            message,
          );
        }

        if (decoded == null) {
          throw const FormatException('Response was not valid JSON.');
        }
        final result = MushroomIdResult.fromJson(decoded);
        _debugLog('backend response success');
        _debugLog(
          'parsed top suggestion: '
          '${result.topSuggestion?.scientificName ?? 'none'}',
        );
        return result;
      } finally {
        if (_httpClient == null) {
          client.close(force: false);
        }
      }
    } on OnlineIdentificationException catch (e) {
      _debugLog('online identification failed: OnlineIdentificationException');
      _debugLog('exception runtimeType: ${e.runtimeType}');
      _debugLog('exception message: ${e.message}');
      rethrow;
    } on SocketException catch (e) {
      _debugLog('online identification failed: SocketException');
      _debugLog('exception runtimeType: ${e.runtimeType}');
      _debugLog('exception message: ${e.message}');
      throw const OnlineIdentificationException(
        'no-internet',
        'No internet connection. Try again when you are online.',
      );
    } on TimeoutException catch (e) {
      _debugLog('online identification failed: TimeoutException');
      _debugLog('exception runtimeType: ${e.runtimeType}');
      _debugLog('exception message: ${e.message ?? 'timeout'}');
      throw const OnlineIdentificationException(
        'timeout',
        'Online identification timed out. Try again shortly.',
      );
    } on FormatException catch (e) {
      _debugLog('online identification failed: FormatException');
      _debugLog('exception runtimeType: ${e.runtimeType}');
      _debugLog('exception message: ${e.message}');
      throw const OnlineIdentificationException(
        'parse_error',
        'Online identification returned an unreadable response.',
      );
    } catch (e) {
      _debugLog('online identification failed: ${e.runtimeType}');
      _debugLog('exception runtimeType: ${e.runtimeType}');
      _debugLog('exception message: $e');
      throw const OnlineIdentificationException(
        'backend_unavailable',
        'Online identification backend is unavailable right now.',
      );
    }
  }

  Future<MushroomIdResult> _identifyWithKindwise({
    required String imageBase64,
    required String apiKey,
  }) async {
    final body = jsonEncode({
      'images': <String>[imageBase64],
      'similar_images': true,
    });
    final client = _httpClient ?? HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final endpoint = _kindwiseEndpointUri();
      _debugLog('Kindwise HTTP endpoint: $endpoint');
      _debugLog('Kindwise image count: 1');
      final request = await client.postUrl(endpoint).timeout(
            const Duration(seconds: 20),
          );
      request.headers.contentType = ContentType.json;
      request.headers.set('Api-Key', apiKey);
      request.add(utf8.encode(body));

      final response = await request.close().timeout(
            const Duration(seconds: 60),
          );
      final raw = await response.transform(utf8.decoder).join();
      _debugLog('Kindwise response status: ${response.statusCode}');
      final decoded = _tryDecodeResponse(raw);
      _debugLog('Kindwise response was JSON: ${decoded != null}');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OnlineIdentificationException(
          _kindwiseErrorCode(response.statusCode),
          _kindwiseErrorMessage(response.statusCode, decoded),
        );
      }
      if (decoded == null) {
        throw const FormatException('Response was not valid JSON.');
      }

      final result = MushroomIdResult.fromJson(decoded);
      if (result.topSuggestion == null) {
        throw const OnlineIdentificationException(
          'no_suggestions',
          'No online identification suggestions were returned for this image.',
        );
      }
      _debugLog(
        'parsed top suggestion: '
        '${result.topSuggestion?.scientificName ?? 'none'}',
      );
      return result;
    } finally {
      if (_httpClient == null) {
        client.close(force: false);
      }
    }
  }

  Uri _endpointUri() {
    final projectId = _firebaseApp.options.projectId;
    return Uri.https(
      '$_functionRegion-$projectId.cloudfunctions.net',
      '/$_functionName',
    );
  }

  Uri _kindwiseEndpointUri() {
    return Uri.https(_kindwiseHost, _kindwisePath, {
      'details': _kindwiseDetails,
    });
  }

  String _kindwiseErrorCode(int statusCode) {
    if (statusCode == 401 || statusCode == 403) {
      return 'backend_config_missing';
    }
    if (statusCode == 402 || statusCode == 429) {
      return 'quota_or_credits_unavailable';
    }
    if (statusCode == 413) {
      return 'image-too-large';
    }
    if (statusCode >= 500) {
      return 'provider-unavailable';
    }
    return 'mushroom_id_http_error';
  }

  String _kindwiseErrorMessage(
    int statusCode,
    Map<String, dynamic>? decoded,
  ) {
    final providerMessage = decoded?['message']?.toString();
    return _messageForBackendError(
      _kindwiseErrorCode(statusCode),
      statusCode,
      providerMessage,
    );
  }

  Map<String, dynamic> _decodeResponse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    throw const FormatException('Response was not an object.');
  }

  Map<String, dynamic>? _tryDecodeResponse(String raw) {
    try {
      return _decodeResponse(raw);
    } on FormatException {
      return null;
    }
  }

  String? _backendErrorCode(Map<String, dynamic>? decoded) {
    return decoded?['error']?.toString() ?? decoded?['code']?.toString();
  }

  String _messageForBackendError(
    String? errorCode,
    int statusCode,
    String? backendMessage,
  ) {
    switch (errorCode) {
      case 'backend_config_missing':
      case 'backend-config':
        return 'Online identification is not configured yet.';
      case 'unauthenticated':
      case 'auth-required':
        return 'Please sign in to use online identification.';
      case 'invalid_image':
      case 'invalid-image':
      case 'image-too-large':
      case 'missing-image':
        return 'The selected photo could not be processed.';
      case 'mushroom_id_rejected':
      case 'provider-rejected-request':
      case 'mushroom_id_http_error':
        return 'Online identification service rejected the image.';
      case 'quota_or_credits_unavailable':
      case 'quota-exceeded':
        return 'Online identification credits are unavailable.';
      case 'no_suggestions':
      case 'no-suggestions':
        return 'No confident online identification was returned.';
      case 'backend_unavailable':
      case 'provider-unavailable':
        return 'Online identification backend is unavailable right now.';
      case 'parse_error':
      case 'malformed-response':
        return 'Online identification response could not be read.';
    }

    if (backendMessage != null && backendMessage.trim().isNotEmpty) {
      return backendMessage;
    }
    return _fallbackMessageForStatus(statusCode);
  }

  String _fallbackMessageForStatus(int statusCode) {
    if (statusCode == 401) {
      return 'Sign in before using online identification.';
    }
    if (statusCode == 403 || statusCode == 404) {
      return 'Online identification backend is unavailable right now.';
    }
    if (statusCode == 413) {
      return 'Image is too large for online identification.';
    }
    if (statusCode == 429) {
      return 'Online identification quota was reached. Try again later.';
    }
    if (statusCode == 422) {
      return 'No online identification suggestions were returned for this image.';
    }
    if (statusCode >= 500) {
      return 'Online identification is unavailable right now.';
    }
    return 'Online identification failed.';
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('ONLINE_ID: $message');
    }
  }
}
