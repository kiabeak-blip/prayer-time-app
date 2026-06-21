import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_compass/flutter_compass.dart';
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
  double _heading = 0;
  StreamSubscription<CompassEvent>? _compassSub;
  final MapController _mapController = MapController();
  bool _compassLocked = false;
  bool _isFullscreen = false;

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

    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (isMobile) {
      _compassSub = FlutterCompass.events?.listen((event) {
        final heading = event.heading;
        if (heading == null || !mounted || _compassLocked) return;
        setState(() => _heading = heading);
        // Rotate the map so the top of the phone always points to true north's
        // current heading, making the Kaaba line/marker reflect the live qibla
        // direction relative to how the phone is held.
        try {
          _mapController.rotate(-heading);
        } catch (_) {
          // Map may not be attached yet on the very first events.
        }
      });
    }
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  void _toggleCompassLock() {
    setState(() => _compassLocked = !_compassLocked);
  }

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    SystemChrome.setEnabledSystemUIMode(
      _isFullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
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

  /// Linearly interpolated point between [from] and [to] at fraction [t]
  /// (0 = from, 1 = to) — used to place the direction arrow near the
  /// Kaaba end of the line without overlapping the Kaaba marker itself.
  LatLng _pointAlong(LatLng from, LatLng to, double t) {
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
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
    final qiblaBearing = _calculateQiblaDirection(userLatLng, _kaabaLatLng);
    final bounds = LatLngBounds.fromPoints([userLatLng, _kaabaLatLng]);
    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    return Scaffold(
      appBar: _isFullscreen
          ? null
          : AppBar(
              title: const Text('Qibla Direction'),
              actions: [
                IconButton(
                  icon: Icon(_compassLocked ? Icons.lock : Icons.lock_open),
                  tooltip: _compassLocked ? 'Unlock compass' : 'Lock compass',
                  onPressed: _toggleCompassLock,
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.layers),
                  tooltip: 'Map style',
                  initialValue: _tileType,
                  onSelected: (value) => setState(() => _tileType = value),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'normal', child: Text('Normal')),
                    PopupMenuItem(value: 'satellite', child: Text('Satellite')),
                    PopupMenuItem(value: 'hybrid', child: Text('Hybrid')),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.fullscreen),
                  tooltip: 'Maximize map',
                  onPressed: _toggleFullscreen,
                ),
              ],
            ),
      body: Stack(
        children: [
          _buildBody(isMobile, qiblaBearing, userLatLng, bounds),
          if (_isFullscreen)
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                child: FloatingActionButton.small(
                  heroTag: 'qibla_fullscreen_exit',
                  onPressed: _toggleFullscreen,
                  tooltip: 'Exit fullscreen',
                  child: const Icon(Icons.fullscreen_exit),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(
    bool isMobile,
    double qiblaBearing,
    LatLng userLatLng,
    LatLngBounds bounds,
  ) {
    return Column(
      children: [
          // ── Live Qibla Compass ───────────────────────────────────────────
          if (_isFullscreen)
            const SizedBox.shrink()
          else if (isMobile)
            Builder(
              builder: (context) {
                final heading = _heading;
                final rotation = (qiblaBearing - heading) * (math.pi / 180);
                final isAligned = ((qiblaBearing - heading) % 360).abs() < 10 ||
                    ((qiblaBearing - heading) % 360).abs() > 350;

                return Container(
                  color: isAligned
                      ? const Color(0xFF1B3A2D)
                      : Colors.grey.shade100,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      // Compass circle
                      SizedBox(
                        width: 200,
                        height: 200,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Outer ring
                            Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isAligned ? Colors.white : Colors.grey.shade400,
                                  width: 3,
                                ),
                                color: isAligned
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.white,
                              ),
                            ),
                            // N/S/E/W labels
                            ..._compassLabels(isAligned),
                            // Rotating Kaaba arrow
                            Transform.rotate(
                              angle: rotation,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset(
                                    'assets/icons/kaaba.png',
                                    width: 40,
                                    height: 40,
                                    color: isAligned ? Colors.white : const Color(0xFF1B3A2D),
                                  ),
                                  Container(
                                    width: 3,
                                    height: 60,
                                    color: isAligned ? Colors.white : const Color(0xFF1B3A2D),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isAligned ? Colors.white : const Color(0xFF1B3A2D),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Status text
                      Text(
                        isAligned
                            ? '🕋 You are facing the Kaaba!'
                            : 'Turn to align the Kaaba arrow upward',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isAligned ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Qibla: ${qiblaBearing.toStringAsFixed(1)}°',
                        style: TextStyle(
                          fontSize: 13,
                          color: isAligned ? Colors.white70 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.grey.shade100,
              child: Text(
                'Compass requires a mobile device  |  Qibla: ${qiblaBearing.toStringAsFixed(1)}°',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),

          // ── Map ───────────────────────────────────────────────────────────
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCameraFit: CameraFit.bounds(
                  bounds: bounds,
                  padding: const EdgeInsets.all(50),
                ),
                initialRotation: -_heading,
              ),
              children: [
                ..._buildTileLayers(),
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
                      child: SvgPicture.asset('assets/icons/kaaba.svg', fit: BoxFit.contain),
                    ),
                    // Arrowhead near the Kaaba end of the line, rotated to the
                    // qibla bearing, so the line's direction is unambiguous.
                    Marker(
                      point: _pointAlong(userLatLng, _kaabaLatLng, 0.9),
                      width: 26,
                      height: 26,
                      child: Transform.rotate(
                        angle: qiblaBearing * (math.pi / 180),
                        child: const Icon(
                          Icons.navigation,
                          color: Colors.green,
                          size: 26,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
  }

  List<TileLayer> _buildTileLayers() {
    const satelliteUrl =
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
    const labelsUrl =
        'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}';

    switch (_tileType) {
      case 'satellite':
        return [
          TileLayer(
            key: const ValueKey('satellite'),
            urlTemplate: satelliteUrl,
            userAgentPackageName: 'com.muslimapp.awqat',
          ),
        ];
      case 'hybrid':
        return [
          TileLayer(
            key: const ValueKey('hybrid-base'),
            urlTemplate: satelliteUrl,
            userAgentPackageName: 'com.muslimapp.awqat',
          ),
          TileLayer(
            key: const ValueKey('hybrid-labels'),
            urlTemplate: labelsUrl,
            userAgentPackageName: 'com.muslimapp.awqat',
          ),
        ];
      default:
        return [
          TileLayer(
            key: const ValueKey('normal'),
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c'],
            userAgentPackageName: 'com.muslimapp.awqat',
          ),
        ];
    }
  }

  List<Widget> _compassLabels(bool isAligned) {
    final color = isAligned ? Colors.white70 : Colors.grey.shade500;
    const style = TextStyle(fontSize: 12, fontWeight: FontWeight.bold);
    return [
      Positioned(top: 8,  child: Text('N', style: style.copyWith(color: color))),
      Positioned(bottom: 8, child: Text('S', style: style.copyWith(color: color))),
      Positioned(left: 8,  child: Text('W', style: style.copyWith(color: color))),
      Positioned(right: 8, child: Text('E', style: style.copyWith(color: color))),
    ];
  }
}

enum _QiblaState { loading, ready, error }

extension _DegreeExtension on num {
  double get radians => this * (math.pi / 180.0);
}
