import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart';
import '../services/location_cache.dart';

class QiblaScreen extends StatefulWidget {
  const QiblaScreen({super.key});

  @override
  State<QiblaScreen> createState() => _QiblaScreenState();
}

class _QiblaScreenState extends State<QiblaScreen> {
  _QiblaState _state = _QiblaState.loading;
  String? _errorMessage;
  Position? _currentPosition;
  String _tileType = 'normal';

  static const _kaabaLatLng = LatLng(21.4225, 39.8262);

  // Cache position so tab switches are instant
  static Position? _cachedPosition;

  @override
  void initState() {
    super.initState();
    // Show cached position instantly if available
    if (_cachedPosition != null) {
      _currentPosition = _cachedPosition;
      _state = _QiblaState.ready;
    }
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    if (_cachedPosition == null) {
      setState(() {
        _state = _QiblaState.loading;
        _errorMessage = null;
      });
    }

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied ||
            requested == LocationPermission.deniedForever) {
          if (mounted && _cachedPosition == null) {
            setState(() {
              _state = _QiblaState.error;
              _errorMessage = 'Location permission denied. Qibla direction requires your location.';
            });
          }
          return;
        }
      } else if (permission == LocationPermission.deniedForever) {
        if (mounted && _cachedPosition == null) {
          setState(() {
            _state = _QiblaState.error;
            _errorMessage = 'Location permission permanently denied.\nEnable it in your device settings.';
          });
        }
        return;
      }

      // 1. Use last-known position first (instant)
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted && _cachedPosition == null) {
        _cachedPosition = last;
        setState(() {
          _currentPosition = last;
          _state = _QiblaState.ready;
        });
      }

      // 2. Get fresh position in background (low accuracy = fast)
      final fresh = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(const Duration(seconds: 10));

      _cachedPosition = fresh;
      LocationCache.lat = fresh.latitude;
      LocationCache.lng = fresh.longitude;
      if (mounted) {
        setState(() {
          _currentPosition = fresh;
          _state = _QiblaState.ready;
        });
      }
    } catch (e) {
      if (mounted && _cachedPosition == null) {
        setState(() {
          _state = _QiblaState.error;
          _errorMessage = 'Failed to get location: $e';
        });
      }
    }
  }

  double _calculateQiblaDirection(LatLng from, LatLng to) {
    final lat1 = from.latitude.radians;
    final lat2 = to.latitude.radians;
    final deltaLong = (to.longitude - from.longitude).radians;
    final x = math.sin(deltaLong);
    final y = math.cos(lat1) * math.tan(lat2) - math.sin(lat1) * math.cos(deltaLong);
    return (math.atan2(x, y) * (180 / math.pi) + 360) % 360;
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _QiblaState.loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Getting your location…'),
          ],
        ),
      );
    }

    if (_state == _QiblaState.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? 'Unknown error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _getCurrentLocation,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final userLatLng = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    final tileUrl = _tileType == 'normal'
        ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
        : 'https://tile.opentopomap.org/{z}/{x}/{y}.png';
    final bounds = LatLngBounds.fromPoints([userLatLng, _kaabaLatLng]);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Qibla Direction'),
        actions: [
          IconButton(
            icon: const Icon(Icons.layers),
            tooltip: 'Toggle map style',
            onPressed: () => setState(
              () => _tileType = _tileType == 'normal' ? 'satellite' : 'normal',
            ),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          FlutterMap(
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(
                bounds: bounds,
                padding: const EdgeInsets.all(50),
              ),
            ),
            children: [
              TileLayer(
                key: ValueKey(_tileType),
                urlTemplate: tileUrl,
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.example.prayer_times_app',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [userLatLng, _kaabaLatLng],
                    strokeWidth: 4.0,
                    color: Colors.green,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: userLatLng,
                    width: 80,
                    height: 80,
                    child: const Icon(Icons.location_pin, color: Colors.blue, size: 40),
                  ),
                  Marker(
                    point: _kaabaLatLng,
                    width: 60,
                    height: 60,
                    child: Image.asset('assets/icons/kaaba.png', fit: BoxFit.contain),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
              bottom: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white70,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.explore, color: Colors.green, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Qibla direction: ${_calculateQiblaDirection(userLatLng, _kaabaLatLng).toStringAsFixed(1)}°',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _QiblaState { loading, ready, error }

extension _DegreeExtension on num {
  double get radians => this * (math.pi / 180.0);
}
