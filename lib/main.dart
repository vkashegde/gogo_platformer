import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const RunnerApp());
}

class RunnerApp extends StatelessWidget {
  const RunnerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Minimal Runner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(primary: Colors.white, surface: Colors.black),
      ),
      home: const GamePage(),
    );
  }
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  // World constants in logical (0..1) units.
  static const double _groundY = 0.9;
  static const double _playerX = 0.2;
  static const double _playerBaseWidth = 0.06;
  static const double _playerBaseHeight = 0.14;
  static const double _obstacleWidth = 0.06;
  static const double _obstacleHeight = 0.16;

  static const double _gravity = 5.0; // downward, in fraction/s^2
  static const double _shortJumpVelocity = -2.0; // upward, small jump
  static const double _highJumpVelocity = -3.2; // upward, high jump
  static const double _baseObstacleSpeed = 0.5; // fraction of screen per second
  static const int _doublePressThresholdMs = 250;

  double _playerY = _groundY;
  double _playerVelocity = 0;

  double _obstacleX = 1.2;

  double _elapsedSeconds = 0;
  int _score = 0;
  bool _isGameOver = false;
  int _sizeLevel = 0;
  double _obstacleScale = 1.0;

  final FocusNode _focusNode = FocusNode();
  int? _lastSpaceDownMs;
  final math.Random _random = math.Random();

  double get _playerWidth => _playerBaseWidth * (1 + 0.5 * _sizeLevel);

  double get _playerHeight => _playerBaseHeight * (1 + 0.5 * _sizeLevel);

  double get _currentObstacleSpeed {
    // Increase speed by 10% every 10 seconds.
    final int speedLevel = (_elapsedSeconds ~/ 10);
    return _baseObstacleSpeed * (1 + 0.1 * speedLevel);
  }

  double get _currentObstacleWidth => _obstacleWidth * _obstacleScale;

  double get _currentObstacleHeight => _obstacleHeight * _obstacleScale;

  Timer? _timer;
  int? _lastUpdateMs;

  @override
  void initState() {
    super.initState();
    _randomizeObstacleSize();
    _startGameLoop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_focusNode);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _randomizeObstacleSize() {
    // Ghost size varies between 70% and 150% of base size.
    _obstacleScale = 0.7 + _random.nextDouble() * 0.8;
  }

  void _startGameLoop() {
    _lastUpdateMs = DateTime.now().millisecondsSinceEpoch;
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = _lastUpdateMs ?? now;
      final dt = (now - last) / 1000.0; // seconds
      _lastUpdateMs = now;
      _updateGame(dt);
    });
  }

  void _updateGame(double dt) {
    if (_isGameOver) return;

    setState(() {
      // Time & score (1 point every 1 second).
      _elapsedSeconds += dt;
      _score = _elapsedSeconds.floor();

      // Character grows slightly every 15 seconds.
      final int newSizeLevel = (_elapsedSeconds ~/ 15);
      if (newSizeLevel != _sizeLevel) {
        _sizeLevel = newSizeLevel;
      }

      // Player physics.
      _playerVelocity += _gravity * dt;
      _playerY += _playerVelocity * dt;
      if (_playerY > _groundY) {
        _playerY = _groundY;
        _playerVelocity = 0;
      }

      // Obstacle movement.
      _obstacleX -= _currentObstacleSpeed * dt;
      if (_obstacleX + _currentObstacleWidth < 0) {
        _obstacleX = 1.2;
        _randomizeObstacleSize();
      }

      // Collision detection.
      if (_checkCollision()) {
        _isGameOver = true;
      }
    });
  }

  bool _checkCollision() {
    final double playerLeft = _playerX - _playerWidth / 2;
    final double playerRight = _playerX + _playerWidth / 2;
    final double playerTop = _playerY - _playerHeight;
    final double playerBottom = _playerY;

    final double obstacleLeft = _obstacleX;
    final double obstacleRight = _obstacleX + _currentObstacleWidth;
    final double obstacleTop = _groundY - _currentObstacleHeight;
    final double obstacleBottom = _groundY;

    final bool overlapX = playerRight > obstacleLeft && playerLeft < obstacleRight;
    final bool overlapY = playerBottom > obstacleTop && playerTop < obstacleBottom;

    return overlapX && overlapY;
  }

  void _jump(double velocity) {
    // Jump only if on (or very close to) the ground.
    if ((_playerY - _groundY).abs() < 0.005) {
      _playerVelocity = velocity;
    }
  }

  void _handleTap() {
    if (_isGameOver) {
      _resetGame();
      return;
    }

    _jump(_highJumpVelocity);
  }

  void _handleSpaceJump({required bool high}) {
    if (_isGameOver) {
      _resetGame();
      return;
    }

    _jump(high ? _highJumpVelocity : _shortJumpVelocity);
  }

  void _resetGame() {
    setState(() {
      _playerY = _groundY;
      _playerVelocity = 0;
      _obstacleX = 1.2;
      _elapsedSeconds = 0;
      _score = 0;
      _isGameOver = false;
      _sizeLevel = 0;
      _lastSpaceDownMs = null;
    });
    _randomizeObstacleSize();
    _startGameLoop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RawKeyboardListener(
        focusNode: _focusNode,
        onKey: (event) {
          if (event is RawKeyDownEvent && event.logicalKey == LogicalKeyboardKey.space) {
            final int now = DateTime.now().millisecondsSinceEpoch;
            final int? last = _lastSpaceDownMs;
            final bool isDouble = last != null && (now - last) <= _doublePressThresholdMs;
            _lastSpaceDownMs = now;
            _handleSpaceJump(high: isDouble);
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double width = constraints.maxWidth;
              final double height = constraints.maxHeight;

              // Convert logical units to pixels.
              final double groundPixelY = height * _groundY;
              final double groundHeight = height - groundPixelY;

              final double playerPixelWidth = width * _playerWidth;
              final double playerPixelHeight = height * _playerHeight;
              final double playerCenterX = width * _playerX;
              final double playerBottomY = height * _playerY;

              final double obstaclePixelWidth = width * _currentObstacleWidth;
              final double obstaclePixelHeight = height * _currentObstacleHeight;
              final double obstacleLeftX = width * _obstacleX;
              final double obstacleBottomY = groundPixelY;

              return Stack(
                children: [
                  // Background image.
                  Positioned.fill(child: Image.asset('assets/background.jpg', fit: BoxFit.cover)),

                  // Ground overlay to keep a clear horizon.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: groundPixelY,
                    height: groundHeight,
                    child: Container(color: Colors.black.withOpacity(0.35)),
                  ),

                  // Runner character.
                  Positioned(
                    left: playerCenterX - playerPixelWidth / 2,
                    top: playerBottomY - playerPixelHeight,
                    width: playerPixelWidth,
                    height: playerPixelHeight,
                    child: Image.asset('assets/game_character.png', fit: BoxFit.contain),
                  ),

                  // Ghost obstacle.
                  Positioned(
                    left: obstacleLeftX,
                    top: obstacleBottomY - obstaclePixelHeight,
                    width: obstaclePixelWidth,
                    height: obstaclePixelHeight,
                    child: Image.asset('assets/ghost.png', fit: BoxFit.contain),
                  ),
                  Positioned(
                    top: 40,
                    left: 24,
                    child: Text(
                      'Score: $_score',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 40,
                    right: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: const [
                        Text(
                          'Tap / Space to jump',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Single space: small jump  |  Double space: high jump',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (_isGameOver)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Game Over',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Score: $_score',
                            style: const TextStyle(color: Colors.white70, fontSize: 18),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white70),
                            ),
                            child: const Text(
                              'Tap anywhere to restart',
                              style: TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
