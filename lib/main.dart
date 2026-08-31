import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/io.dart';

import 'providers/match_provider.dart';
import 'server/local_server.dart';
import 'models/game.dart';
import 'ui/web/remote_control.dart';
import 'ui/web/web_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    registerIframeViewFactory();

    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Telecomando',
      home: RemoteControlScreen(),
    ));
  } else {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(size: Size(1280, 720), center: true, title: "Tabellone Segnapunti");
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setResizable(false); 
      await windowManager.setFullScreen(true);
    });

    final matchProvider = MatchProvider();
    await matchProvider.loadFromFile();
    await startLocalServer(matchProvider);

    runApp(
      ChangeNotifierProvider.value(
        value: matchProvider,
        child: const MaterialApp(debugShowCheckedModeBanner: false, home: ScoreboardApp()),
      ),
    );
  }
}

class ScoreboardApp extends StatelessWidget {
  const ScoreboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MatchProvider>();

    // --- LOGICA TIMER A SCHERMO INTERO ---
    Widget mainContent;

    if (state.isTimerVisible) {
      String m = (state.timerSeconds ~/ 60).toString().padLeft(2, '0');
      String s = (state.timerSeconds % 60).toString().padLeft(2, '0');
      Color timerColor = state.timerSeconds <= 10 ? Colors.redAccent : Colors.white;

      mainContent = Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: Padding(
            padding: const EdgeInsets.all(50.0),
            child: Text(
              "$m:$s",
              style: TextStyle(
                fontSize: 600, // Gigantesco!
                fontFamily: 'Courier',
                fontWeight: FontWeight.bold,
                color: timerColor,
                shadows: const [Shadow(color: Colors.black, blurRadius: 40, offset: Offset(0, 10))]
              ),
            ),
          ),
        ),
      );
    } else {
      // --- LOGICA NORMALE (Tabellone Punti) ---
      bool isTotals = state.currentPage == 'totals';
      String mainTitle = state.eventName;
      String subtitle = 'CLASSIFICA GENERALE';
      Game? currentGame;

      if (!isTotals) {
        int? gameIndex = int.tryParse(state.currentPage);
        if (gameIndex != null && gameIndex >= 0 && gameIndex < state.games.length) {
          currentGame = state.games[gameIndex];
          subtitle = currentGame.name.toUpperCase();
        }
      }

      List<Widget> teamCardWidgets = [];
      if (state.teams.isNotEmpty) {
        if (state.isRevealMode) {
          List<int> sortedIndices = List.generate(state.teams.length, (i) => i);
          sortedIndices.sort((a, b) {
            int scoreA = isTotals ? state.getTotalScore(a) : (currentGame?.scores[a] ?? 0);
            int scoreB = isTotals ? state.getTotalScore(b) : (currentGame?.scores[b] ?? 0);
            return scoreA.compareTo(scoreB);
          });

          for (int i = 0; i < sortedIndices.length; i++) {
            int originalIndex = sortedIndices[i];
            final team = state.teams[originalIndex];
            int score = isTotals ? state.getTotalScore(originalIndex) : (currentGame?.scores[originalIndex] ?? 0);
            bool showJolly = isTotals ? team.hasUsedJolly : (currentGame?.activeJollies[originalIndex] ?? false);
            String? partial;
            if (!isTotals) {
              partial = currentGame?.partials[originalIndex];
              if (partial == null || partial.isEmpty) partial = null;
            }

            if (i < state.revealedTeamsCount) {
              teamCardWidgets.add(Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10.0), child: _buildTeamCard(team.name, team.colorHex, score, partial, showJolly, key: ValueKey('team_${originalIndex}_revealed')))));
            } else {
              int rank = state.teams.length - i; 
              teamCardWidgets.add(Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10.0), child: _buildObscuredCard(rank))));
            }
          }
        } else {
          for (int i = 0; i < state.teams.length; i++) {
            final team = state.teams[i];
            int score = isTotals ? state.getTotalScore(i) : (currentGame?.scores[i] ?? 0);
            bool showJolly = isTotals ? team.hasUsedJolly : (currentGame?.activeJollies[i] ?? false);
            String? partial;
            if (!isTotals) {
              partial = currentGame?.partials[i];
              if (partial == null || partial.isEmpty) partial = null;
            }
            teamCardWidgets.add(Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10.0), child: _buildTeamCard(team.name, team.colorHex, score, partial, showJolly, key: ValueKey('team_$i')))));
          }
        }
      }

      mainContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                child: Text(
                  mainTitle,
                  style: const TextStyle(fontSize: 80, color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 3, shadows: [Shadow(color: Colors.black54, blurRadius: 20, offset: Offset(0, 5))]),
                ),
              ),
              FittedBox(
                child: Text(
                  subtitle,
                  style: const TextStyle(fontSize: 40, color: Colors.amberAccent, fontWeight: FontWeight.bold, letterSpacing: 5),
                ),
              ),
              const SizedBox(height: 60),
              
              if (state.teams.isEmpty)
                const Text("In attesa delle squadre...", style: TextStyle(color: Colors.white54, fontSize: 30))
              else
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: teamCardWidgets, 
                  ),
                ),
            ],
          ),
        ),
      );
    } // Fine else normale

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
          ),
        ),
        child: Stack(
          children: [
            mainContent,
            
            Positioned.fill(
              child: Offstage(
                offstage: !state.isStreamingActive,
                child: const WebRTCReceiverWidget(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamCard(String name, String colorHex, int score, String? partial, bool showJolly, {Key? key}) {
    Color teamColor = Colors.white;
    try { teamColor = Color(int.parse(colorHex.substring(1), radix: 16) + 0xFF000000); } catch (e) {}

    return Container(
      key: key, 
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: teamColor.withOpacity(0.8), width: 4),
        boxShadow: [BoxShadow(color: teamColor.withOpacity(0.3), blurRadius: 30, spreadRadius: 5)]
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name.toUpperCase(), style: TextStyle(fontSize: 50, color: teamColor, fontWeight: FontWeight.bold, letterSpacing: 2)),
                if (showJolly)
                  Container(
                    margin: const EdgeInsets.only(left: 15),
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                    decoration: BoxDecoration(color: Colors.orangeAccent, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.orange, blurRadius: 10, spreadRadius: 2)]),
                    child: const Text('🌟 JOLLY', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold, color: Colors.black)),
                  ),
              ],
            ),
          ),
          
          if (partial != null) ...[
            const SizedBox(height: 10), 
            FittedBox(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(15)),
                child: Text(
                  partial,
                  style: const TextStyle(fontSize: 35, color: Colors.cyanAccent, fontFamily: 'Courier', fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
          
          const SizedBox(height: 30),
          
          Expanded(
            child: FittedBox(
              child: TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: score),
                duration: const Duration(milliseconds: 1200), 
                curve: Curves.easeOutCubic, 
                builder: (context, value, child) {
                  if (value == 0) return const SizedBox.shrink(); 
                  return Text(value.toString(), style: const TextStyle(fontSize: 250, fontWeight: FontWeight.w900, color: Colors.white));
                }
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildObscuredCard(int rank) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white54, width: 4),
      ),
      child: Center(
        child: FittedBox(
          child: Text(
            "$rank°", 
            style: const TextStyle(fontSize: 150, color: Colors.white54, fontWeight: FontWeight.bold)
          )
        )
      )
    );
  }
}

// =======================================================
// WIDGET RICEVITORE WEBRTC
// =======================================================
class WebRTCReceiverWidget extends StatefulWidget {
  const WebRTCReceiverWidget({super.key});

  @override
  State<WebRTCReceiverWidget> createState() => _WebRTCReceiverWidgetState();
}

class _WebRTCReceiverWidgetState extends State<WebRTCReceiverWidget> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  IOWebSocketChannel? _signalingChannel;
  final List<RTCIceCandidate> _candidateBuffer = []; 

  @override
  void initState() {
    super.initState();
    _initRenderer();
    _connectSignaling();
  }

  Future<void> _initRenderer() async {
    await _renderer.initialize();
  }

  void _connectSignaling() {
    final customClient = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;

    WebSocket.connect('wss://127.0.0.1:8080/ws', customClient: customClient).then((ws) {
      _signalingChannel = IOWebSocketChannel(ws);
      _signalingChannel!.stream.listen((message) {
        _handleSignalingMessage(message);
      });
    }).catchError((e) {});
  }

  Future<void> _handleSignalingMessage(String message) async {
    try {
      final data = jsonDecode(message);

      if (data['stop'] == true) {
        _peerConnection?.close();
        _peerConnection = null;
        setState(() {
          _renderer.srcObject = null;
        });
        _candidateBuffer.clear();
        return; 
      }

      if (data['offer'] != null) {
        await _createPeerConnection();
        var offer = RTCSessionDescription(data['offer']['sdp'], data['offer']['type']);
        await _peerConnection!.setRemoteDescription(offer);
        var answer = await _peerConnection!.createAnswer();
        await _peerConnection!.setLocalDescription(answer);
        _signalingChannel?.sink.add(jsonEncode({'answer': answer.toMap()}));

        for (var cand in _candidateBuffer) {
          await _peerConnection!.addCandidate(cand);
        }
        _candidateBuffer.clear();
      } 
      else if (data['candidate'] != null) {
        var candidateMap = data['candidate'];
        var candidate = RTCIceCandidate(
            candidateMap['candidate'], candidateMap['sdpMid'], candidateMap['sdpMLineIndex']);
        
        if (_peerConnection != null) {
          await _peerConnection!.addCandidate(candidate);
        } else {
          _candidateBuffer.add(candidate);
        }
      }
    } catch (e) {}
  }

  Future<void> _createPeerConnection() async {
    if (_peerConnection != null) return;
    Map<String, dynamic> configuration = {
      "iceServers": [{"url": "stun:stun.l.google.com:19302"}]
    };
    _peerConnection = await createPeerConnection(configuration);

    _peerConnection!.onAddStream = (MediaStream stream) {
      setState(() {
        _renderer.srcObject = stream;
      });
    };

    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'video' && event.streams.isNotEmpty) {
        setState(() {
          _renderer.srcObject = event.streams[0];
        });
      }
    };

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      _signalingChannel?.sink.add(jsonEncode({'candidate': candidate.toMap()}));
    };
  }

  @override
  void dispose() {
    _renderer.dispose();
    _peerConnection?.dispose();
    _signalingChannel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: RTCVideoView(
        _renderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      ),
    );
  }
}