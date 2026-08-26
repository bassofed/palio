import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'web_helper.dart';

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

  Color selectedTeamColor = Colors.white;
  
  final TextEditingController eventNameCtrl = TextEditingController();
  final TextEditingController newTeamNameCtrl = TextEditingController();
  final TextEditingController newGameNameCtrl = TextEditingController();

  Map<int, TextEditingController> scoreCtrls = {};
  Map<int, TextEditingController> partialCtrls = {};

  @override
  void initState() {
    super.initState();
    fetchState();
  }

  Future<void> fetchState() async {
    try {
      final url = Uri.parse('${Uri.base.origin}/api/state');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          eventName = data['eventName'];
          eventNameCtrl.text = eventName;
          activePage = data['currentPage'];
          isRevealMode = data['isRevealMode'] ?? false;
          revealedTeamsCount = data['revealedTeamsCount'] ?? 0;
          teams = data['teams'];
          games = data['games'];
          
          for (var t in teams) {
            int id = t['id'];
            if (!scoreCtrls.containsKey(id)) scoreCtrls[id] = TextEditingController();
            if (!partialCtrls.containsKey(id)) partialCtrls[id] = TextEditingController();
          }
          
          if (activePage != 'totals') {
            int? pageIndex = int.tryParse(activePage);
            if (pageIndex != null && games.any((g) => g['id'] == pageIndex)) {
              currentGameIndex = pageIndex;
            }
          } else if (games.isNotEmpty && !games.any((g) => g['id'] == currentGameIndex)) {
            currentGameIndex = games.first['id'];
          }
        });
      }
    } catch (e) {}
  }

  Future<void> sendCommand(String endpoint) async {
    final url = Uri.parse('${Uri.base.origin}$endpoint');
    try {
      await http.post(url);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Azione eseguita!'), duration: Duration(milliseconds: 300)));
      if (endpoint.contains('/team') || endpoint.contains('/game') || endpoint.contains('/reset') || endpoint.contains('/event') || endpoint.contains('/navigate') || endpoint.contains('/jolly') || endpoint.contains('/reveal')) {
        await Future.delayed(const Duration(milliseconds: 300));
        fetchState();
      }
    } catch (e) {}
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
            child: Container(
              width: 50, height: 50,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.black38, width: 2))
            )
          )).toList(),
        ),
      )
    );
    if (picked != null) setState(() => selectedTeamColor = picked);
  }

  String _colorToHex(Color c) => '#${c.value.toRadixString(16).substring(2).toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    bool isTotalsView = activePage == 'totals';

    return Scaffold(
      appBar: AppBar(title: const Text('🕹️ Telecomando'), backgroundColor: Colors.blueGrey, actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: fetchState)]),
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
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                icon: const Icon(Icons.videocam),
                label: const Text('🔴 Streaming Live'),
                onPressed: () {
                  // Reindirizza l'utente alla pagina dedicata per la trasmissione
                  redirectToBroadcaster(Uri.base.origin);
                },
              ),
            ],
          ),
          const Divider(height: 30, thickness: 2),

          // --- MODALITÀ ANNUNCIO (SUSPENSE) ---
          if (teams.isNotEmpty) ...[
            Card(
              color: Colors.purple.shade50,
              shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.purple, width: 2), borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('🎭 MODALITÀ ANNUNCIO (Classifica Rivelata)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
                      subtitle: const Text('Nasconde le squadre e le riordina dall\'ultima alla prima.'),
                      value: isRevealMode,
                      activeColor: Colors.purple,
                      onChanged: (val) => sendCommand('/api/reveal/toggle?enable=$val'),
                    ),
                    if (isRevealMode)
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
                      )
                  ],
                ),
              ),
            ),
            const Divider(height: 30, thickness: 2),
          ],

          Text(isTotalsView ? '🛑 MODIFICHE DISABILITATE NEI TOTALI' : '🎮 ASSEGNA PUNTI E PARZIALI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isTotalsView ? Colors.red : Colors.black)),
          if (games.isNotEmpty) DropdownButton<int>(
            value: currentGameIndex,
            isExpanded: true,
            items: games.map<DropdownMenuItem<int>>((g) => DropdownMenuItem<int>(value: g['id'], child: Text('Modificando: ${g['name']}'))).toList(),
            onChanged: (val) {
              setState(() {
                currentGameIndex = val!;
                for (var controller in scoreCtrls.values) controller.clear();
                for (var controller in partialCtrls.values) controller.clear();
              });
              sendCommand('/api/navigate?page=$val');
            },
          ),
          const SizedBox(height: 10),

          ...teams.map((team) {
            int teamId = team['id'];
            bool hasUsedJolly = team['hasUsedJolly'] == true;
            Color teamColor = Colors.white;
            try { teamColor = Color(int.parse(team['colorHex'].substring(1), radix: 16) + 0xFF000000); } catch (e) {}

            return Card(
              color: teamColor.withOpacity(0.15), 
              shape: RoundedRectangleBorder(side: BorderSide(color: teamColor, width: 2), borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.only(bottom: 15),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(team['name'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                        Row(
                          children: [
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: hasUsedJolly ? Colors.grey : Colors.orange,
                                foregroundColor: hasUsedJolly ? Colors.white70 : Colors.white,
                              ), 
                              onPressed: isTotalsView 
                                ? null 
                                : () {
                                    if (hasUsedJolly) {
                                      confirmAndSend('❌ ANNULLA JOLLY', 'Vuoi annullare l\'uso del Jolly per ${team['name']}?', '/api/jolly/revoke?team=$teamId');
                                    } else {
                                      confirmAndSend('🌟 GIOCA JOLLY', 'Sei sicuro di giocare il Jolly per ${team['name']}?', '/api/jolly?game=$currentGameIndex&team=$teamId');
                                    }
                                }, 
                              child: Text(hasUsedJolly ? 'Jolly Usato' : '🌟 Jolly')
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red), 
                              onPressed: () => confirmAndSend('Elimina Squadra', 'Vuoi eliminare ${team['name']}?', '/api/delete/team?id=$teamId')
                            )
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: TextField(
                          controller: scoreCtrls[teamId], 
                          readOnly: isTotalsView,
                          keyboardType: TextInputType.number, 
                          decoration: InputDecoration(labelText: 'Punti', border: const OutlineInputBorder(), filled: true, fillColor: isTotalsView ? Colors.grey.shade300 : Colors.white)
                        )),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15)),
                          onPressed: isTotalsView ? null : () {
                            String pts = scoreCtrls[teamId]!.text.isEmpty ? "0" : scoreCtrls[teamId]!.text;
                            sendCommand('/api/score?game=$currentGameIndex&team=$teamId&points=$pts');
                          }, 
                          child: const Text('Salva Punti')
                        )
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: TextField(
                          controller: partialCtrls[teamId], 
                          readOnly: isTotalsView,
                          decoration: InputDecoration(labelText: 'Misura / Note libere', border: const OutlineInputBorder(), filled: true, fillColor: isTotalsView ? Colors.grey.shade300 : Colors.white)
                        )),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15)),
                          onPressed: isTotalsView ? null : () => sendCommand('/api/partial?game=$currentGameIndex&team=$teamId&value=${partialCtrls[teamId]!.text}'), 
                          child: const Text('Salva Misura')
                        )
                      ],
                    )
                  ],
                ),
              ),
            );
          }),

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
                    icon: const Icon(Icons.add_circle),
                    label: const Text('Aggiungi Gioco'),
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