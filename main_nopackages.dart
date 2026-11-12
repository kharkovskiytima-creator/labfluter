import 'package:flutter/material.dart';

// ============================================================================
// MODEL
// ============================================================================
class User {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String? photo; // фото у форматі base64

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    this.photo,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'phone': phone,
        'photo': photo,
      };

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        name: j['name'] as String,
        email: j['email'] as String,
        phone: j['phone'] as String,
        photo: j['photo'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is User &&
      other.id == id &&
      other.name == name &&
      other.email == email &&
      other.phone == phone &&
      other.photo == photo;

  @override
  int get hashCode => Object.hash(id, name, email, phone, photo);
}

// ============================================================================
// REPOSITORY: локальне кешування (shared_preferences), асинхронно
// ============================================================================
class UserRepository {
  // Кеш у пам'яті (без зовнішніх пакетів). Асинхронні методи збережено.
  static List<User> _cache = [
    const User(
        id: '1', name: 'Олена Коваль', email: 'olena@example.com',
        phone: '+380501112233', photo: '4283215696'),
    const User(
        id: '2', name: 'Андрій Мельник', email: 'andriy@example.com',
        phone: '+380671234567', photo: '4283657726'),
  ];

  Future<List<User>> load() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return List.of(_cache);
  }

  Future<void> save(List<User> users) async {
    _cache = List.of(users);
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

  Future<void> loadUsers() async {
    _loading = true;
    notifyListeners();
    _users = await _repo.load();
    _loading = false;
    notifyListeners();
  }

  Future<void> addUser({
    required String name,
    required String email,
    required String phone,
    String? photo,
  }) async {
    final user = User(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      email: email,
      phone: phone,
      photo: photo,
    );
    _users = [..._users, user];
    notifyListeners();
    await _repo.save(_users);
  }

  Future<void> updateUser(
    User old, {
    required String name,
    required String email,
    required String phone,
    String? photo,
  }) async {
    final updated = User(
      id: old.id,
      name: name,
      email: email,
      phone: phone,
      photo: photo,
    );
    _users = [for (final u in _users) u.id == old.id ? updated : u];
    notifyListeners();
    await _repo.save(_users);
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
}

class ThemeViewModel extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> load() async {}

  Future<void> toggle(Brightness current) async {
    _mode = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
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
  final String? photo; // колір аватара (int у вигляді рядка)
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = photo == null ? null : int.tryParse(photo!);
    return CircleAvatar(
      radius: radius,
      backgroundColor: value != null ? Color(value) : scheme.primaryContainer,
      foregroundColor: value != null ? Colors.white : scheme.onPrimaryContainer,
      child: Text(
        name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?',
        style: TextStyle(fontSize: radius * 0.8),
      ),
    );
  }
}

class UserCard extends StatelessWidget {
  const UserCard({super.key, required this.user, required this.onTap});

  final User user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    Text(user.name,
                        style: text.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(user.email,
                        style: text.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(user.phone,
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
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
        // Адаптивність: 1 колонка на телефоні, кілька на широких екранах.
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 480,
            mainAxisExtent: 92,
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
// VIEW: форма додавання / редагування + камера / галерея (image_picker)
// ============================================================================
class UserFormScreen extends StatefulWidget {
  const UserFormScreen({super.key, this.user});

  final User? user;

  @override
  State<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<UserFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;

  String? _photo;
  bool _saving = false;

  bool get _isEdit => widget.user != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.user?.name ?? '');
    _email = TextEditingController(text: widget.user?.email ?? '');
    _phone = TextEditingController(text: widget.user?.phone ?? '');
    _photo = widget.user?.photo;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  static const _palette = <Color>[
    Colors.indigo, Colors.teal, Colors.orange, Colors.pink,
    Colors.green, Colors.purple, Colors.brown, Colors.blueGrey,
  ];

  void _showPhotoSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Оберіть колір аватара'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in _palette)
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() => _photo = c.value.toString());
                      },
                      child: CircleAvatar(backgroundColor: c, radius: 22),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final name = _name.text.trim();
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    if (_isEdit) {
      await userVm.updateUser(widget.user!,
          name: name, email: email, phone: phone, photo: _photo);
    } else {
      await userVm.addUser(name: name, email: email, phone: phone, photo: _photo);
    }
    if (mounted) Navigator.of(context).pop();
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
                        Hero(
                          tag: 'avatar_${widget.user?.id ?? 'new'}',
                          child: UserAvatar(
                              name: _name.text, photo: _photo, radius: 56),
                        ),
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: scheme.primary,
                          child: Icon(Icons.palette,
                              size: 18, color: scheme.onPrimary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _name,
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
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Електронна пошта',
                      prefixIcon: Icon(Icons.email),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                          .hasMatch(v?.trim() ?? '');
                      return ok ? null : 'Введіть коректний email';
                    },
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
