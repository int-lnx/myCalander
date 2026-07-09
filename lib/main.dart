import 'dart:ui';
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
import 'screens/notes_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/tracking_screen.dart';
import 'screens/event_form_screen.dart';
import 'screens/project_form_screen.dart';
import 'screens/task_form_screen.dart';
import 'screens/all_timeline_screen.dart';
import 'screens/analysis_screen.dart';
import 'screens/day_note_dialog.dart';
import 'screens/app_drawer.dart';
import 'screens/splash_screen.dart';

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

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    return MaterialApp(
      title: 'Plan-A',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const AppScrollBehavior(),
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
      home: const SplashScreen(),
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
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  Widget _buildSearchField(AppState appState) {
    final isDark = appState.isDarkMode;
    return TextField(
      controller: _searchController,
      autofocus: true,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16),
      decoration: InputDecoration(
        hintText: 'Ara...',
        border: InputBorder.none,
        hintStyle: TextStyle(color: isDark ? Colors.white60 : Colors.black45),
      ),
      onChanged: (val) {
        appState.setSearchQuery(val);
      },
    );
  }

  List<Widget> _buildSearchActions(AppState appState) {
    return [
      if (appState.searchResults.isNotEmpty) ...[
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${appState.searchResultIndex + 1}/${appState.searchResults.length}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => appState.prevSearchResult(),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () => appState.nextSearchResult(),
        ),
      ],
      IconButton(
        icon: const Icon(Icons.close),
        onPressed: () {
          setState(() {
            _isSearching = false;
            _searchController.clear();
            appState.setSearchQuery('');
          });
        },
      ),
    ];
  }

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
      {
        'view': 'recent',
        'label': 'Son Eklenenler',
        'icon': Icons.history,
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
                        : (view == 'recent'
                            ? appState.showRecentView
                            : (!appState.showSeritView &&
                                  !appState.showPlanView &&
                                  !appState.showRecentView &&
                                  currentView == view)));

              return GestureDetector(
                onTap: () {
                  if (view == 'plan') {
                    appState.setShowPlanView(true);
                  } else if (view == 'serit') {
                    appState.setShowSeritView(true);
                  } else if (view == 'recent') {
                    appState.setShowRecentView(true);
                  } else {
                    appState.setShowPlanView(false);
                    appState.setShowSeritView(false);
                    appState.setShowRecentView(false);
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
      'Oca',
      'Şub',
      'Mar',
      'Nis',
      'May',
      'Haz',
      'Tem',
      'Ağu',
      'Eyl',
      'Eki',
      'Kas',
      'Ara',
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
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
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
        currentScreen = const AnalysisScreen();
        break;
      case 4:
        currentScreen = const NotesScreen();
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
                appBar: (_currentIndex == 0 || _currentIndex == 1)
                    ? AppBar(
                        title: _isSearching
                            ? _buildSearchField(appState)
                            : (_currentIndex == 0
                                ? _buildDateIndicator(appState)
                                : const Text('Görevler')),
                        actions: _isSearching
                            ? _buildSearchActions(appState)
                            : [
                                if (_currentIndex == 0)
                                  IconButton(
                                    icon: Icon(
                                      appState.fitToScreen
                                          ? Icons.fullscreen_exit
                                          : Icons.fullscreen,
                                      color: appState.fitToScreen
                                          ? Colors.blue
                                          : null,
                                    ),
                                    tooltip: 'Dikey Ekrana Sığdır',
                                    onPressed: () => appState.toggleFitToScreen(),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.search),
                                  tooltip: 'Ara',
                                  onPressed: () {
                                    setState(() => _isSearching = true);
                                  },
                                ),
                                IconButton(
                                  icon: Icon(
                                    appState.isDarkMode
                                        ? Icons.light_mode
                                        : Icons.dark_mode,
                                  ),
                                  onPressed: () => appState.toggleDarkMode(),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.person),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const ProfileScreen(),
                                      ),
                                    );
                                  },
                                ),
                              ],
                      )
                    : null,
                body: currentScreen,
              ),
            ),
          ],
        ),
      );
    } else {
      return Scaffold(
        appBar: AppBar(
          title: _isSearching
              ? _buildSearchField(appState)
              : (_currentIndex == 0
                  ? _buildDateIndicator(appState)
                  : Text(
                      _currentIndex == 1
                          ? 'Görevler'
                          : _currentIndex == 2
                          ? 'Projeler'
                          : _currentIndex == 3
                          ? 'Analiz'
                          : 'Notlar',
                    )),
          actions: _isSearching
              ? _buildSearchActions(appState)
              : [
                  if (_currentIndex == 0)
                    IconButton(
                      icon: Icon(
                        appState.fitToScreen
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen,
                        color: appState.fitToScreen ? Colors.blue : null,
                      ),
                      tooltip: 'Dikey Ekrana Sığdır',
                      onPressed: () => appState.toggleFitToScreen(),
                    ),
                  if (_currentIndex == 0 || _currentIndex == 1)
                    IconButton(
                      icon: const Icon(Icons.search),
                      tooltip: 'Ara',
                      onPressed: () {
                        setState(() => _isSearching = true);
                      },
                    ),
                  IconButton(
                    icon: Icon(
                      appState.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                    ),
                    onPressed: () => appState.toggleDarkMode(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.person),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ProfileScreen(),
                        ),
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
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Colors.blue,
          unselectedItemColor: Colors.grey,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today),
              label: 'Takvim',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.task_alt),
              label: 'Görevler',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.rocket_launch),
              label: 'Projeler',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart),
              label: 'Analiz',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.note_alt),
              label: 'Notlar',
            ),
          ],
        ),
      );
    }
  }
}
