import 'dart:convert';
import 'dart:io'; 
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../providers/match_provider.dart';

Middleware corsHeaders() {
  return (Handler innerHandler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: {'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS'});
      }
      final response = await innerHandler(request);
      return response.change(headers: {'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS'});
    };
  };
}

Future<void> startLocalServer(MatchProvider provider) async {
  final router = Router();

  router.get('/api/state', (Request request) {
    final data = {
      'eventName': provider.eventName,
      'currentPage': provider.currentPage,
      'isRevealMode': provider.isRevealMode, 
      'revealedTeamsCount': provider.revealedTeamsCount, 
      'isStreamingActive': provider.isStreamingActive, 
      // Dati Countdown:
      'isTimerVisible': provider.isTimerVisible,
      'timerSeconds': provider.timerSeconds,
      'isTimerRunning': provider.isTimerRunning,
      'teams': provider.teams.asMap().entries.map((e) => {
        'id': e.key, 
        'name': e.value.name, 
        'colorHex': e.value.colorHex,
        'hasUsedJolly': e.value.hasUsedJolly
      }).toList(),
      'games': provider.games.asMap().entries.map((e) => {
        'id': e.key, 
        'name': e.value.name
      }).toList(),
    };
    return Response.ok(jsonEncode(data), headers: {'Content-Type': 'application/json'});
  });

  // --- API TIMER ---
  router.post('/api/timer/visibility', (Request request) {
    bool show = request.url.queryParameters['show'] == 'true';
    provider.toggleTimerVisibility(show);
    return Response.ok('Visibility updated');
  });

  router.post('/api/timer/start', (Request request) {
    provider.startTimer();
    return Response.ok('Timer started');
  });

  router.post('/api/timer/stop', (Request request) {
    provider.stopTimer();
    return Response.ok('Timer stopped');
  });

  router.post('/api/timer/reset', (Request request) {
    provider.resetTimer();
    return Response.ok('Timer reset');
  });

  router.post('/api/timer/set', (Request request) {
    int m = int.tryParse(request.url.queryParameters['m'] ?? '0') ?? 0;
    int s = int.tryParse(request.url.queryParameters['s'] ?? '0') ?? 0;
    provider.setTimer(m, s);
    return Response.ok('Timer set');
  });
  // -----------------

  router.post('/api/reveal/toggle', (Request request) {
    bool enable = request.url.queryParameters['enable'] == 'true';
    provider.toggleRevealMode(enable);
    return Response.ok('Modalità annuncio toggled');
  });

  router.post('/api/reveal/next', (Request request) {
    provider.revealNext();
    return Response.ok('Next revealed');
  });

  router.post('/api/reveal/prev', (Request request) {
    provider.revealPrev();
    return Response.ok('Prev revealed');
  });

  router.post('/api/event', (Request request) {
    provider.setEventName(request.url.queryParameters['name'] ?? 'Evento');
    return Response.ok('Nome evento aggiornato');
  });

  router.post('/api/game', (Request request) {
    provider.addGame(request.url.queryParameters['name'] ?? 'Nuovo Gioco');
    return Response.ok('Gioco aggiunto');
  });

  router.post('/api/team', (Request request) {
    provider.addTeam(request.url.queryParameters['name'] ?? 'Nuova Squadra', request.url.queryParameters['color'] ?? '#FFFFFF');
    return Response.ok('Squadra aggiunta');
  });

  router.post('/api/navigate', (Request request) {
    provider.navigateTo(request.url.queryParameters['page'] ?? 'totals');
    return Response.ok('Navigazione effettuata');
  });

  router.post('/api/score', (Request request) {
    int gIdx = int.tryParse(request.url.queryParameters['game'] ?? '0') ?? 0;
    int tIdx = int.tryParse(request.url.queryParameters['team'] ?? '0') ?? 0;
    int pts = int.tryParse(request.url.queryParameters['points'] ?? '0') ?? 0;
    provider.updateScore(gIdx, tIdx, pts);
    return Response.ok('Punteggio aggiornato');
  });

  router.post('/api/jolly', (Request request) {
    int gIdx = int.tryParse(request.url.queryParameters['game'] ?? '0') ?? 0;
    int tIdx = int.tryParse(request.url.queryParameters['team'] ?? '0') ?? 0;
    provider.activateJolly(gIdx, tIdx);
    return Response.ok('Jolly attivato');
  });

  router.post('/api/jolly/revoke', (Request request) {
    int tIdx = int.tryParse(request.url.queryParameters['team'] ?? '0') ?? 0;
    provider.revokeJolly(tIdx);
    return Response.ok('Jolly annullato');
  });

  router.post('/api/partial', (Request request) {
    int gIdx = int.tryParse(request.url.queryParameters['game'] ?? '0') ?? 0;
    int tIdx = int.tryParse(request.url.queryParameters['team'] ?? '0') ?? 0;
    provider.updatePartial(gIdx, tIdx, request.url.queryParameters['value'] ?? '');
    return Response.ok('Parziale aggiornato');
  });

  router.post('/api/delete/game', (Request request) {
    provider.removeGame(int.tryParse(request.url.queryParameters['id'] ?? '') ?? -1);
    return Response.ok('Gioco eliminato');
  });

  router.post('/api/delete/team', (Request request) {
    provider.removeTeam(int.tryParse(request.url.queryParameters['id'] ?? '') ?? -1);
    return Response.ok('Squadra eliminata');
  });

  router.post('/api/reset/game', (Request request) {
    provider.resetGameScores(int.tryParse(request.url.queryParameters['id'] ?? '') ?? -1);
    return Response.ok('Punteggi resettati');
  });

  router.post('/api/reset/all', (Request request) {
    provider.resetAll();
    return Response.ok('Tutto resettato');
  });

  final List<WebSocketChannel> activeChannels = [];

  router.get('/ws', webSocketHandler((WebSocketChannel webSocket) {
    activeChannels.add(webSocket);
    webSocket.stream.listen((message) {
      try {
        final decoded = jsonDecode(message);
        if (decoded['offer'] != null) {
          provider.setStreamingActive(true);
        } else if (decoded['stop'] == true) {
          provider.setStreamingActive(false);
        }
      } catch (e) {}

      for (var channel in activeChannels) {
        if (channel != webSocket) {
          channel.sink.add(message);
        }
      }
    }, onDone: () {
      activeChannels.remove(webSocket);
    }, onError: (err) {
      activeChannels.remove(webSocket);
    });
  }));

  final staticHandler = createStaticHandler('build/web', defaultDocument: 'index.html');
  final cascade = Cascade().add(router.call).add(staticHandler);
  
  final handler = const Pipeline().addMiddleware(corsHeaders()).addHandler(cascade.handler);
  
  try {
    final securityContext = SecurityContext()
      ..useCertificateChain('certs/cert.pem')
      ..usePrivateKey('certs/key.pem');

    print('🟢 Server in ascolto su HTTPS e WSS (Porta 8080)');
    await io.serve(handler, '0.0.0.0', 8080, securityContext: securityContext);
  } catch (e) {
    print('⚠️ Certificati SSL non trovati. Server in ascolto su HTTP normale.');
    await io.serve(handler, '0.0.0.0', 8080);
  }
}