import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'providers/app_state.dart';
import 'services/notification_service.dart';
import 'screens/calendar_screen.dart';
import 'screens/tasks_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/tracking_screen.dart';
import 'screens/event_form_screen.dart';
import 'screens/project_form_screen.dart';
import 'screens/task_form_screen.dart';
import 'screens/all_timeline_screen.dart';
import 'screens/day_note_dialog.dart';
import 'screens/app_drawer.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  } catch (e) {
    debugPrint('Failed to clear SharedPreferences on startup: $e');
  }
  try {
    const firebaseOptions = FirebaseOptions(
      apiKey: 'AIzaSyAALVX3X_i3MDD6HAd63whTtW9mNDnFG8c',
      appId: '1:446668780386:web:24e024b2f85b4fb0cb323b',
      messagingSenderId: '446668780386',
      projectId: 'myplan-a',
      authDomain: 'myplan-a.firebaseapp.com',
      storageBucket: 'myplan-a.firebasestorage.app',
      measurementId: 'G-8VVN6M4QGB',
    );

    final isDesktop =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS);

    if (kIsWeb) {
      await Firebase.initializeApp(options: firebaseOptions);
      await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    } else if (isDesktop) {
      await Firebase.initializeApp(options: firebaseOptions);
    } else {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }
  await NotificationService.init();
  await NotificationService.requestPermissions();
  runApp(
    ChangeNotifierProvider(
      create: (context) => AppState(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    return MaterialApp(
      title: 'Plan-A',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: appState.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(appState.fontSizeMultiplier),
          ),
          child: child!,
        );
      },
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0; // 0: Takvim, 1: Görevler

  Widget _buildViewTypeSelectorBar(BuildContext context, AppState appState) {
    final currentView = appState.calendarView;
    final views = [
      {'view': 'plan', 'label': 'Plan', 'icon': Icons.view_column},
      {'view': 'serit', 'label': 'Şerit', 'icon': Icons.layers},
      {
        'view': CalendarView.month,
        'label': 'Aylık',
        'icon': Icons.calendar_view_month,
      },
      {
        'view': CalendarView.week,
        'label': 'Haftalık',
        'icon': Icons.calendar_view_week,
      },
      {
        'view': CalendarView.day,
        'label': 'Günlük',
        'icon': Icons.calendar_view_day,
      },
      {
        'view': CalendarView.schedule,
        'label': 'Program',
        'icon': Icons.view_agenda,
      },
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(4.0),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: views.map((item) {
              final dynamic view = item['view'];
              final label = item['label'] as String;
              final icon = item['icon'] as IconData;
              final isSelected = view == 'plan'
                  ? appState.showPlanView
                  : (view == 'serit'
                      ? appState.showSeritView
                      : (!appState.showSeritView &&
                          !appState.showPlanView &&
                          currentView == view));

              return GestureDetector(
                onTap: () {
                  if (view == 'plan') {
                    appState.setShowPlanView(true);
                  } else if (view == 'serit') {
                    appState.setShowSeritView(true);
                  } else {
                    appState.setShowPlanView(false);
                    appState.setShowSeritView(false);
                    appState.setCalendarView(view as CalendarView);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    vertical: 8.0,
                    horizontal: 16.0,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 16,
                        color: isSelected ? Colors.white : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? Colors.white
                              : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildDateIndicator(AppState appState) {
    final today = DateTime.now();
    const shortMonths = [
      'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
      'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
    ];
    final shortMonthStr = shortMonths[today.month - 1];

    final Widget todayBox = GestureDetector(
      onTap: () {
        if (_currentIndex == 0) {
          appState.jumpToToday();
        }
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.blue.shade200, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${today.day}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
                height: 1.1,
              ),
            ),
            Text(
              shortMonthStr,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.blue.shade700,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );

    final dateToShow = appState.displayDate;
    const fullMonths = [
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
    ];
    final fullMonthStr = fullMonths[dateToShow.month - 1];

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        todayBox,
        if (_currentIndex == 0) ...[
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '$fullMonthStr ${dateToShow.year}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showAddSelection(
    BuildContext context,
    AppState appState, {
    DateTime? initialDate,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.layers, color: Colors.orange),
                title: const Text('Şerit Ekle'),
                onTap: () {
                  Navigator.pop(context);
                  appState.startSeritDraft(initialDate: initialDate);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.note_alt_outlined,
                  color: Colors.amber,
                ),
                title: const Text('Günlük Not Ekle/Düzenle'),
                onTap: () {
                  Navigator.pop(context);
                  DayNoteDialog.show(
                    context,
                    appState,
                    initialDate ?? DateTime.now(),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.event, color: Colors.blue),
                title: const Text('Etkinlik Ekle'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          EventFormScreen(initialDate: initialDate),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.rocket_launch, color: Colors.purple),
                title: const Text('Proje Ekle'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProjectFormScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.task_alt, color: Colors.green),
                title: const Text('Görev Ekle'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          TaskFormScreen(initialDate: initialDate),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final isWide = MediaQuery.of(context).size.width > 900;

    Widget currentScreen;
    switch (_currentIndex) {
      case 0:
        currentScreen = Column(
          children: [
            _buildViewTypeSelectorBar(context, appState),
            const Expanded(child: CalendarScreen()),
          ],
        );
        break;
      case 1:
        currentScreen = const TasksScreen();
        break;
      case 2:
        currentScreen = const TrackingScreen();
        break;
      case 3:
        currentScreen = const AllTimelineScreen();
        break;
      case 4:
        currentScreen = const SettingsScreen();
        break;
      default:
        currentScreen = Column(
          children: [
            _buildViewTypeSelectorBar(context, appState),
            const Expanded(child: CalendarScreen()),
          ],
        );
    }

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: 280,
              child: AppDrawer(
                isSidebar: true,
                currentIndex: _currentIndex,
                onIndexChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Scaffold(
                appBar: _currentIndex == 0 ? AppBar(
                  title: _buildDateIndicator(appState),
                  actions: [
                    IconButton(
                      icon: Icon(appState.isDarkMode ? Icons.light_mode : Icons.dark_mode),
                      onPressed: () => appState.toggleDarkMode(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.person),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ProfileScreen()),
                        );
                      },
                    ),
                  ],
                ) : null,
                body: currentScreen,
                floatingActionButton: _currentIndex == 0 ? FloatingActionButton(
                  onPressed: () => _showAddSelection(context, appState),
                  child: const Icon(Icons.add),
                ) : null,
              ),
            ),
          ],
        ),
      );
    } else {
      return Scaffold(
        appBar: AppBar(
          title: _currentIndex == 0 ? _buildDateIndicator(appState) : Text(
            _currentIndex == 1
                ? 'Görevler'
                : _currentIndex == 2
                    ? 'Projeler'
                    : _currentIndex == 3
                        ? 'Analiz'
                        : 'Ayarlar',
          ),
          actions: [
            IconButton(
              icon: Icon(appState.isDarkMode ? Icons.light_mode : Icons.dark_mode),
              onPressed: () => appState.toggleDarkMode(),
            ),
            IconButton(
              icon: const Icon(Icons.person),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfileScreen()),
                );
              },
            ),
          ],
        ),
        drawer: AppDrawer(
          isSidebar: false,
          currentIndex: _currentIndex,
          onIndexChanged: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
        ),
        body: currentScreen,
        floatingActionButton: _currentIndex == 0 ? FloatingActionButton(
          onPressed: () => _showAddSelection(context, appState),
          child: const Icon(Icons.add),
        ) : null,
      );
    }
  }
}
