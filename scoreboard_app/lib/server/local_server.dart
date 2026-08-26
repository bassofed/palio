import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
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

  router.post('/api/event', (Request request) {
    provider.setEventName(request.url.queryParameters['name'] ?? 'Evento');
    return Response.ok('Nome evento aggiornato');
  });

  router.post('/api/game', (Request request) {
    final name = request.url.queryParameters['name'] ?? 'Nuovo Gioco';
    provider.addGame(name);
    return Response.ok('Gioco aggiunto');
  });

  router.post('/api/team', (Request request) {
    final name = request.url.queryParameters['name'] ?? 'Nuova Squadra';
    final color = request.url.queryParameters['color'] ?? '#FFFFFF';
    provider.addTeam(name, color);
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

  final staticHandler = createStaticHandler('build/web', defaultDocument: 'index.html');
  final cascade = Cascade().add(router.call).add(staticHandler);
  
  final handler = const Pipeline().addMiddleware(corsHeaders()).addHandler(cascade.handler);
  await io.serve(handler, '0.0.0.0', 8080);
}