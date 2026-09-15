import 'dart:convert';
import 'dart:io';
import 'dart:async'; // Aggiunto per il Timer
import 'package:flutter/material.dart';

// --- IMPORT AGGIUNTI PER IL WEBRTC ---
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/io.dart';

import '../models/team.dart';
import '../models/game.dart';

class MatchProvider extends ChangeNotifier {
  List<Team> teams = [];
  List<Game> games = [];
  String currentPage = 'totals';
  String eventName = 'GRANDE EVENTO 2026';

  bool isRevealMode = false;
  int revealedTeamsCount = 0;
  bool isStreamingActive = false;

  // --- STATO DEL COUNTDOWN ---
  bool isTimerVisible = false;
  int timerSeconds = 300; // Tempo attuale (es. 5 min = 300)
  int initialTimerSeconds = 300; // Tempo salvato per il reset
  bool isTimerRunning = false;
  Timer? _countdownTimer;

  final String _saveFileName = 'scoreboard_backup.json';

  // ====================================================
  // --- MOTORE WEBRTC INTEGRATO ---
  // ====================================================
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  IOWebSocketChannel? _signalingChannel;
  final List<RTCIceCandidate> _candidateBuffer = []; 
  bool isRendererReady = false;

  Future<void> initWebRTC() async {
    await renderer.initialize();
    isRendererReady = true;
    _connectSignaling();
    notifyListeners();
  }

  void _connectSignaling() {
    final customClient = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;

    WebSocket.connect('wss://127.0.0.1:8080/ws', customClient: customClient).then((ws) {
      _signalingChannel = IOWebSocketChannel(ws);
      _signalingChannel!.stream.listen(_handleSignalingMessage);
    }).catchError((e) {
      print("⚠️ Errore WebSocket WebRTC: $e");
    });
  }

  // --- NUOVA FUNZIONE: FORZA LO STOP DEL VIDEO ---
  void forceStopStream() {
    print("🛑 FORZATURA STOP STREAMING MANUALE");
    _peerConnection?.close();
    _peerConnection = null;
    renderer.srcObject = null;
    _candidateBuffer.clear();
    isStreamingActive = false;

    // Invia il segnale di stop sul websocket così i telefoni (Broadcaster) si scollegano
    _signalingChannel?.sink.add(jsonEncode({'stop': true}));
    notifyListeners();
  }

  Future<void> _handleSignalingMessage(dynamic message) async {
    try {
      final data = jsonDecode(message);

      if (data['stop'] == true) {
        _peerConnection?.close();
        _peerConnection = null;
        renderer.srcObject = null;
        _candidateBuffer.clear();
        isStreamingActive = false;
        notifyListeners();
        return; 
      }

      if (data['offer'] != null) {
        // --- BLOCCO DI SICUREZZA: SE GIÀ IN ONDA, IGNORA! ---
        if (isStreamingActive) {
          print("⚠️ Stream già attivo! Rifiuto la connessione del secondo dispositivo.");
          return;
        }

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

        isStreamingActive = true;
        notifyListeners();
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
    } catch (e) {
      print("❌ Errore WebRTC: $e");
    }
  }

  Future<void> _createPeerConnection() async {
    if (_peerConnection != null) return;
    print("⚙️ Creazione connessione WebRTC...");

    Map<String, dynamic> configuration = {
      "iceServers": [{"url": "stun:stun.l.google.com:19302"}]
    };
    _peerConnection = await createPeerConnection(configuration);

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      print("🧊 Stato Rete Video: ${state.name}");
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        print("❌ ERRORE CRITICO: I fotogrammi video non riescono a passare (Firewall o Rete).");
      }
    };

    _peerConnection!.onAddStream = (MediaStream stream) {
      print("🎥 Flusso Video in arrivo! Tracce trovate: ${stream.getVideoTracks().length}");
      renderer.srcObject = stream;
      notifyListeners();
    };

    _peerConnection!.onTrack = (RTCTrackEvent event) {
      print("🎥 Traccia in arrivo: ${event.track.kind}");
      if (event.track.kind == 'video' && event.streams.isNotEmpty) {
        renderer.srcObject = event.streams[0];
        notifyListeners();
      }
    };

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      _signalingChannel?.sink.add(jsonEncode({'candidate': candidate.toMap()}));
    };
  }
  // ====================================================

  Future<void> loadFromFile() async {
    try {
      final file = File(_saveFileName);
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content);

        eventName = data['eventName'] ?? 'GRANDE EVENTO 2026';
        currentPage = data['currentPage'] ?? 'totals';
        isRevealMode = data['isRevealMode'] ?? false;
        revealedTeamsCount = data['revealedTeamsCount'] ?? 0;

        isTimerVisible = data['isTimerVisible'] ?? false;
        timerSeconds = data['timerSeconds'] ?? 300;
        initialTimerSeconds = data['initialTimerSeconds'] ?? 300;
        isTimerRunning = false; // Il timer parte sempre fermo al riavvio

        if (data['teams'] != null) {
          teams = (data['teams'] as List).map((t) => Team.fromJson(t)).toList();
        }
        if (data['games'] != null) {
          games = (data['games'] as List).map((g) => Game.fromJson(g)).toList();
        }
        notifyListeners();
      }
    } catch (e) {
      print("⚠️ Errore caricamento: $e");
    }
  }

  void _autoSave() {
    notifyListeners(); // <-- Spostato in cima per forzare subito il ridisegno grafico
    try {
      final data = {
        'eventName': eventName,
        'currentPage': currentPage,
        'isRevealMode': isRevealMode,
        'revealedTeamsCount': revealedTeamsCount,
        'isTimerVisible': isTimerVisible,
        'timerSeconds': timerSeconds,
        'initialTimerSeconds': initialTimerSeconds,
        'teams': teams.map((t) => t.toJson()).toList(),
        'games': games.map((g) => g.toJson()).toList(),
      };
      File(_saveFileName).writeAsString(jsonEncode(data));
    } catch (e) {}
  }

  // --- FUNZIONI COUNTDOWN ---
  void toggleTimerVisibility(bool visible) {
    isTimerVisible = visible;
    _autoSave();
  }

  void setTimer(int minutes, int seconds) {
    initialTimerSeconds = (minutes * 60) + seconds;
    timerSeconds = initialTimerSeconds;
    stopTimer();
    _autoSave();
  }

  void startTimer() {
    if (!isTimerRunning && timerSeconds > 0) {
      isTimerRunning = true;
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (timerSeconds > 0) {
          timerSeconds--;
          notifyListeners(); // Aggiorna solo UI
        } else {
          stopTimer();
        }
      });
      notifyListeners();
    }
  }

  void stopTimer() {
    isTimerRunning = false;
    _countdownTimer?.cancel();
    notifyListeners();
  }

  void resetTimer() {
    stopTimer();
    timerSeconds = initialTimerSeconds;
    _autoSave();
  }
  // ---------------------------

  void toggleRevealMode(bool enable) {
    isRevealMode = enable;
    if (!enable) revealedTeamsCount = 0;
    _autoSave();
  }

  void revealNext() {
    if (revealedTeamsCount < teams.length) revealedTeamsCount++;
    _autoSave();
  }

  void revealPrev() {
    if (revealedTeamsCount > 0) revealedTeamsCount--;
    _autoSave();
  }

  void setEventName(String name) {
    eventName = name;
    _autoSave();
  }

  void addGame(String name) {
    int newId = games.isEmpty ? 1 : games.last.id + 1;
    final newGame = Game(id: newId, name: name);
    for (var team in teams) {
      newGame.scores[team.id.toString()] = 0; 
      newGame.partials[team.id.toString()] = "";
      newGame.participations[team.id.toString()] = true;
    }
    games.add(newGame);
    _autoSave();
  }

  void addTeam(String name, String color) {
    int newId = teams.isEmpty ? 1 : teams.last.id + 1;
    final newTeam = Team(id: newId, name: name, colorHex: color);
    teams.add(newTeam);

    String newIndexStr = newId.toString(); 
    for (var game in games) {
      game.scores[newIndexStr] = 0;
      game.partials[newIndexStr] = "";
      game.participations[newIndexStr] = true;
    }
    _autoSave();
  }

  void removeGame(int id) {
    int index = games.indexWhere((g) => g.id == id);
    if (index != -1) {
      games.removeAt(index);
      
      bool pageChanged = false;
      if (currentPage == id.toString()) {
        currentPage = 'totals';
        pageChanged = true;
      }
      if (pageChanged && isRevealMode) revealedTeamsCount = 0;
      _autoSave();
    }
  }

  void removeTeam(int id) {
    teams.removeWhere((t) => t.id == id);
    String idStr = id.toString();
    for (var game in games) {
      game.scores.remove(idStr);
      game.partials.remove(idStr);
      game.participations.remove(idStr);
      game.activeJollies.remove(id); // activeJollies uses int ID as key
    }
    _autoSave();
  }

  void resetGameScores(int gameId) {
    int index = games.indexWhere((g) => g.id == gameId);
    if (index != -1) {
      for (var team in teams) {
        String idStr = team.id.toString();
        games[index].scores[idStr] = 0;
        games[index].partials[idStr] = "";
      }
      games[index].activeJollies.clear();
      _autoSave();
    }
  }

  void resetAll() {
    teams.clear();
    games.clear();
    eventName = 'NUOVO EVENTO';
    currentPage = 'totals';
    isRevealMode = false;
    revealedTeamsCount = 0;
    isTimerVisible = false;
    stopTimer();
    final file = File(_saveFileName);
    if (file.existsSync()) file.deleteSync();
    _autoSave();
  }

  void activateJolly(int gameId, int teamId) {
    final gameIndex = games.indexWhere((g) => g.id == gameId);
    final teamIndex = teams.indexWhere((t) => t.id == teamId);
    
    if (teamIndex != -1 && gameIndex != -1 && !teams[teamIndex].hasUsedJolly) {
      games[gameIndex].activeJollies[teamId] = true;
      teams[teamIndex].hasUsedJolly = true;
      _autoSave();
    }
  }

  void revokeJolly(int teamId) {
    final teamIndex = teams.indexWhere((t) => t.id == teamId);
    if (teamIndex != -1) {
      teams[teamIndex].hasUsedJolly = false;
      for (var game in games) {
        game.activeJollies[teamId] = false;
      }
      _autoSave();
    }
  }

  void setParticipation(int gameId, int teamId, bool isParticipating) {
    final gameIndex = games.indexWhere((g) => g.id == gameId); 
    print('📡 [setParticipation] Aggiornamento partecipazione: Game $gameId, Team $teamId, Partecipante: $isParticipating');
    
    if (gameIndex != -1) {
      games[gameIndex].participations[teamId.toString()] = isParticipating;
      _autoSave();
    }
  }

  void updateScore(int gameId, int teamId, int points) {
    final gameIndex = games.indexWhere((g) => g.id == gameId);
    if (gameIndex != -1) {
      games[gameIndex].scores[teamId.toString()] = points; 
      _autoSave();
    }
  }

  void updatePartial(int gameId, int teamId, String partialValue) {
    final gameIndex = games.indexWhere((g) => g.id == gameId);
    if (gameIndex != -1) {
      games[gameIndex].partials[teamId.toString()] = partialValue; 
      _autoSave();
    }
  }

  void navigateTo(String page) {
    if (currentPage != page) {
      currentPage = page;
      if (isRevealMode) revealedTeamsCount = 0;
      _autoSave();
    }
  }

  int getTotalScore(int teamId) { 
    String teamIdStr = teamId.toString();
    return games.fold(0, (sum, game) {
      int score = (game.scores[teamIdStr] as num?)?.toInt() ?? 0;
      return sum + score;
    });
  }
}