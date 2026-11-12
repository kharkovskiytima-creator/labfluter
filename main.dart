import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// НАЛАШТУВАННЯ ВІДПРАВКИ ПОШТИ (EmailJS, https://www.emailjs.com)
// Вставте свої значення з панелі EmailJS. Поки тут YOUR_..., працює ДЕМО-режим:
// код не надсилається на пошту, а показується у вікні підтвердження.
// ============================================================================
class EmailConfig {
  static const serviceId = 'service_qvkjxma';
  static const templateId = 'template_86nniwh';
  static const publicKey = 'bn00r_ZlJAGU_mTiw';
}

// ============================================================================
// MODEL
// ============================================================================
class Task {
  final String id;
  final String title;
  final bool done;

  const Task({required this.id, required this.title, this.done = false});

  Task copyWith({String? title, bool? done}) =>
      Task(id: id, title: title ?? this.title, done: done ?? this.done);

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'done': done};

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] as String,
        title: j['title'] as String,
        done: j['done'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      other is Task && other.id == id && other.title == title && other.done == done;

  @override
  int get hashCode => Object.hash(id, title, done);
}

class User {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String? photo; // фото у форматі base64
  final bool emailVerified;
  final List<Task> tasks;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    this.photo,
    this.emailVerified = false,
    this.tasks = const [],
  });

  User copyWith({List<Task>? tasks}) => User(
        id: id,
        name: name,
        email: email,
        phone: phone,
        photo: photo,
        emailVerified: emailVerified,
        tasks: tasks ?? this.tasks,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'photo': photo,
        'emailVerified': emailVerified,
        'tasks': tasks.map((t) => t.toJson()).toList(),
      };

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        name: j['name'] as String,
        email: j['email'] as String,
        phone: j['phone'] as String,
        photo: j['photo'] as String?,
        emailVerified: j['emailVerified'] as bool? ?? false,
        tasks: ((j['tasks'] as List<dynamic>?) ?? [])
            .map((e) => Task.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  @override
  bool operator ==(Object other) =>
      other is User &&
      other.id == id &&
      other.name == name &&
      other.email == email &&
      other.phone == phone &&
      other.photo == photo &&
      other.emailVerified == emailVerified &&
      listEquals(other.tasks, tasks);

  @override
  int get hashCode => Object.hash(
      id, name, email, phone, photo, emailVerified, Object.hashAll(tasks));
}

// ============================================================================
// SERVICES
// ============================================================================
class EmailService {
  static bool get isConfigured =>
      EmailConfig.serviceId != 'YOUR_SERVICE_ID' &&
      EmailConfig.templateId != 'YOUR_TEMPLATE_ID' &&
      EmailConfig.publicKey != 'YOUR_PUBLIC_KEY';

  /// Випадковий 6-значний код.
  static String generateCode() =>
      (100000 + Random.secure().nextInt(900000)).toString();

  /// Надсилає код на пошту через EmailJS REST API.
  /// У шаблоні EmailJS мають бути змінні {{to_email}} та {{code}}.
  static Future<void> sendCode(String email, String code) async {
    if (!isConfigured) return; // демо-режим
    final res = await http.post(
      Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'service_id': EmailConfig.serviceId,
        'template_id': EmailConfig.templateId,
        'user_id': EmailConfig.publicKey,
        'template_params': {'to_email': email, 'code': code},
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('${res.statusCode}: ${res.body}');
    }
  }
}

// ============================================================================
// REPOSITORY: локальне кешування (shared_preferences), асинхронно
// ============================================================================
class UserRepository {
  static const _key = 'users_v2';

  Future<List<User>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> save(List<User> users) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(users.map((u) => u.toJson()).toList()));
  }
}

// ============================================================================
// VIEWMODELS
// ============================================================================
class UserListViewModel extends ChangeNotifier {
  UserListViewModel(this._repo);

  final UserRepository _repo;
  List<User> _users = [];
  bool _loading = true;

  List<User> get users => List.unmodifiable(_users);
  bool get isLoading => _loading;

  User? byId(String id) {
    for (final u in _users) {
      if (u.id == id) return u;
    }
    return null;
  }

  Future<void> loadUsers() async {
    _loading = true;
    notifyListeners();
    _users = await _repo.load();
    _loading = false;
    notifyListeners();
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> _replace(String id, User Function(User) change) async {
    _users = [for (final u in _users) u.id == id ? change(u) : u];
    notifyListeners();
    await _repo.save(_users);
  }

  // ---------- користувачі ----------
  Future<String> addUser({
    required String name,
    required String email,
    required String phone,
    String? photo,
    required bool emailVerified,
  }) async {
    final user = User(
      id: _newId(),
      name: name,
      email: email,
      phone: phone,
      photo: photo,
      emailVerified: emailVerified,
    );
    _users = [..._users, user];
    notifyListeners();
    await _repo.save(_users);
    return user.id;
  }

  Future<void> updateUser(
    User old, {
    required String name,
    required String email,
    required String phone,
    String? photo,
    required bool emailVerified,
  }) {
    return _replace(
      old.id,
      (u) => User(
        id: u.id,
        name: name,
        email: email,
        phone: phone,
        photo: photo,
        emailVerified: emailVerified,
        tasks: u.tasks,
      ),
    );
  }

  Future<void> deleteUser(String id) async {
    _users = _users.where((u) => u.id != id).toList();
    notifyListeners();
    await _repo.save(_users);
  }

  Future<void> restoreUser(User user, int index) async {
    final copy = [..._users];
    copy.insert(index.clamp(0, copy.length), user);
    _users = copy;
    notifyListeners();
    await _repo.save(_users);
  }

  // ---------- завдання ----------
  Future<void> addTask(String userId, String title) => _replace(
        userId,
        (u) => u.copyWith(tasks: [...u.tasks, Task(id: _newId(), title: title)]),
      );

  Future<void> toggleTask(String userId, String taskId) => _replace(
        userId,
        (u) => u.copyWith(tasks: [
          for (final t in u.tasks) t.id == taskId ? t.copyWith(done: !t.done) : t
        ]),
      );

  Future<void> deleteTask(String userId, String taskId) => _replace(
        userId,
        (u) => u.copyWith(tasks: u.tasks.where((t) => t.id != taskId).toList()),
      );

  Future<void> restoreTask(String userId, Task task, int index) => _replace(
        userId,
        (u) {
          final list = [...u.tasks];
          list.insert(index.clamp(0, list.length), task);
          return u.copyWith(tasks: list);
        },
      );

  /// Зміна порядку завдань перетягуванням (drag & drop).
  Future<void> reorderTasks(String userId, int oldIndex, int newIndex) =>
      _replace(userId, (u) {
        final list = [...u.tasks];
        if (newIndex > oldIndex) newIndex -= 1;
        final item = list.removeAt(oldIndex);
        list.insert(newIndex, item);
        return u.copyWith(tasks: list);
      });
}

class ThemeViewModel extends ChangeNotifier {
  static const _key = 'theme_mode';
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    _mode = ThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => ThemeMode.system,
    );
    notifyListeners();
  }

  Future<void> toggle(Brightness current) async {
    _mode = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _mode.name);
  }
}

final userVm = UserListViewModel(UserRepository());
final themeVm = ThemeViewModel();

// ============================================================================
// APP
// ============================================================================
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  userVm.loadUsers();
  themeVm.load();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeVm,
      builder: (context, _) => MaterialApp(
        title: 'Користувачі',
        debugShowCheckedModeBanner: false,
        themeMode: themeVm.mode,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: Brightness.dark,
          ),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

// Анімований перехід між екранами
Route<T> animatedRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

// ============================================================================
// WIDGETS
// ============================================================================
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.photo, this.radius = 28});

  final String name;
  final String? photo;
  final double radius;

  static final Map<String, Uint8List> _cache = {};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Uint8List? bytes;
    if (photo != null) {
      bytes = _cache.putIfAbsent(photo!, () => base64Decode(photo!));
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      backgroundImage: bytes != null ? MemoryImage(bytes) : null,
      child: bytes != null
          ? null
          : Text(
              name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?',
              style: TextStyle(fontSize: radius * 0.8),
            ),
    );
  }
}

class UserCard extends StatelessWidget {
  const UserCard({
    super.key,
    required this.user,
    required this.onTap,
    required this.onEdit,
  });

  final User user;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final done = user.tasks.where((t) => t.done).length;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, top: 10, bottom: 10, right: 4),
          child: Row(
            children: [
              Hero(
                tag: 'avatar_${user.id}',
                child: UserAvatar(name: user.name, photo: user.photo),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(user.name,
                              style: text.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (user.emailVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.verified, size: 16, color: Colors.green),
                        ],
                      ],
                    ),
                    Text(user.email,
                        style: text.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(user.phone,
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(
                      'Завдань: ${user.tasks.length} (виконано $done)',
                      style: text.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Редагувати',
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// VIEW: головний екран
// ============================================================================
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Користувачі'),
        actions: [
          IconButton(
            tooltip: 'Змінити тему',
            onPressed: () => themeVm.toggle(brightness),
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) => RotationTransition(
                turns: Tween<double>(begin: 0.75, end: 1).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Icon(
                brightness == Brightness.dark ? Icons.light_mode : Icons.dark_mode,
                key: ValueKey(brightness),
              ),
            ),
          ),
        ],
      ),
      body: const _UserList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.of(context).push(animatedRoute(const UserFormScreen())),
        icon: const Icon(Icons.person_add),
        label: const Text('Додати'),
      ),
    );
  }
}

class _UserList extends StatelessWidget {
  const _UserList();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: userVm,
      builder: (context, _) {
        if (userVm.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final users = userVm.users;
        if (users.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Список порожній.\nНатисніть «Додати», щоб створити користувача.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 480,
            mainAxisExtent: 108,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            return Dismissible(
              key: ValueKey(user.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.delete,
                    color: Theme.of(context).colorScheme.onErrorContainer),
              ),
              onDismissed: (_) {
                final messenger = ScaffoldMessenger.of(context);
                userVm.deleteUser(user.id);
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text('«${user.name}» видалено'),
                      action: SnackBarAction(
                        label: 'Скасувати',
                        onPressed: () => userVm.restoreUser(user, index),
                      ),
                    ),
                  );
              },
              child: UserCard(
                user: user,
                onTap: () => Navigator.of(context)
                    .push(animatedRoute(TasksScreen(userId: user.id))),
                onEdit: () => Navigator.of(context)
                    .push(animatedRoute(UserFormScreen(user: user))),
              ),
            );
          },
        );
      },
    );
  }
}

// ============================================================================
// VIEW: завдання користувача (перетягування для зміни порядку)
// ============================================================================
class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key, required this.userId});

  final String userId;

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _add() {
    final title = _ctrl.text.trim();
    if (title.isEmpty) return;
    userVm.addTask(widget.userId, title);
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: userVm,
      builder: (context, _) {
        final user = userVm.byId(widget.userId);
        if (user == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Користувача не знайдено')),
          );
        }
        final text = Theme.of(context).textTheme;
        final scheme = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Завдання'),
            actions: [
              IconButton(
                tooltip: 'Редагувати користувача',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.of(context)
                    .push(animatedRoute(UserFormScreen(user: user))),
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Hero(
                          tag: 'avatar_${user.id}',
                          child: UserAvatar(
                              name: user.name, photo: user.photo, radius: 30),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user.name, style: text.titleLarge),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(user.email,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  if (user.emailVerified) ...[
                                    const SizedBox(width: 6),
                                    const Icon(Icons.verified,
                                        size: 16, color: Colors.green),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _add(),
                            decoration: const InputDecoration(
                              labelText: 'Нове завдання',
                              prefixIcon: Icon(Icons.task_alt),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _add,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Icon(Icons.add),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Перетягніть значок ≡, щоб змінити порядок',
                        style: text.bodySmall,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: user.tasks.isEmpty
                        ? const Center(child: Text('Завдань поки немає'))
                        : ReorderableListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            buildDefaultDragHandles: false,
                            itemCount: user.tasks.length,
                            onReorder: (o, n) =>
                                userVm.reorderTasks(user.id, o, n),
                            itemBuilder: (context, index) {
                              final task = user.tasks[index];
                              return Dismissible(
                                key: ValueKey(task.id),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 24),
                                  decoration: BoxDecoration(
                                    color: scheme.errorContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(Icons.delete,
                                      color: scheme.onErrorContainer),
                                ),
                                onDismissed: (_) {
                                  final messenger = ScaffoldMessenger.of(context);
                                  userVm.deleteTask(user.id, task.id);
                                  messenger
                                    ..hideCurrentSnackBar()
                                    ..showSnackBar(
                                      SnackBar(
                                        content: const Text('Завдання видалено'),
                                        action: SnackBarAction(
                                          label: 'Скасувати',
                                          onPressed: () => userVm.restoreTask(
                                              user.id, task, index),
                                        ),
                                      ),
                                    );
                                },
                                child: Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: Checkbox(
                                      value: task.done,
                                      onChanged: (_) =>
                                          userVm.toggleTask(user.id, task.id),
                                    ),
                                    title: Text(
                                      '${index + 1}. ${task.title}',
                                      style: task.done
                                          ? TextStyle(
                                              decoration:
                                                  TextDecoration.lineThrough,
                                              color: scheme.outline,
                                            )
                                          : null,
                                    ),
                                    trailing: ReorderableDragStartListener(
                                      index: index,
                                      child: const Padding(
                                        padding: EdgeInsets.all(8),
                                        child: Icon(Icons.drag_handle),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// VIEW: діалог підтвердження пошти кодом
// ============================================================================
class EmailVerifyDialog extends StatefulWidget {
  const EmailVerifyDialog({super.key, required this.email});

  final String email;

  @override
  State<EmailVerifyDialog> createState() => _EmailVerifyDialogState();
}

class _EmailVerifyDialogState extends State<EmailVerifyDialog> {
  static const _ttl = Duration(minutes: 10);
  static const _maxAttempts = 5;

  final _ctrl = TextEditingController();
  String _code = '';
  DateTime? _sentAt;
  bool _sending = true;
  String? _error;
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
    _send();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    _code = EmailService.generateCode();
    String? error;
    DateTime? sentAt;
    try {
      await EmailService.sendCode(widget.email, _code);
      sentAt = DateTime.now();
    } catch (e) {
      error = 'Не вдалося надіслати лист: $e';
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      _error = error;
      _sentAt = sentAt;
    });
  }

  void _resend() {
    setState(() {
      _sending = true;
      _error = null;
      _attempts = 0;
      _ctrl.clear();
    });
    _send();
  }

  void _check() {
    if (_sentAt == null) return;
    if (DateTime.now().difference(_sentAt!) > _ttl) {
      setState(() => _error = 'Код застарів. Надішліть новий.');
      return;
    }
    if (_ctrl.text.trim() == _code) {
      Navigator.of(context).pop(true);
      return;
    }
    _attempts++;
    setState(() {
      if (_attempts >= _maxAttempts) {
        _sentAt = null;
        _error = 'Забагато невдалих спроб. Надішліть новий код.';
      } else {
        _error = 'Невірний код (спроба $_attempts з $_maxAttempts)';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final demo = !EmailService.isConfigured;
    return AlertDialog(
      title: const Text('Підтвердження пошти'),
      content: SizedBox(
        width: 360,
        child: _sending
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_sentAt != null)
                    Text('Ми надіслали 6-значний код на\n${widget.email}'),
                  if (demo && _sentAt != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'ДЕМО-РЕЖИМ: сервіс пошти не налаштовано.\nВаш код: $_code',
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _ctrl,
                    enabled: _sentAt != null,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    onSubmitted: (_) => _check(),
                    decoration: const InputDecoration(
                      labelText: 'Код із листа',
                      prefixIcon: Icon(Icons.pin),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Скасувати'),
        ),
        TextButton(
          onPressed: _sending ? null : _resend,
          child: const Text('Надіслати ще раз'),
        ),
        FilledButton(
          onPressed: (_sending || _sentAt == null) ? null : _check,
          child: const Text('Підтвердити'),
        ),
      ],
    );
  }
}

// ============================================================================
// VIEW: форма додавання / редагування + камера / галерея + підтвердження пошти
// ============================================================================
class UserFormScreen extends StatefulWidget {
  const UserFormScreen({super.key, this.user});

  final User? user;

  @override
  State<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<UserFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailKey = GlobalKey<FormFieldState<String>>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  final _picker = ImagePicker();

  String? _photo;
  String? _verifiedFor; // пошта (у нижньому регістрі), яку вже підтверджено
  bool _saving = false;

  bool get _isEdit => widget.user != null;
  bool get _emailVerified =>
      _verifiedFor != null && _verifiedFor == _email.text.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _name = TextEditingController(text: u?.name ?? '');
    _email = TextEditingController(text: u?.email ?? '');
    _phone = TextEditingController(text: u?.phone ?? '');
    _photo = u?.photo;
    if (u != null && u.emailVerified) _verifiedFor = u.email.toLowerCase();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 400,
        imageQuality: 70,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() => _photo = base64Encode(bytes));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не вдалося отримати доступ до камери/галереї')),
      );
    }
  }

  void _showPhotoSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Зробити фото'),
              onTap: () {
                Navigator.pop(ctx);
                _pick(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Обрати з галереї'),
              onTap: () {
                Navigator.pop(ctx);
                _pick(ImageSource.gallery);
              },
            ),
            if (_photo != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Видалити фото'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _photo = null);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Надсилає код на пошту й просить його ввести.
  Future<bool> _verifyEmail() async {
    if (!(_emailKey.currentState?.validate() ?? false)) return false;
    final email = _email.text.trim();
    final ok = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => EmailVerifyDialog(email: email),
        ) ??
        false;
    if (!mounted) return false;
    if (ok) setState(() => _verifiedFor = email.toLowerCase());
    return ok;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_emailVerified) {
      final ok = await _verifyEmail();
      if (!ok) return;
    }
    setState(() => _saving = true);
    final name = _name.text.trim();
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    if (_isEdit) {
      await userVm.updateUser(widget.user!,
          name: name, email: email, phone: phone, photo: _photo, emailVerified: true);
      if (mounted) Navigator.of(context).pop();
    } else {
      final id = await userVm.addUser(
          name: name, email: email, phone: phone, photo: _photo, emailVerified: true);
      // Після додавання одразу відкриваємо завдання нового користувача.
      if (mounted) {
        Navigator.of(context)
            .pushReplacement(animatedRoute(TasksScreen(userId: id)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Редагування' : 'Новий користувач')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _showPhotoSheet,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        UserAvatar(name: _name.text, photo: _photo, radius: 56),
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: scheme.primary,
                          child: Icon(Icons.camera_alt,
                              size: 18, color: scheme.onPrimary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _name,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: "Ім'я",
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().length < 2)
                        ? "Введіть ім'я (мінімум 2 символи)"
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: _emailKey,
                    controller: _email,
                    onChanged: (_) => setState(() {}),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Електронна пошта',
                      prefixIcon: const Icon(Icons.email),
                      border: const OutlineInputBorder(),
                      suffixIcon: Icon(
                        _emailVerified ? Icons.verified : Icons.error_outline,
                        color: _emailVerified ? Colors.green : scheme.outline,
                      ),
                      helperText: _emailVerified
                          ? 'Пошту підтверджено'
                          : 'Пошту потрібно підтвердити кодом',
                    ),
                    validator: (v) {
                      final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                          .hasMatch(v?.trim() ?? '');
                      return ok ? null : 'Введіть коректний email';
                    },
                  ),
                  if (!_emailVerified)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _verifyEmail,
                        icon: const Icon(Icons.mark_email_read_outlined),
                        label: const Text('Надіслати код підтвердження'),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Телефон',
                      prefixIcon: Icon(Icons.phone),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final digits = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                      return digits.length >= 10
                          ? null
                          : 'Введіть коректний номер телефону';
                    },
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _saving
                            ? const SizedBox(
                                key: ValueKey('loading'),
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save, key: ValueKey('save')),
                      ),
                      label: Text(_isEdit ? 'Зберегти зміни' : 'Додати'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
