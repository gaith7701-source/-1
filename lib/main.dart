import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as pathHelper;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MuthakkaratiApp());
}

const kPrimary = Color(0xFF6C63FF);
const kAccent = Color(0xFFFF6584);

const List<Color> kSubjectColors = [
  Color(0xFF6C63FF), Color(0xFFFF6584), Color(0xFF43BCCD),
  Color(0xFFFFB347), Color(0xFF77DD77), Color(0xFFFF6961),
  Color(0xFF836FFF), Color(0xFF00B4D8),
];

const List<String> kDays = ['الأحد','الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت'];

// ===== APP =====
class MuthakkaratiApp extends StatelessWidget {
  const MuthakkaratiApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مذكرتي المدرسية',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: kPrimary), useMaterial3: true),
      darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: kPrimary, brightness: Brightness.dark), useMaterial3: true),
      themeMode: ThemeMode.system,
      home: const SplashScreen(),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
    );
  }
}

// ===== DATABASE =====
class DBHelper {
  static Database? _db;
  static Future<Database> get db async { _db ??= await _initDB(); return _db!; }

  static Future<Database> _initDB() async {
    final p = pathHelper.join(await getDatabasesPath(), 'muthakkarati.db');
    return openDatabase(p, version: 1, onCreate: (db, v) async {
      await db.execute('CREATE TABLE subjects (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, teacher TEXT, color INTEGER NOT NULL DEFAULT 4280391411)');
      await db.execute('CREATE TABLE schedule (id INTEGER PRIMARY KEY AUTOINCREMENT, subject_id INTEGER, day_index INTEGER NOT NULL, start_time TEXT NOT NULL, end_time TEXT NOT NULL, teacher TEXT)');
      await db.execute('CREATE TABLE lessons (id INTEGER PRIMARY KEY AUTOINCREMENT, subject_id INTEGER NOT NULL, title TEXT NOT NULL, content TEXT, date TEXT NOT NULL)');
      await db.execute('CREATE TABLE homework (id INTEGER PRIMARY KEY AUTOINCREMENT, subject_id INTEGER NOT NULL, description TEXT NOT NULL, due_date TEXT NOT NULL, is_done INTEGER DEFAULT 0)');
      await db.execute('CREATE TABLE exams (id INTEGER PRIMARY KEY AUTOINCREMENT, subject_id INTEGER NOT NULL, title TEXT NOT NULL, exam_date TEXT NOT NULL, topics TEXT, grade REAL)');
      await db.execute('CREATE TABLE ai_chat (id INTEGER PRIMARY KEY AUTOINCREMENT, role TEXT NOT NULL, content TEXT NOT NULL, timestamp TEXT NOT NULL)');
    });
  }

  static Future<int> insertSubject(Map<String, dynamic> d) async => (await db).insert('subjects', d);
  static Future<List<Map<String, dynamic>>> getSubjects() async => (await db).query('subjects');
  static Future<int> deleteSubject(int id) async => (await db).delete('subjects', where: 'id=?', whereArgs: [id]);

  static Future<int> insertSchedule(Map<String, dynamic> d) async => (await db).insert('schedule', d);
  static Future<List<Map<String, dynamic>>> getScheduleForDay(int day) async => (await db).rawQuery('SELECT s.*, sub.name as subject_name, sub.color as subject_color, sub.teacher as sub_teacher FROM schedule s LEFT JOIN subjects sub ON s.subject_id=sub.id WHERE s.day_index=? ORDER BY s.start_time', [day]);
  static Future<List<Map<String, dynamic>>> getAllSchedule() async => (await db).rawQuery('SELECT s.*, sub.name as subject_name, sub.color as subject_color FROM schedule s LEFT JOIN subjects sub ON s.subject_id=sub.id ORDER BY s.day_index, s.start_time');
  static Future<int> deleteSchedule(int id) async => (await db).delete('schedule', where: 'id=?', whereArgs: [id]);

  static Future<int> insertLesson(Map<String, dynamic> d) async => (await db).insert('lessons', d);
  static Future<List<Map<String, dynamic>>> getLessonsForSubject(int sid) async => (await db).query('lessons', where: 'subject_id=?', whereArgs: [sid], orderBy: 'date DESC');
  static Future<List<Map<String, dynamic>>> getAllLessons() async => (await db).rawQuery('SELECT l.*, sub.name as subject_name FROM lessons l LEFT JOIN subjects sub ON l.subject_id=sub.id ORDER BY l.date DESC');

  static Future<int> insertHomework(Map<String, dynamic> d) async => (await db).insert('homework', d);
  static Future<List<Map<String, dynamic>>> getHomework({bool pending = false}) async => (await db).rawQuery('SELECT h.*, sub.name as subject_name, sub.color as subject_color FROM homework h LEFT JOIN subjects sub ON h.subject_id=sub.id ${pending ? "WHERE h.is_done=0" : ""} ORDER BY h.due_date ASC');
  static Future<int> updateHomeworkStatus(int id, bool v) async => (await db).update('homework', {'is_done': v ? 1 : 0}, where: 'id=?', whereArgs: [id]);
  static Future<int> deleteHomework(int id) async => (await db).delete('homework', where: 'id=?', whereArgs: [id]);

  static Future<int> insertExam(Map<String, dynamic> d) async => (await db).insert('exams', d);
  static Future<List<Map<String, dynamic>>> getExams() async => (await db).rawQuery('SELECT e.*, sub.name as subject_name, sub.color as subject_color FROM exams e LEFT JOIN subjects sub ON e.subject_id=sub.id ORDER BY e.exam_date ASC');
  static Future<int> deleteExam(int id) async => (await db).delete('exams', where: 'id=?', whereArgs: [id]);

  static Future<int> insertAIMsg(Map<String, dynamic> d) async => (await db).insert('ai_chat', d);
  static Future<List<Map<String, dynamic>>> getAIChat() async => (await db).query('ai_chat', orderBy: 'timestamp ASC');
  static Future<void> clearAIChat() async => (await db).delete('ai_chat');
}

class Subject {
  final int? id; final String name; final String? teacher; final int color;
  Subject({this.id, required this.name, this.teacher, this.color = 0xFF6C63FF});
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'teacher': teacher, 'color': color};
  factory Subject.fromMap(Map<String, dynamic> m) => Subject(id: m['id'], name: m['name'], teacher: m['teacher'], color: m['color'] ?? 0xFF6C63FF);
}

// ===== SPLASH =====
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}
class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _a = CurvedAnimation(parent: _c, curve: Curves.easeIn);
    _c.forward();
    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => prefs.getBool('is_setup') == true ? const MainApp() : const SetupScreen()));
    });
  }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kPrimary,
    body: FadeTransition(opacity: _a, child: const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.menu_book_rounded, size: 80, color: Colors.white),
      SizedBox(height: 20),
      Text('مذكّرتي المدرسية', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
      SizedBox(height: 8),
      Text('مساعدك الدراسي الشخصي', style: TextStyle(fontSize: 16, color: Colors.white70)),
    ]))),
  );
}

// ===== SETUP =====
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override State<SetupScreen> createState() => _SetupScreenState();
}
class _SetupScreenState extends State<SetupScreen> {
  final _n = TextEditingController(), _g = TextEditingController(), _s = TextEditingController();
  @override void dispose() { _n.dispose(); _g.dispose(); _s.dispose(); super.dispose(); }
  Future<void> _finish() async {
    if (_n.text.trim().isEmpty || _g.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الرجاء إدخال الاسم والصف'))); return; }
    final p = await SharedPreferences.getInstance();
    await p.setString('student_name', _n.text.trim());
    await p.setString('student_grade', _g.text.trim());
    await p.setString('student_school', _s.text.trim());
    await p.setBool('is_setup', true);
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainApp()));
  }
  Widget _field(String label, TextEditingController c, IconData icon) => TextField(
    controller: c, style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: Colors.white70), prefixIcon: Icon(icon, color: Colors.white70),
      enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white30), borderRadius: BorderRadius.all(Radius.circular(12))),
      focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white), borderRadius: BorderRadius.all(Radius.circular(12)))),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [kPrimary, Color(0xFF4A47A3)])),
      child: SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 40),
        const Icon(Icons.menu_book_rounded, size: 60, color: Colors.white),
        const SizedBox(height: 20),
        const Text('مرحباً بك!', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
        const Text('أدخل بياناتك للبدء', style: TextStyle(fontSize: 18, color: Colors.white70)),
        const SizedBox(height: 40),
        _field('الاسم الكامل *', _n, Icons.person),
        const SizedBox(height: 16),
        _field('الصف الدراسي *', _g, Icons.school),
        const SizedBox(height: 16),
        _field('المدرسة (اختياري)', _s, Icons.account_balance),
        const Spacer(),
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _finish,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kPrimary, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('ابدأ الآن', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        )),
      ]))),
    ),
  );
}

// ===== MAIN APP =====
class MainApp extends StatefulWidget {
  const MainApp({super.key});
  @override State<MainApp> createState() => _MainAppState();
}
class _MainAppState extends State<MainApp> {
  int _idx = 0;
  final _screens = const [HomeScreen(), ScheduleScreen(), SubjectsScreen(), HomeworkScreen(), AIChatScreen()];
  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _idx, children: _screens),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _idx,
      onDestinationSelected: (i) => setState(() => _idx = i),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
        NavigationDestination(icon: Icon(Icons.calendar_today_outlined), selectedIcon: Icon(Icons.calendar_today), label: 'الجدول'),
        NavigationDestination(icon: Icon(Icons.book_outlined), selectedIcon: Icon(Icons.book), label: 'المواد'),
        NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: 'الواجبات'),
        NavigationDestination(icon: Icon(Icons.psychology_outlined), selectedIcon: Icon(Icons.psychology), label: 'المساعد'),
      ],
    ),
  );
}

// ===== HOME SCREEN =====
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  String _name = '', _grade = '';
  List<Map<String, dynamic>> _today = [], _hw = [], _exams = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final today = DateTime.now().weekday % 7;
    final ts = await DBHelper.getScheduleForDay(today);
    final hw = await DBHelper.getHomework(pending: true);
    final ex = await DBHelper.getExams();
    final now = DateTime.now();
    final upEx = ex.where((e) { try { final d = DateTime.parse(e['exam_date']); return d.isAfter(now) && d.isBefore(now.add(const Duration(days: 14))); } catch(_){return false;} }).toList();
    if (mounted) setState(() { _name = p.getString('student_name') ?? ''; _grade = p.getString('student_grade') ?? ''; _today = ts; _hw = hw.take(3).toList(); _exams = upEx.take(3).toList(); _loading = false; });
  }

  String get _greeting { final h = DateTime.now().hour; if (h < 12) return 'صباح الخير'; if (h < 17) return 'مساء الخير'; return 'مساء النور'; }
  String get _dayName => kDays[DateTime.now().weekday % 7];

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          SliverAppBar(
            expandedHeight: 180, pinned: true,
            flexibleSpace: FlexibleSpaceBar(background: Container(
              decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [kPrimary, Color(0xFF4A47A3)])),
              child: SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('$_greeting، $_name', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 4),
                Text('$_dayName | الصف: $_grade', style: const TextStyle(fontSize: 14, color: Colors.white70)),
                const SizedBox(height: 8),
                Row(children: [
                  _chip(Icons.class_outlined, '${_today.length} حصص'),
                  const SizedBox(width: 8),
                  _chip(Icons.assignment_outlined, '${_hw.length} واجبات'),
                ]),
              ]))),
            )),
          ),
          SliverPadding(padding: const EdgeInsets.all(16), sliver: SliverList(delegate: SliverChildListDelegate([
            _sec('📚 حصص اليوم'),
            const SizedBox(height: 8),
            if (_today.isEmpty) _empty('لا توجد حصص اليوم 🎉')
            else ..._today.map((s) => _schedCard(s)),
            const SizedBox(height: 16),
            _sec('📝 واجبات قريبة'),
            const SizedBox(height: 8),
            if (_hw.isEmpty) _empty('لا توجد واجبات معلقة ✓')
            else ..._hw.map((h) => _hwCard(h)),
            const SizedBox(height: 16),
            _sec('📅 امتحانات قادمة'),
            const SizedBox(height: 8),
            if (_exams.isEmpty) _empty('لا توجد امتحانات قريبة')
            else ..._exams.map((e) => _exCard(e)),
            const SizedBox(height: 80),
          ]))),
        ]),
      ),
    );
  }

  Widget _chip(IconData icon, String t) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: Colors.white), const SizedBox(width: 4), Text(t, style: const TextStyle(color: Colors.white, fontSize: 12))]));
  Widget _sec(String t) => Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold));
  Widget _empty(String t) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(t, style: TextStyle(color: Colors.grey[600]))));
  Widget _schedCard(Map<String, dynamic> s) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(leading: Container(width: 4, height: 40, decoration: BoxDecoration(color: Color(s['subject_color'] ?? 0xFF6C63FF), borderRadius: BorderRadius.circular(2))), title: Text(s['subject_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text('${s['start_time']} - ${s['end_time']}')));
  Widget _hwCard(Map<String, dynamic> h) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(leading: CircleAvatar(backgroundColor: Color(h['subject_color'] ?? 0xFF6C63FF), radius: 6), title: Text(h['description'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text(h['subject_name'] ?? ''), trailing: Text(h['due_date'] ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 12))));
  Widget _exCard(Map<String, dynamic> e) { int d = 0; try { d = DateTime.parse(e['exam_date']).difference(DateTime.now()).inDays; } catch(_){} return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(leading: const Icon(Icons.quiz_outlined, color: kAccent), title: Text(e['subject_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(e['title'] ?? ''), trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: (d <= 3 ? kAccent : kPrimary).withOpacity(0.15), borderRadius: BorderRadius.circular(12)), child: Text('بعد $d أيام', style: TextStyle(color: d <= 3 ? kAccent : kPrimary, fontSize: 12, fontWeight: FontWeight.bold))))); }
}

// ===== SCHEDULE SCREEN =====
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});
  @override State<ScheduleScreen> createState() => _ScheduleScreenState();
}
class _ScheduleScreenState extends State<ScheduleScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<List<Map<String, dynamic>>> _sched = List.generate(7, (_) => []);
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 7, vsync: this, initialIndex: DateTime.now().weekday % 7);
    _load();
  }
  @override void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    final all = await DBHelper.getAllSchedule();
    final s = List.generate(7, (_) => <Map<String, dynamic>>[]);
    for (final x in all) { final d = x['day_index'] as int; if (d >= 0 && d < 7) s[d].add(x); }
    if (mounted) setState(() { _sched = s; _loading = false; });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الجدول الأسبوعي'), bottom: TabBar(controller: _tab, isScrollable: true, tabs: kDays.map((d) => Tab(text: d.substring(0, 2))).toList())),
    body: _loading ? const Center(child: CircularProgressIndicator()) : TabBarView(controller: _tab, children: List.generate(7, (di) {
      final ds = _sched[di];
      if (ds.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.event_available, size: 64, color: Colors.grey), const SizedBox(height: 16), Text('لا توجد حصص ${kDays[di]}', style: TextStyle(color: Colors.grey[600]))]));
      return ListView.builder(padding: const EdgeInsets.all(16), itemCount: ds.length, itemBuilder: (ctx, i) {
        final s = ds[i]; final c = Color(s['subject_color'] ?? 0xFF6C63FF);
        return Card(margin: const EdgeInsets.only(bottom: 10), child: IntrinsicHeight(child: Row(children: [
          Container(width: 6, decoration: BoxDecoration(color: c, borderRadius: const BorderRadius.only(topRight: Radius.circular(12), bottomRight: Radius.circular(12)))),
          Expanded(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s['subject_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            Row(children: [const Icon(Icons.access_time, size: 14, color: Colors.grey), const SizedBox(width: 4), Text('${s['start_time']} - ${s['end_time']}', style: TextStyle(color: Colors.grey[600], fontSize: 13))]),
            if ((s['teacher'] ?? '').toString().isNotEmpty) Row(children: [const Icon(Icons.person_outline, size: 14, color: Colors.grey), const SizedBox(width: 4), Text(s['teacher'] ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 13))]),
          ]))),
          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () async { await DBHelper.deleteSchedule(s['id']); _load(); }),
        ])));
      });
    })),
    floatingActionButton: FloatingActionButton.extended(onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddScheduleScreen())); _load(); }, icon: const Icon(Icons.add), label: const Text('إضافة حصة')),
  );
}

// ===== ADD SCHEDULE =====
class AddScheduleScreen extends StatefulWidget {
  const AddScheduleScreen({super.key});
  @override State<AddScheduleScreen> createState() => _AddScheduleScreenState();
}
class _AddScheduleScreenState extends State<AddScheduleScreen> {
  int _day = DateTime.now().weekday % 7; int? _subId;
  String _start = '08:00', _end = '09:00';
  final _tCtrl = TextEditingController();
  List<Subject> _subjects = [];

  @override void initState() { super.initState(); _loadSubs(); }
  @override void dispose() { _tCtrl.dispose(); super.dispose(); }

  Future<void> _loadSubs() async { final s = await DBHelper.getSubjects(); if (mounted) setState(() => _subjects = s.map((x) => Subject.fromMap(x)).toList()); }

  Future<void> _pickTime(bool isStart) async {
    final p = (isStart ? _start : _end).split(':');
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])));
    if (t != null) setState(() { final f = '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}'; if (isStart) _start = f; else _end = f; });
  }

  Future<void> _save() async {
    if (_subId == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر مادة أولاً'))); return; }
    await DBHelper.insertSchedule({'subject_id': _subId, 'day_index': _day, 'start_time': _start, 'end_time': _end, 'teacher': _tCtrl.text.trim()});
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('إضافة حصة'), actions: [TextButton(onPressed: _save, child: const Text('حفظ'))]),
    body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('اليوم', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: List.generate(7, (i) => ChoiceChip(label: Text(kDays[i]), selected: _day == i, onSelected: (_) => setState(() => _day = i)))),
      const SizedBox(height: 20),
      const Text('المادة', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      if (_subjects.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('أضف مواد أولاً من قسم المواد')))
      else DropdownButtonFormField<int>(value: _subId, decoration: const InputDecoration(border: OutlineInputBorder()), hint: const Text('اختر المادة'),
        items: _subjects.map((s) => DropdownMenuItem(value: s.id, child: Row(children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: Color(s.color), shape: BoxShape.circle)), const SizedBox(width: 8), Text(s.name)]))).toList(),
        onChanged: (v) => setState(() => _subId = v)),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('وقت البداية', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 8), GestureDetector(onTap: () => _pickTime(true), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)), child: Text(_start, style: const TextStyle(fontSize: 18))))])),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('وقت النهاية', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 8), GestureDetector(onTap: () => _pickTime(false), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)), child: Text(_end, style: const TextStyle(fontSize: 18))))])),
      ]),
      const SizedBox(height: 20),
      TextField(controller: _tCtrl, decoration: const InputDecoration(labelText: 'اسم الأستاذ (اختياري)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person_outline))),
    ])),
  );
}

// ===== SUBJECTS SCREEN =====
class SubjectsScreen extends StatefulWidget {
  const SubjectsScreen({super.key});
  @override State<SubjectsScreen> createState() => _SubjectsScreenState();
}
class _SubjectsScreenState extends State<SubjectsScreen> {
  List<Subject> _subjects = [];
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { final s = await DBHelper.getSubjects(); if (mounted) setState(() => _subjects = s.map((x) => Subject.fromMap(x)).toList()); }

  void _add() => showDialog(context: context, builder: (ctx) => _AddSubjectDialog(onSaved: _load));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('المواد الدراسية')),
    body: _subjects.isEmpty
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.book_outlined, size: 80, color: Colors.grey), const SizedBox(height: 16), const Text('لا توجد مواد بعد', style: TextStyle(fontSize: 18, color: Colors.grey)), const SizedBox(height: 8), ElevatedButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('إضافة مادة'))]))
        : ListView.builder(padding: const EdgeInsets.all(16), itemCount: _subjects.length, itemBuilder: (ctx, i) {
            final s = _subjects[i];
            return Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(
              leading: CircleAvatar(backgroundColor: Color(s.color), child: Text(s.name.isNotEmpty ? s.name[0] : '؟', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: s.teacher != null && s.teacher!.isNotEmpty ? Text(s.teacher!) : null,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () async { await DBHelper.deleteSubject(s.id!); _load(); }), const Icon(Icons.chevron_left)]),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SubjectDetailScreen(subject: s))).then((_) => _load()),
            ));
          }),
    floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('إضافة مادة')),
  );
}

class _AddSubjectDialog extends StatefulWidget {
  final VoidCallback onSaved;
  const _AddSubjectDialog({required this.onSaved});
  @override State<_AddSubjectDialog> createState() => _AddSubjectDialogState();
}
class _AddSubjectDialogState extends State<_AddSubjectDialog> {
  final _n = TextEditingController(), _t = TextEditingController();
  int _ci = 0;
  @override void dispose() { _n.dispose(); _t.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('إضافة مادة'),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: _n, decoration: const InputDecoration(labelText: 'اسم المادة *', border: OutlineInputBorder()), autofocus: true),
      const SizedBox(height: 12),
      TextField(controller: _t, decoration: const InputDecoration(labelText: 'اسم الأستاذ (اختياري)', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      const Align(alignment: Alignment.centerRight, child: Text('اللون:')),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: List.generate(kSubjectColors.length, (i) => GestureDetector(onTap: () => setState(() => _ci = i), child: Container(width: 32, height: 32, decoration: BoxDecoration(color: kSubjectColors[i], shape: BoxShape.circle, border: _ci == i ? Border.all(color: Colors.black, width: 3) : null))))),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
      ElevatedButton(onPressed: () async {
        if (_n.text.trim().isEmpty) return;
        await DBHelper.insertSubject({'name': _n.text.trim(), 'teacher': _t.text.trim().isNotEmpty ? _t.text.trim() : null, 'color': kSubjectColors[_ci].value});
        if (!mounted) return; Navigator.pop(context); widget.onSaved();
      }, child: const Text('إضافة')),
    ],
  );
}

// ===== SUBJECT DETAIL =====
class SubjectDetailScreen extends StatefulWidget {
  final Subject subject;
  const SubjectDetailScreen({super.key, required this.subject});
  @override State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}
class _SubjectDetailScreenState extends State<SubjectDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _lessons = [], _hw = [], _exams = [];
  @override void initState() { super.initState(); _tab = TabController(length: 3, vsync: this); _load(); }
  @override void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    final l = await DBHelper.getLessonsForSubject(widget.subject.id!);
    final hw = await DBHelper.getHomework();
    final ex = await DBHelper.getExams();
    if (mounted) setState(() { _lessons = l; _hw = hw.where((h) => h['subject_id'] == widget.subject.id).toList(); _exams = ex.where((e) => e['subject_id'] == widget.subject.id).toList(); });
  }

  void _addLesson() { final tc = TextEditingController(), cc = TextEditingController(); showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('إضافة درس'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: tc, decoration: const InputDecoration(labelText: 'عنوان الدرس *', border: OutlineInputBorder())), const SizedBox(height: 12), TextField(controller: cc, maxLines: 4, decoration: const InputDecoration(labelText: 'محتوى الدرس / ملاحظات', border: OutlineInputBorder()))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), ElevatedButton(onPressed: () async { if (tc.text.trim().isEmpty) return; await DBHelper.insertLesson({'subject_id': widget.subject.id, 'title': tc.text.trim(), 'content': cc.text.trim(), 'date': DateTime.now().toIso8601String().split('T')[0]}); if (!ctx.mounted) return; Navigator.pop(ctx); _load(); }, child: const Text('إضافة'))])); }

  void _addHw() { final dc = TextEditingController(); DateTime due = DateTime.now().add(const Duration(days: 1)); showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(title: const Text('إضافة واجب'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: dc, maxLines: 3, decoration: const InputDecoration(labelText: 'وصف الواجب *', border: OutlineInputBorder())), ListTile(title: Text('تاريخ التسليم: ${due.day}/${due.month}/${due.year}'), trailing: const Icon(Icons.calendar_today), onTap: () async { final p = await showDatePicker(context: ctx, initialDate: due, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365))); if (p != null) ss(() => due = p); })]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), ElevatedButton(onPressed: () async { if (dc.text.trim().isEmpty) return; await DBHelper.insertHomework({'subject_id': widget.subject.id, 'description': dc.text.trim(), 'due_date': due.toIso8601String().split('T')[0], 'is_done': 0}); if (!ctx.mounted) return; Navigator.pop(ctx); _load(); }, child: const Text('إضافة'))]))); }

  void _addExam() { final tc = TextEditingController(), topc = TextEditingController(); DateTime ed = DateTime.now().add(const Duration(days: 7)); showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(title: const Text('إضافة امتحان'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: tc, decoration: const InputDecoration(labelText: 'اسم الامتحان *', border: OutlineInputBorder())), const SizedBox(height: 12), TextField(controller: topc, maxLines: 3, decoration: const InputDecoration(labelText: 'المواضيع الداخلة', border: OutlineInputBorder())), ListTile(title: Text('التاريخ: ${ed.day}/${ed.month}/${ed.year}'), trailing: const Icon(Icons.calendar_today), onTap: () async { final p = await showDatePicker(context: ctx, initialDate: ed, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365))); if (p != null) ss(() => ed = p); })]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), ElevatedButton(onPressed: () async { if (tc.text.trim().isEmpty) return; await DBHelper.insertExam({'subject_id': widget.subject.id, 'title': tc.text.trim(), 'exam_date': ed.toIso8601String().split('T')[0], 'topics': topc.text.trim()}); if (!ctx.mounted) return; Navigator.pop(ctx); _load(); }, child: const Text('إضافة'))]))); }

  @override
  Widget build(BuildContext context) { final c = Color(widget.subject.color); return Scaffold(
    appBar: AppBar(title: Text(widget.subject.name), backgroundColor: c, foregroundColor: Colors.white, bottom: TabBar(controller: _tab, labelColor: Colors.white, indicatorColor: Colors.white, tabs: const [Tab(text: 'الدروس'), Tab(text: 'الواجبات'), Tab(text: 'الامتحانات')])),
    body: TabBarView(controller: _tab, children: [
      _lessons.isEmpty ? const Center(child: Text('لا توجد دروس\nاضغط + لإضافة', textAlign: TextAlign.center)) : ListView.builder(padding: const EdgeInsets.all(16), itemCount: _lessons.length, itemBuilder: (ctx, i) { final l = _lessons[i]; return Card(margin: const EdgeInsets.only(bottom: 10), child: ExpansionTile(title: Text(l['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(l['date'] ?? ''), children: [if ((l['content'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(l['content']))])); }),
      _hw.isEmpty ? const Center(child: Text('لا توجد واجبات\nاضغط + لإضافة', textAlign: TextAlign.center)) : ListView.builder(padding: const EdgeInsets.all(16), itemCount: _hw.length, itemBuilder: (ctx, i) { final h = _hw[i]; return Card(margin: const EdgeInsets.only(bottom: 10), child: CheckboxListTile(title: Text(h['description'] ?? '', style: TextStyle(decoration: h['is_done']==1 ? TextDecoration.lineThrough : null)), subtitle: Text('التسليم: ${h['due_date']}'), value: h['is_done']==1, onChanged: (v) async { await DBHelper.updateHomeworkStatus(h['id'], v??false); _load(); })); }),
      _exams.isEmpty ? const Center(child: Text('لا توجد امتحانات\nاضغط + لإضافة', textAlign: TextAlign.center)) : ListView.builder(padding: const EdgeInsets.all(16), itemCount: _exams.length, itemBuilder: (ctx, i) { final e = _exams[i]; return Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(leading: const Icon(Icons.quiz_outlined, color: kAccent), title: Text(e['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text('${e['exam_date']}\n${e['topics'] ?? ''}'))); }),
    ]),
    floatingActionButton: FloatingActionButton(onPressed: () { final i = _tab.index; if (i==0) _addLesson(); else if (i==1) _addHw(); else _addExam(); }, backgroundColor: c, child: const Icon(Icons.add, color: Colors.white)),
  ); }
}

// ===== HOMEWORK SCREEN =====
class HomeworkScreen extends StatefulWidget {
  const HomeworkScreen({super.key});
  @override State<HomeworkScreen> createState() => _HomeworkScreenState();
}
class _HomeworkScreenState extends State<HomeworkScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _hw = [], _exams = [];
  bool _loading = true;
  @override void initState() { super.initState(); _tab = TabController(length: 2, vsync: this); _load(); }
  @override void dispose() { _tab.dispose(); super.dispose(); }
  Future<void> _load() async { final hw = await DBHelper.getHomework(); final ex = await DBHelper.getExams(); if (mounted) setState(() { _hw = hw; _exams = ex; _loading = false; }); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الواجبات والامتحانات'), bottom: TabBar(controller: _tab, tabs: const [Tab(text: 'الواجبات'), Tab(text: 'الامتحانات')])),
    body: _loading ? const Center(child: CircularProgressIndicator()) : TabBarView(controller: _tab, children: [
      _hw.isEmpty ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.assignment_turned_in, size: 64, color: Colors.grey), SizedBox(height: 16), Text('لا توجد واجبات', style: TextStyle(color: Colors.grey)), Text('أضفها من صفحة المادة', style: TextStyle(color: Colors.grey, fontSize: 13))]))
          : ListView(padding: const EdgeInsets.all(16), children: [
              ..._hw.where((h) => h['is_done']==0).map((h) => _hwTile(h)),
              if (_hw.any((h) => h['is_done']==1)) ...[const Divider(), Text('مكتملة', style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold)), ..._hw.where((h) => h['is_done']==1).map((h) => _hwTile(h))],
            ]),
      _exams.isEmpty ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.quiz_outlined, size: 64, color: Colors.grey), SizedBox(height: 16), Text('لا توجد امتحانات', style: TextStyle(color: Colors.grey)), Text('أضفها من صفحة المادة', style: TextStyle(color: Colors.grey, fontSize: 13))]))
          : ListView(padding: const EdgeInsets.all(16), children: _exams.map((e) { int d = 0; try { d = DateTime.parse(e['exam_date']).difference(DateTime.now()).inDays; } catch(_){} return Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(leading: CircleAvatar(backgroundColor: Color(e['subject_color']??0xFF6C63FF), child: const Icon(Icons.quiz_outlined, color: Colors.white, size: 20)), title: Text(e['subject_name']??'', style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text('${e['title']}\n${e['exam_date']}'), trailing: d >= 0 ? Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: (d<=3?kAccent:kPrimary).withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(d==0?'اليوم!':'بعد $d أيام', style: TextStyle(color: d<=3?kAccent:kPrimary, fontSize: 12, fontWeight: FontWeight.bold))) : const Text('انتهى', style: TextStyle(color: Colors.grey, fontSize: 12)))); }).toList()),
    ]),
  );

  Widget _hwTile(Map<String, dynamic> h) => Card(margin: const EdgeInsets.only(bottom: 8), child: CheckboxListTile(activeColor: kPrimary, title: Text(h['description']??'', style: TextStyle(decoration: h['is_done']==1?TextDecoration.lineThrough:null)), subtitle: Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(color: Color(h['subject_color']??0xFF6C63FF), shape: BoxShape.circle)), const SizedBox(width: 6), Text(h['subject_name']??''), const SizedBox(width: 12), Text(h['due_date']??'', style: TextStyle(color: Colors.grey[600], fontSize: 12))]), value: h['is_done']==1, onChanged: (v) async { await DBHelper.updateHomeworkStatus(h['id'], v??false); _load(); }, secondary: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20), onPressed: () async { await DBHelper.deleteHomework(h['id']); _load(); })));
}

// ===== AI CHAT SCREEN =====
class AIChatScreen extends StatefulWidget {
  const AIChatScreen({super.key});
  @override State<AIChatScreen> createState() => _AIChatScreenState();
}
class _AIChatScreenState extends State<AIChatScreen> {
  final _msgCtrl = TextEditingController(), _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _msgs = [];
  bool _loading = false;
  String? _apiKey;

  @override void initState() { super.initState(); _loadMsgs(); _loadKey(); }
  @override void dispose() { _msgCtrl.dispose(); _scrollCtrl.dispose(); super.dispose(); }

  Future<void> _loadKey() async { final p = await SharedPreferences.getInstance(); setState(() => _apiKey = p.getString('api_key')); }
  Future<void> _loadMsgs() async { final m = await DBHelper.getAIChat(); if (mounted) setState(() => _msgs = m); _scrollBottom(); }
  void _scrollBottom() => WidgetsBinding.instance.addPostFrameCallback((_) { if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut); });

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    if (_apiKey == null || _apiKey!.isEmpty) { _showKeyDialog(); return; }
    _msgCtrl.clear();
    final um = {'role': 'user', 'content': text, 'timestamp': DateTime.now().toIso8601String()};
    await DBHelper.insertAIMsg(um);
    setState(() { _msgs.add(um); _loading = true; });
    _scrollBottom();

    try {
      final lessons = await DBHelper.getAllLessons(); final hw = await DBHelper.getHomework(pending: true); final ex = await DBHelper.getExams();
      String ctx = 'أنت مساعد دراسي ذكي. بيانات الطالب:\n\n';
      if (lessons.isNotEmpty) { ctx += 'الدروس:\n'; for (final l in lessons.take(10)) { ctx += '- ${l['subject_name']}: ${l['title']}'; if ((l['content']??'').toString().isNotEmpty) ctx += ' - ${l['content'].toString().substring(0, l['content'].toString().length.clamp(0,150))}'; ctx += '\n'; } }
      if (hw.isNotEmpty) { ctx += '\nالواجبات:\n'; for (final h in hw.take(5)) ctx += '- ${h['subject_name']}: ${h['description']} (${h['due_date']})\n'; }
      if (ex.isNotEmpty) { ctx += '\nالامتحانات:\n'; for (final e in ex.take(5)) ctx += '- ${e['subject_name']}: ${e['title']} في ${e['exam_date']}\n'; }
      ctx += '\nهام: استجب بناءً على بيانات الطالب فقط. إذا لم تجد معلومات، أخبره بذلك بوضوح.';

      final history = _msgs.where((m) => m['role'] != null).map((m) => {'role': m['role'], 'content': m['content']}).toList();
      final res = await http.post(Uri.parse('https://api.anthropic.com/v1/messages'), headers: {'Content-Type': 'application/json', 'x-api-key': _apiKey!, 'anthropic-version': '2023-06-01'}, body: jsonEncode({'model': 'claude-haiku-4-5-20251001', 'max_tokens': 1024, 'system': ctx, 'messages': history}));
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body); final t = d['content'][0]['text'];
        final am = {'role': 'assistant', 'content': t, 'timestamp': DateTime.now().toIso8601String()};
        await DBHelper.insertAIMsg(am); if (mounted) setState(() => _msgs.add(am));
      } else { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: ${res.statusCode}'), backgroundColor: Colors.red)); }
    } catch(e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red)); }
    if (mounted) setState(() => _loading = false);
    _scrollBottom();
  }

  void _showKeyDialog() { final c = TextEditingController(text: _apiKey); showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('مفتاح API'), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text('أدخل مفتاح Anthropic API من:\nconsole.anthropic.com'), const SizedBox(height: 12), TextField(controller: c, decoration: const InputDecoration(labelText: 'sk-ant-...', border: OutlineInputBorder()), obscureText: true)]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), ElevatedButton(onPressed: () async { final p = await SharedPreferences.getInstance(); await p.setString('api_key', c.text.trim()); setState(() => _apiKey = c.text.trim()); if (!ctx.mounted) return; Navigator.pop(ctx); }, child: const Text('حفظ'))])); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Row(children: [Icon(Icons.psychology, color: kPrimary), SizedBox(width: 8), Text('المساعد الذكي')]), actions: [
      IconButton(icon: const Icon(Icons.key), onPressed: _showKeyDialog, tooltip: 'مفتاح API'),
      IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { await DBHelper.clearAIChat(); _loadMsgs(); }, tooltip: 'مسح'),
    ]),
    body: Column(children: [
      if (_apiKey == null || _apiKey!.isEmpty) Container(padding: const EdgeInsets.all(12), color: Colors.orange.withOpacity(0.1), child: Row(children: [const Icon(Icons.info_outline, color: Colors.orange), const SizedBox(width: 8), const Expanded(child: Text('أضف مفتاح API لتفعيل المساعد', style: TextStyle(fontSize: 13))), TextButton(onPressed: _showKeyDialog, child: const Text('إضافة'))])),
      Expanded(child: _msgs.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.psychology_outlined, size: 80, color: kPrimary), const SizedBox(height: 16), const Text('المساعد الدراسي الذكي', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text('اسألني عن دروسك!', style: TextStyle(color: Colors.grey[600])), const SizedBox(height: 24), Wrap(spacing: 8, runSpacing: 8, children: ['اشرح لي آخر درس', 'ما هي واجباتي؟', 'متى امتحاني؟', 'اختبرني'].map((t) => ActionChip(label: Text(t), onPressed: () { _msgCtrl.text = t; _send(); })).toList())]))
          : ListView.builder(controller: _scrollCtrl, padding: const EdgeInsets.all(16), itemCount: _msgs.length, itemBuilder: (ctx, i) {
              final m = _msgs[i]; final isUser = m['role'] == 'user';
              return Align(alignment: isUser ? Alignment.centerLeft : Alignment.centerRight, child: Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), constraints: BoxConstraints(maxWidth: MediaQuery.of(ctx).size.width * 0.8), decoration: BoxDecoration(color: isUser ? kPrimary : Theme.of(ctx).cardColor, borderRadius: BorderRadius.only(topRight: const Radius.circular(16), topLeft: const Radius.circular(16), bottomLeft: Radius.circular(isUser ? 4 : 16), bottomRight: Radius.circular(isUser ? 16 : 4)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))]), child: Text(m['content'] ?? '', style: TextStyle(color: isUser ? Colors.white : null, height: 1.5))));
            })),
      if (_loading) const Padding(padding: EdgeInsets.all(8), child: Row(children: [SizedBox(width: 16), SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 12), Text('جاري التفكير...', style: TextStyle(color: Colors.grey))])),
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(context).cardColor, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, -2))]), child: Row(children: [
        Expanded(child: TextField(controller: _msgCtrl, maxLines: null, textInputAction: TextInputAction.send, onSubmitted: (_) => _send(), decoration: InputDecoration(hintText: 'اسألني عن دروسك...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), filled: true, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)))),
        const SizedBox(width: 8),
        FloatingActionButton.small(onPressed: _send, backgroundColor: kPrimary, child: const Icon(Icons.send, color: Colors.white)),
      ])),
    ]),
  );
}
