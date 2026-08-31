import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class RemoteControlScreen extends StatefulWidget {
  const RemoteControlScreen({super.key});

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen> {
  int currentGameIndex = 0;
  List<dynamic> teams = [];
  List<dynamic> games = [];
  String eventName = '';
  String activePage = 'totals';
  
  bool isRevealMode = false;
  int revealedTeamsCount = 0;

  bool isTimerVisible = false;
  int timerSeconds = 0;
  bool isTimerRunning = false;
  
  bool isStreamingActive = false;
  
  Timer? _pollingTimer;

  Color selectedTeamColor = Colors.white;
  
  final TextEditingController eventNameCtrl = TextEditingController();
  final TextEditingController newTeamNameCtrl = TextEditingController();
  final TextEditingController newGameNameCtrl = TextEditingController();
  final TextEditingController timerMinCtrl = TextEditingController(text: "5");
  final TextEditingController timerSecCtrl = TextEditingController(text: "0");

  Map<int, TextEditingController> scoreCtrls = {};
  Map<int, TextEditingController> partialCtrls = {};
  
  Map<int, String> savedScores = {};
  Map<int, String> savedPartials = {};

  @override
  void initState() {
    super.initState();
    fetchState();
    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isTimerVisible || isTimerRunning || isStreamingActive) fetchState(silent: true);
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> fetchState({bool silent = false}) async {
    try {
      final url = Uri.parse('${Uri.base.origin}/api/state');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          activePage = data['currentPage'];
          isRevealMode = data['isRevealMode'] ?? false;
          revealedTeamsCount = data['revealedTeamsCount'] ?? 0;
          teams = data['teams'];
          games = data['games'];
          
          isTimerVisible = data['isTimerVisible'] ?? false;
          timerSeconds = data['timerSeconds'] ?? 0;
          isTimerRunning = data['isTimerRunning'] ?? false;
          
          isStreamingActive = data['isStreamingActive'] ?? false;
          
          if (!silent) {
            eventName = data['eventName'];
            eventNameCtrl.text = eventName;
          }
          
          if (activePage != 'totals') {
            int? pageIndex = int.tryParse(activePage);
            if (pageIndex != null && games.any((g) => g['id'] == pageIndex)) currentGameIndex = pageIndex;
          } else if (games.isNotEmpty && !games.any((g) => g['id'] == currentGameIndex)) {
            currentGameIndex = games.first['id'];
          }

          if (activePage != 'totals') {
            var currentGame = games.firstWhere((g) => g['id'] == currentGameIndex, orElse: () => null);
            if (currentGame != null) {
              var scores = currentGame['scores'] ?? {};
              var partials = currentGame['partials'] ?? {};

              for (var t in teams) {
                int id = t['id'];
                if (!scoreCtrls.containsKey(id)) scoreCtrls[id] = TextEditingController();
                if (!partialCtrls.containsKey(id)) partialCtrls[id] = TextEditingController();

                String sScore = (scores[id.toString()] ?? 0).toString();
                String sPartial = (partials[id.toString()] ?? '').toString();

                savedScores[id] = sScore;
                savedPartials[id] = sPartial;

                if (!silent) {
                  scoreCtrls[id]!.text = sScore;
                  partialCtrls[id]!.text = sPartial;
                }
              }
            }
          }
        });
      }
    } catch (e) {}
  }

  Future<void> sendCommand(String endpoint) async {
    final url = Uri.parse('${Uri.base.origin}$endpoint');
    try {
      await http.post(url);
      if (!endpoint.contains('timer/start') && !endpoint.contains('timer/stop') && !endpoint.contains('navigate')) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Azione eseguita!'), duration: Duration(milliseconds: 300)));
      }
      await Future.delayed(const Duration(milliseconds: 300));
      fetchState();
    } catch (e) {}
  }

  Future<void> saveAll() async {
    if (activePage == 'totals') return;

    List<Future> futures = [];
    for (var t in teams) {
      int id = t['id'];
      
      String currentScore = scoreCtrls[id]?.text ?? "0";
      if (currentScore.isEmpty) currentScore = "0";
      if (currentScore != savedScores[id]) {
        futures.add(http.post(Uri.parse('${Uri.base.origin}/api/score?game=$currentGameIndex&team=$id&points=$currentScore')));
      }
      
      String currentPartial = partialCtrls[id]?.text ?? "";
      if (currentPartial != savedPartials[id]) {
        String encodedVal = Uri.encodeComponent(currentPartial);
        futures.add(http.post(Uri.parse('${Uri.base.origin}/api/partial?game=$currentGameIndex&team=$id&value=$encodedVal')));
      }
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tutte le modifiche salvate!'), backgroundColor: Colors.green));
      fetchState(); 
    }
  }

  Future<void> confirmAndSend(String title, String content, String endpoint) async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(color: Colors.red)),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Conferma')),
        ],
      )
    ) ?? false;
    if (confirm) await sendCommand(endpoint);
  }

  Future<void> _pickColor() async {
    final List<Color> palette = [
      Colors.white, Colors.red, Colors.pink, Colors.purple, Colors.deepPurple, Colors.indigo,
      Colors.blue, Colors.lightBlue, Colors.cyan, Colors.teal, Colors.green,
      Colors.lightGreen, Colors.lime, Colors.yellow, Colors.amber, Colors.orange,
      Colors.deepOrange, Colors.brown, Colors.grey, Colors.blueGrey, Colors.black
    ];
    Color? picked = await showDialog<Color>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scegli colore'),
        content: Wrap(
          spacing: 10, runSpacing: 10,
          children: palette.map((c) => GestureDetector(
            onTap: () => Navigator.pop(ctx, c),
            child: Container(width: 50, height: 50, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.black38, width: 2)))
          )).toList(),
        ),
      )
    );
    if (picked != null) setState(() => selectedTeamColor = picked);
  }

  String _colorToHex(Color c) => '#${c.value.toRadixString(16).substring(2).toUpperCase()}';
  
  String get formattedTimer {
    String m = (timerSeconds ~/ 60).toString().padLeft(2, '0');
    String s = (timerSeconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  // --- MODIFICATA: Calcola il punteggio in base alla vista attuale ---
  int _getScoreForCurrentView(int teamId, bool isTotalsView) {
    if (isTotalsView) {
      int total = 0;
      for (var g in games) {
        if (g['scores'] != null && g['scores'][teamId.toString()] != null) {
          total += (g['scores'][teamId.toString()] as num).toInt();
        }
      }
      return total;
    } else {
      var currentGame = games.firstWhere((g) => g['id'] == currentGameIndex, orElse: () => null);
      if (currentGame != null && currentGame['scores'] != null && currentGame['scores'][teamId.toString()] != null) {
         return (currentGame['scores'][teamId.toString()] as num).toInt();
      }
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isTotalsView = activePage == 'totals';
    bool hasUnsavedChanges = false;
    if (!isTotalsView) {
      for (var t in teams) {
        int id = t['id'];
        String cs = scoreCtrls[id]?.text ?? "0";
        if (cs.isEmpty) cs = "0";
        if (cs != savedScores[id]) hasUnsavedChanges = true;
        if ((partialCtrls[id]?.text ?? "") != savedPartials[id]) hasUnsavedChanges = true;
      }
    }

    // --- MODIFICATA: L'anteprima si adatta a Totali O Gioco Corrente ---
    List<Map<String, dynamic>> sortedTeams = [];
    if (teams.isNotEmpty) {
      sortedTeams = List.from(teams);
      sortedTeams.sort((a, b) {
        int scoreA = _getScoreForCurrentView(a['id'], isTotalsView);
        int scoreB = _getScoreForCurrentView(b['id'], isTotalsView);
        return scoreA.compareTo(scoreB);
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('🕹️ Telecomando PC'), backgroundColor: Colors.blueGrey, actions: [
        isStreamingActive 
        ? IconButton(
            icon: const Icon(Icons.videocam_off, color: Colors.redAccent),
            tooltip: 'Forza chiusura Diretta',
            onPressed: () => confirmAndSend('🛑 Stop Streaming', 'Forzare la chiusura dello streaming video attivo?', '/api/stream/stop')
          )
        : IconButton(
            icon: const Icon(Icons.videocam, color: Colors.amberAccent), 
            tooltip: 'Avvia Diretta Video',
            onPressed: () async {
              final url = Uri.parse('${Uri.base.origin}/stream_broadcaster.html');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            }
          ),
        IconButton(icon: const Icon(Icons.refresh), onPressed: fetchState)
      ]),
      bottomNavigationBar: isTotalsView ? null : Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))],
        ),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: hasUnsavedChanges ? Colors.green : Colors.grey.shade400,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 20),
            minimumSize: const Size(double.infinity, 60),
          ),
          icon: Icon(hasUnsavedChanges ? Icons.save : Icons.check_circle, size: 28),
          label: Text(
            hasUnsavedChanges ? 'SALVA TUTTE LE MODIFICHE' : 'TUTTO SALVATO', 
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1)
          ),
          onPressed: hasUnsavedChanges ? saveAll : null,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('📺 VISTA TABELLONE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: activePage == 'totals' ? Colors.blue : Colors.white, foregroundColor: activePage == 'totals' ? Colors.white : Colors.black),
                onPressed: () => sendCommand('/api/navigate?page=totals'), 
                child: const Text('🏆 Totali')
              ),
              ...games.map((g) {
                bool isActive = activePage == g['id'].toString();
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: isActive ? Colors.blue : Colors.white, foregroundColor: isActive ? Colors.white : Colors.black),
                  onPressed: () => sendCommand('/api/navigate?page=${g['id']}'), 
                  child: Text(g['name'])
                );
              }),
            ],
          ),
          const Divider(height: 30, thickness: 2),

          Text(isTotalsView ? '🛑 MODIFICHE DISABILITATE NEI TOTALI' : '🎮 ASSEGNA PUNTI E PARZIALI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isTotalsView ? Colors.red : Colors.black)),
          if (games.isNotEmpty) DropdownButton<int>(
            value: currentGameIndex,
            isExpanded: true,
            items: games.map<DropdownMenuItem<int>>((g) => DropdownMenuItem<int>(value: g['id'], child: Text('Modificando: ${g['name']}'))).toList(),
            onChanged: (val) {
              setState(() {
                currentGameIndex = val!;
                fetchState(); 
              });
              sendCommand('/api/navigate?page=$val');
            },
          ),
          const SizedBox(height: 15),

          if (teams.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: teams.map((team) {
                  int teamId = team['id'];
                  bool hasUsedJolly = team['hasUsedJolly'] == true;
                  Color teamColor = Colors.white;
                  try { teamColor = Color(int.parse(team['colorHex'].substring(1), radix: 16) + 0xFF000000); } catch (e) {}

                  String currentScore = scoreCtrls[teamId]?.text ?? "0";
                  if (currentScore.isEmpty) currentScore = "0";
                  bool isScoreSaved = currentScore == savedScores[teamId];
                  bool isPartialSaved = (partialCtrls[teamId]?.text ?? "") == savedPartials[teamId];

                  return Container(
                    width: 160, 
                    margin: const EdgeInsets.only(right: 12, bottom: 15),
                    child: Card(
                      color: teamColor.withOpacity(0.15), 
                      shape: RoundedRectangleBorder(side: BorderSide(color: teamColor, width: 2), borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.all(10.0), 
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(child: Text(team['name'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red, size: 20), 
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => confirmAndSend('Elimina Squadra', 'Vuoi eliminare ${team['name']}?', '/api/delete/team?id=$teamId')
                                )
                              ],
                            ),
                            const SizedBox(height: 4),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: hasUsedJolly ? Colors.grey : Colors.orange, 
                                foregroundColor: hasUsedJolly ? Colors.white70 : Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0) 
                              ), 
                              onPressed: isTotalsView ? null : () {
                                    if (hasUsedJolly) confirmAndSend('❌ ANNULLA', 'Vuoi annullare l\'uso del Jolly?', '/api/jolly/revoke?team=$teamId');
                                    else confirmAndSend('🌟 GIOCA JOLLY', 'Giocare il Jolly per questa squadra?', '/api/jolly?game=$currentGameIndex&team=$teamId');
                                }, 
                              child: Text(hasUsedJolly ? 'Usato' : '🌟 Jolly', style: const TextStyle(fontSize: 13))
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: scoreCtrls[teamId], 
                              readOnly: isTotalsView, 
                              keyboardType: TextInputType.number, 
                              onChanged: (val) => setState(() {}),
                              style: TextStyle(
                                color: isScoreSaved ? Colors.black : Colors.grey.shade600,
                                fontWeight: isScoreSaved ? FontWeight.normal : FontWeight.bold,
                                fontStyle: isScoreSaved ? FontStyle.normal : FontStyle.italic
                              ),
                              decoration: InputDecoration(
                                labelText: 'Punti', 
                                isDense: true, 
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                border: const OutlineInputBorder(), 
                                filled: true, 
                                fillColor: isTotalsView ? Colors.grey.shade300 : Colors.white
                              )
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: partialCtrls[teamId], 
                              readOnly: isTotalsView, 
                              onChanged: (val) => setState(() {}),
                              style: TextStyle(
                                color: isPartialSaved ? Colors.black : Colors.grey.shade600,
                                fontWeight: isPartialSaved ? FontWeight.normal : FontWeight.bold,
                                fontStyle: isPartialSaved ? FontStyle.normal : FontStyle.italic
                              ),
                              decoration: InputDecoration(
                                labelText: 'Note', 
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                border: const OutlineInputBorder(), 
                                filled: true, 
                                fillColor: isTotalsView ? Colors.grey.shade300 : Colors.white
                              )
                            )
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

          const Divider(height: 40, thickness: 2),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Card(
                  color: Colors.amber.shade50,
                  shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.orange, width: 2), borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('⏳ MOSTRA COUNTDOWN', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                          subtitle: const Text('Nasconde la classifica e mostra il timer.'),
                          value: isTimerVisible,
                          activeColor: Colors.deepOrange,
                          onChanged: (val) => sendCommand('/api/timer/visibility?show=$val'),
                        ),
                        const Divider(),
                        Text(formattedTimer, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                              icon: const Icon(Icons.play_arrow), label: const Text('Start'),
                              onPressed: isTimerRunning ? null : () => sendCommand('/api/timer/start')
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                              icon: const Icon(Icons.stop), label: const Text('Stop'),
                              onPressed: !isTimerRunning ? null : () => sendCommand('/api/timer/stop')
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey, foregroundColor: Colors.white),
                              icon: const Icon(Icons.refresh), label: const Text('Reset'),
                              onPressed: () => sendCommand('/api/timer/reset')
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: TextField(controller: timerMinCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minuti', isDense: true))),
                            const SizedBox(width: 10),
                            Expanded(child: TextField(controller: timerSecCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Secondi', isDense: true))),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: () => sendCommand('/api/timer/set?m=${timerMinCtrl.text}&s=${timerSecCtrl.text}'),
                              child: const Text('Imposta')
                            )
                          ],
                        )
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              
              if (teams.isNotEmpty) 
                Expanded(
                  child: Card(
                    color: Colors.purple.shade50,
                    shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.purple, width: 2), borderRadius: BorderRadius.circular(10)),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SwitchListTile(
                            title: const Text('🎭 MODALITÀ ANNUNCIO', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
                            subtitle: const Text('Riordina la classifica e oscura le squadre sul tabellone.'),
                            value: isRevealMode,
                            activeColor: Colors.purple,
                            onChanged: (val) => sendCommand('/api/reveal/toggle?enable=$val'),
                          ),
                          if (isRevealMode) ...[
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                                  icon: const Icon(Icons.visibility_off), label: const Text('Nascondi (-1)'),
                                  onPressed: () => sendCommand('/api/reveal/prev')
                                ),
                                Text('$revealedTeamsCount / ${teams.length}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
                                  icon: const Icon(Icons.visibility), label: const Text('Rivela (+1)'),
                                  onPressed: () => sendCommand('/api/reveal/next')
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            const Text("Anteprima Annunciatore:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
                            const SizedBox(height: 8),
                            Column(
                              children: List.generate(sortedTeams.length, (index) {
                                var team = sortedTeams[index];
                                int rank = sortedTeams.length - index;
                                int score = _getScoreForCurrentView(team['id'], isTotalsView);
                                bool isRevealed = index < revealedTeamsCount;
                                
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 5),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isRevealed ? Colors.white : Colors.grey.shade300,
                                    border: Border.all(color: isRevealed ? Colors.green : Colors.grey),
                                    borderRadius: BorderRadius.circular(5)
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text("$rank° - ${team['name']}", style: TextStyle(
                                        fontWeight: isRevealed ? FontWeight.bold : FontWeight.normal,
                                        color: isRevealed ? Colors.black : Colors.grey.shade600
                                      )),
                                      Row(
                                        children: [
                                          Text("$score pt", style: TextStyle(fontWeight: FontWeight.bold, color: isRevealed ? Colors.blue.shade800 : Colors.grey)),
                                          const SizedBox(width: 10),
                                          Icon(
                                            isRevealed ? Icons.visibility : Icons.visibility_off, 
                                            color: isRevealed ? Colors.green : Colors.grey,
                                            size: 18,
                                          )
                                        ],
                                      )
                                    ],
                                  ),
                                );
                              }),
                            )
                          ]
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),

          const Divider(height: 40, thickness: 2),

          const Text('⚙️ IMPOSTAZIONI EVENTO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 10),
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  const Text('🏆 Evento: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(child: TextField(controller: eventNameCtrl, decoration: const InputDecoration(hintText: 'Titolo...'))),
                  ElevatedButton(onPressed: () => sendCommand('/api/event?name=${eventNameCtrl.text}'), child: const Text('Salva'))
                ],
              ),
            ),
          ),
          Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(child: TextField(controller: newGameNameCtrl, decoration: const InputDecoration(hintText: 'Nome Nuovo Gioco...'))),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                    icon: const Icon(Icons.add_circle), label: const Text('Aggiungi Gioco'),
                    onPressed: () {
                      sendCommand('/api/game?name=${newGameNameCtrl.text}');
                      newGameNameCtrl.clear();
                    }
                  )
                ],
              ),
            ),
          ),
          Card(
            color: Colors.blueGrey.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(child: TextField(controller: newTeamNameCtrl, decoration: const InputDecoration(hintText: 'Nuova Squadra...'))),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: _pickColor,
                    child: Container(width: 40, height: 40, decoration: BoxDecoration(color: selectedTeamColor, shape: BoxShape.circle, border: Border.all(color: Colors.black38, width: 2))),
                  ),
                  const SizedBox(width: 10),
                  IconButton(icon: const Icon(Icons.add_circle, color: Colors.blueGrey), onPressed: () {
                    sendCommand('/api/team?name=${newTeamNameCtrl.text}&color=${_colorToHex(selectedTeamColor).replaceAll('#', '%23')}');
                    newTeamNameCtrl.clear();
                  })
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          Card(
            color: Colors.red.shade50,
            shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.red, width: 2), borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('⚠️ ZONA PERICOLOSA', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18), textAlign: TextAlign.center),
                  const SizedBox(height: 15),
                  if (games.isNotEmpty) ...[
                    OutlinedButton.icon(icon: const Icon(Icons.delete_sweep, color: Colors.red), label: const Text('Elimina gioco selezionato', style: TextStyle(color: Colors.red)), onPressed: () => confirmAndSend('Elimina Gioco', 'Eliminare questo gioco?', '/api/delete/game?id=$currentGameIndex')),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(icon: const Icon(Icons.exposure_zero, color: Colors.deepOrange), label: const Text('Azzera punti del gioco', style: TextStyle(color: Colors.deepOrange)), onPressed: () => confirmAndSend('Azzera Punteggi', 'Azzera i punti del gioco?', '/api/reset/game?id=$currentGameIndex')),
                  ],
                  const Divider(height: 30, color: Colors.red),
                  ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.all(15)), icon: const Icon(Icons.warning), label: const Text('RESET TOTALE EVENTO', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), onPressed: () => confirmAndSend('RESET TOTALE', 'Questo cancellerà TUTTO. Sei sicuro?', '/api/reset/all'))
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}