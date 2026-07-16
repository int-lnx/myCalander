import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../utils/id_generator.dart';
import '../utils/recurrence_helper.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/event.dart';
import '../models/task_item.dart';
import '../models/project.dart';
import '../models/project_evaluation.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../models/serit.dart';
import '../models/topic.dart';
import '../models/topic_plan.dart';
import '../models/note.dart';
import '../models/day_note.dart';
import '../services/notification_service.dart';

String? _sanitizeRRule(String? rule, DateTime startDate) {
  if (rule == null || rule.isEmpty) return rule;
  String sanitized = rule;
  if (sanitized.contains('FREQ=WEEKLY') && !sanitized.contains('BYDAY=')) {
    const days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
    final weekday = startDate.weekday;
    if (weekday >= 1 && weekday <= 7) {
      sanitized = '$sanitized;BYDAY=${days[weekday - 1]}';
    }
  }
  if (sanitized.contains('FREQ=MONTHLY') &&
      !sanitized.contains('BYMONTHDAY=') &&
      !sanitized.contains('BYDAY=')) {
    sanitized = '$sanitized;BYMONTHDAY=${startDate.day}';
  }
  if (sanitized.contains('FREQ=YEARLY') && !sanitized.contains('BYMONTH=')) {
    sanitized =
        '$sanitized;BYMONTH=${startDate.month};BYMONTHDAY=${startDate.day}';
  }
  return sanitized;
}

class AppState extends ChangeNotifier {
  static const String appVersion = '2.32';
  bool _showSeritOverlay = true;
  bool get showSeritOverlay => _showSeritOverlay;
  void toggleSeritOverlay() {
    _showSeritOverlay = !_showSeritOverlay;
    notifyListeners();
  }
  List<String> _deletedTaskIds = [];
  List<String> _deletedEventIds = [];
  List<String> _deletedDayNoteIds = [];
  List<String> _deletedProjectIds = [];
  bool _selectedProjectIdsNeedsInit = false;

  Future<void> _saveDeletedIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('deletedTaskIds', _deletedTaskIds);
    await prefs.setStringList('deletedEventIds', _deletedEventIds);
    await prefs.setStringList('deletedDayNoteIds', _deletedDayNoteIds);
    await prefs.setStringList('deletedProjectIds', _deletedProjectIds);
  }

  List<Event> _events = [];
  List<TaskItem> _tasks = [];
  List<Project> _projects = [];
  List<ProjectEvaluation> _evaluations = [];
  List<String> _selectedProjectIds = [];
  bool _isBulkMode = false;
  final Set<String> _selectedEventIds = {};

  bool get isBulkMode => _isBulkMode;
  Set<String> get selectedEventIds => _selectedEventIds;

  Map<String, String> _paintedDays =
      {}; // key: "yyyy-MM-dd", value: color string
  Map<String, String> get paintedDays => _paintedDays;

  List<DayNote> _dayNotes = [];
  List<DayNote> get dayNotes => _dayNotes;

  List<Note> _notes = [];
  List<Note> get notes => _notes;

  String _quickNote = '';
  String get quickNote => _quickNote;

  Future<void> updateQuickNote(String note) async {
    _quickNote = note;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('quickNote', _quickNote);
    if (_user != null) {
      try {
        await _firestoreService.saveQuickNote(_user!.uid, _quickNote);
      } catch (e) {
        debugPrint('Firestore save quickNote error: $e');
      }
    }
  }

  Future<void> addNote(Note note) async {
    _notes.add(note);
    notifyListeners();
    await saveNotes();
  }

  Future<void> updateNote(Note note) async {
    final idx = _notes.indexWhere((n) => n.id == note.id);
    if (idx != -1) {
      _notes[idx] = note;
      notifyListeners();
      await saveNotes();
    }
  }

  Future<void> deleteNote(String noteId) async {
    _notes.removeWhere((n) => n.id == noteId);
    notifyListeners();
    await saveNotes();
  }

  Future<void> saveNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> notesJson = _notes.map((n) => json.encode(n.toJson())).toList();
    await prefs.setStringList('keepNotes', notesJson);
    if (_user != null) {
      try {
        await _firestoreService.saveNotes(_user!.uid, _notes.map((n) => n.toJson()).toList());
      } catch (e) {
        debugPrint('Firestore saveNotes error: $e');
      }
    }
  }

  List<String> _customTaskOrder = [];
  List<String> get customTaskOrder => _customTaskOrder;

  Future<void> updateTaskOrder(List<String> newOrder) async {
    _customTaskOrder = newOrder;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('customTaskOrder', _customTaskOrder);
    if (_user != null) {
      try {
        await _firestoreService.saveTaskOrder(_user!.uid, _customTaskOrder);
      } catch (e) {
        debugPrint('Firestore save taskOrder error: $e');
      }
    }
  }

  List<Serit> _serits = [];
  List<Serit> get serits => _serits;

  bool _showSeritView = false;
  bool get showSeritView => _showSeritView;

  bool _showPlanView = false;
  bool get showPlanView => _showPlanView;

  bool _showRecentView = false;
  bool get showRecentView => _showRecentView;

  List<Topic> _topics = [];
  List<Topic> get topics => _topics;

  List<TopicPlan> _topicPlans = [];
  List<TopicPlan> get topicPlans => _topicPlans;

  bool _isSeritDraftActive = false;
  bool get isSeritDraftActive => _isSeritDraftActive;
  Serit? _draftExistingSerit;
  Serit? get draftExistingSerit => _draftExistingSerit;
  DateTime? _draftStartDate;
  DateTime? get draftStartDate => _draftStartDate;

  void setBulkMode(bool active) {
    _isBulkMode = active;
    if (!active) {
      _selectedEventIds.clear();
    }
    notifyListeners();
  }

  void toggleEventSelection(String id) {
    if (_selectedEventIds.contains(id)) {
      _selectedEventIds.remove(id);
    } else {
      _selectedEventIds.add(id);
    }
    if (_selectedEventIds.isEmpty) {
      _isBulkMode = false;
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedEventIds.clear();
    _isBulkMode = false;
    notifyListeners();
  }

  // Firebase properties
  User? _user;
  String? _firestoreUserId;
  bool _autoSync = true;
  bool _isSyncing = false;
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  StreamSubscription<User?>? _authSub;

  StreamSubscription<List<TaskItem>>? _tasksSubscription;
  StreamSubscription<List<Event>>? _eventsSubscription;
  StreamSubscription<List<Project>>? _projectsSubscription;
  StreamSubscription<List<ProjectEvaluation>>? _evaluationsSubscription;
  StreamSubscription<List<DayNote>>? _dayNotesSubscription;
  StreamSubscription<List<Serit>>? _seritsSubscription;
  StreamSubscription<List<Topic>>? _topicsSubscription;
  StreamSubscription<List<TopicPlan>>? _topicPlansSubscription;

  final Map<String, bool> _eventTagsExpandedState = {};
  final Map<String, bool> _taskTagsExpandedState = {};

  bool isEventTagExpanded(String tag) => _eventTagsExpandedState[tag] ?? true;
  bool isTaskTagExpanded(String tag) => _taskTagsExpandedState[tag] ?? true;

  void setEventTagExpanded(String tag, bool expanded) {
    _eventTagsExpandedState[tag] = expanded;
    _saveExpandedStates();
  }

  void setTaskTagExpanded(String tag, bool expanded) {
    _taskTagsExpandedState[tag] = expanded;
    _saveExpandedStates();
  }

  Future<void> _saveExpandedStates() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'eventTagsExpandedState',
      json.encode(_eventTagsExpandedState),
    );
    await prefs.setString(
      'taskTagsExpandedState',
      json.encode(_taskTagsExpandedState),
    );
  }

  User? get firebaseUser => _user;
  String? get firestoreUserId => _firestoreUserId;
  bool get autoSync => _autoSync;
  bool get isSyncing => _isSyncing;

  // ---- Etkinlik kategorileri ----
  List<String> _eventTags = ['Genel'];
  List<String> _selectedEventTags = ['Genel'];
  Map<String, List<String>> _eventSubTags = {'Genel': []};
  final List<String> _selectedEventSubTags = [];

  // ---- Görev kategorileri ----
  List<String> _taskTags = ['Yapılacaklar'];
  List<String> _selectedTaskTags = ['Yapılacaklar'];
  Map<String, List<String>> _taskSubTags = {'Yapılacaklar': []};
  final List<String> _selectedTaskSubTags = [];

  /// [LEGACY COMPAT] Etkinlik taglarını döner — eski kod için.
  List<String> get availableTags => _eventTags;
  List<String> get selectedTags => _selectedEventTags;
  Map<String, List<String>> get categorySubTags => _eventSubTags;
  List<String> get selectedSubTags => _selectedEventSubTags;

  final List<int> _selectedImportances = [0, 1, 2];
  String _searchQuery = '';
  int _searchResultIndex = 0;
  List<dynamic> _searchResults = [];
  CalendarView _calendarView = CalendarView.month;
  bool _hideEmptyHours = true;
  bool _fitToScreen = false;
  int _firstDayOfWeek = 1; // Default to Monday
  int _currentTabIndex = 0;
  int get currentTabIndex => _currentTabIndex;
  final CalendarController calendarController = CalendarController();
  DateTime _displayDate = DateTime.now();
  bool _showHiddenEvents = false;
  bool get showHiddenEvents => _showHiddenEvents;
  double _fontSizeMultiplier = 1.0;
  double get fontSizeMultiplier => _fontSizeMultiplier;

  bool _isDarkMode = false;
  bool get isDarkMode => _isDarkMode;

  void toggleDarkMode() async {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', _isDarkMode);
  }

  bool _expandShortDuration = false;
  bool get expandShortDuration => _expandShortDuration;

  void toggleExpandShortDuration() {
    _expandShortDuration = !_expandShortDuration;
    notifyListeners();
  }

  List<Event> get events => _events;
  List<TaskItem> get tasks => _tasks;
  List<Project> get projects => _projects;
  List<ProjectEvaluation> get evaluations => _evaluations;
  List<String> get selectedProjectIds => _selectedProjectIds;

  // --- Yeni ayrı kategori getter'ları ---
  List<String> get eventTags => _eventTags;
  List<String> get selectedEventTags => _selectedEventTags;
  Map<String, List<String>> get eventSubTags => _eventSubTags;
  List<String> get selectedEventSubTags => _selectedEventSubTags;

  List<String> get taskTags => _taskTags;
  List<String> get selectedTaskTags => _selectedTaskTags;
  Map<String, List<String>> get taskSubTags => _taskSubTags;
  List<String> get selectedTaskSubTags => _selectedTaskSubTags;

  // ---- Kategori default renkleri ----
  final Map<String, int> _eventTagColors = {};
  final Map<String, int> _taskTagColors = {};

  static const Map<String, int> _builtInTagColors = {
    'Genel': 0xFF2196F3, // blue
    'İş': 0xFF9C27B0, // purple
    'Kişisel': 0xFF4CAF50, // green
    'Eğitim': 0xFFFF9800, // orange
    'Sağlık': 0xFFE91E63, // pink
    'Finans': 0xFF009688, // teal
  };

  int? getEventTagColor(String tag) {
    return _eventTagColors[tag] ?? _builtInTagColors[tag];
  }

  int? getTaskTagColor(String tag) {
    return _taskTagColors[tag] ?? _builtInTagColors[tag];
  }

  void setEventTagColor(String tag, int colorValue) {
    _eventTagColors[tag] = colorValue;
    notifyListeners();
    _saveTagColors();
  }

  void setTaskTagColor(String tag, int colorValue) {
    _taskTagColors[tag] = colorValue;
    notifyListeners();
    _saveTagColors();
  }

  Future<void> _saveTagColors() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'eventTagColors',
      json.encode(_eventTagColors.map((k, v) => MapEntry(k, v))),
    );
    await prefs.setString(
      'taskTagColors',
      json.encode(_taskTagColors.map((k, v) => MapEntry(k, v))),
    );
    if (_user != null) {
      try {
        await _firestoreService.saveCategoryColors(
          _user!.uid,
          _eventTagColors,
          _taskTagColors,
        );
      } catch (e) {
        debugPrint('Firestore save tag colors error: $e');
      }
    }
  }

  Future<void> _loadTagColors(SharedPreferences prefs) async {
    final eventJson = prefs.getString('eventTagColors');
    if (eventJson != null) {
      try {
        final decoded = json.decode(eventJson) as Map<String, dynamic>;
        decoded.forEach((k, v) => _eventTagColors[k] = v as int);
      } catch (_) {}
    }
    final taskJson = prefs.getString('taskTagColors');
    if (taskJson != null) {
      try {
        final decoded = json.decode(taskJson) as Map<String, dynamic>;
        decoded.forEach((k, v) => _taskTagColors[k] = v as int);
      } catch (_) {}
    }
  }

  List<int> get selectedImportances => _selectedImportances;
  String get searchQuery => _searchQuery;
  int get searchResultIndex => _searchResultIndex;
  List<dynamic> get searchResults => _searchResults;
  CalendarView get calendarView => _calendarView;
  bool get hideEmptyHours => _hideEmptyHours;
  bool get fitToScreen => _fitToScreen;
  int get firstDayOfWeek => _firstDayOfWeek;
  DateTime get displayDate => _displayDate;

  void setDisplayDate(DateTime date) {
    if (_displayDate.year != date.year ||
        _displayDate.month != date.month ||
        _displayDate.day != date.day) {
      _displayDate = date;
      notifyListeners();
    }
  }

  /// Etkinlik için tag + subtag filtresi
  bool _matchesEventTagAndSubTag(String tag, String? subTag) {
    if (!_selectedEventTags.contains(tag)) return false;
    final allowedSubTags = _eventSubTags[tag] ?? [];
    if (allowedSubTags.isEmpty) return true;
    if (subTag == null || subTag.trim().isEmpty) return true;
    return _selectedEventSubTags.contains('$tag:$subTag') ||
        _selectedEventSubTags.contains(subTag);
  }

  /// Görev için tag + subtag filtresi
  bool _matchesTaskTagAndSubTag(String tag, String? subTag) {
    if (!_selectedTaskTags.contains(tag)) return false;
    final allowedSubTags = _taskSubTags[tag] ?? [];
    if (allowedSubTags.isEmpty) return true;
    if (subTag == null || subTag.trim().isEmpty) return true;
    return _selectedTaskSubTags.contains('$tag:$subTag') ||
        _selectedTaskSubTags.contains(subTag);
  }

  List<Event> get filteredEvents {
    return _events.where((e) {
      final matchesSearch =
          _searchQuery.isEmpty ||
          e.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          e.description.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesTag = _matchesEventTagAndSubTag(e.tag, e.subTag);
      final matchesImportance = _selectedImportances.contains(e.importance);
      final projectKey = e.projectId ?? 'no_project';
      final matchesProject = _selectedProjectIds.contains(projectKey);
      final matchesHidden = _showHiddenEvents || !e.isHidden;
      return matchesSearch &&
          matchesTag &&
          matchesImportance &&
          matchesProject &&
          matchesHidden;
    }).toList();
  }

  List<TaskItem> get filteredTasks {
    return _tasks.where((t) {
      final matchesSearch =
          _searchQuery.isEmpty ||
          t.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          t.details.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesTag = _matchesTaskTagAndSubTag(t.tag, t.subTag);
      final matchesImportance = _selectedImportances.contains(t.importance);
      final projectKey = t.projectId ?? 'no_project';
      final matchesProject = _selectedProjectIds.contains(projectKey);
      final matchesHidden = _showHiddenEvents || !t.isHidden;
      return matchesSearch &&
          matchesTag &&
          matchesImportance &&
          matchesProject &&
          matchesHidden;
    }).toList();
  }

  List<Project> get filteredProjects {
    return _projects.where((p) {
      final matchesSearch =
          _searchQuery.isEmpty ||
          p.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.description.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesTag = _matchesEventTagAndSubTag(p.tag, p.subTag);
      final isNotArchived = !p.isArchived && p.status != 'COMPLETED';
      return matchesSearch && matchesTag && isNotArchived;
    }).toList();
  }

  AppState() {
    _loadData();
    _authSub = _authService.authStateChanges.listen((user) async {
      _user = user;
      if (user != null) {
        _firestoreUserId = await _firestoreService.getOrCreateSiralId(
          user.uid,
          email: user.email,
        );
        notifyListeners();
        if (_autoSync) {
          await syncDataWithFirebase();
          _startFirestoreListeners(_firestoreUserId!);
        } else {
          _cancelFirestoreListeners();
        }
      } else {
        _firestoreUserId = null;
        _cancelFirestoreListeners();
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _cancelFirestoreListeners();
    super.dispose();
  }

  void _startFirestoreListeners(String userId) {
    _cancelFirestoreListeners();

    _tasksSubscription = _firestoreService.getTasks(userId).listen((
      newTasks,
    ) async {
      // Silinmiş görevleri filtrele; Firestore'da hâlâ duruyorlarsa tekrar sil
      for (final t in newTasks) {
        if (_deletedTaskIds.contains(t.id)) {
          _firestoreDeleteTask(t.id);
        }
      }
      final filtered = newTasks
          .where((t) => !_deletedTaskIds.contains(t.id))
          .toList();
      final oldJson = json.encode(_tasks.map((t) => t.toJson()).toList());
      final newJson = json.encode(filtered.map((t) => t.toJson()).toList());
      if (oldJson != newJson) {
        _tasks = filtered;
        _cleanDuplicateTasks();
        _syncTaskTagsAndSubTags();
        await _saveTasks();
        notifyListeners();
      }
    });

    _eventsSubscription = _firestoreService.getEvents(userId).listen((
      newEvents,
    ) async {
      // Silinmiş etkinlikleri filtrele; Firestore'da hâlâ duruyorlarsa tekrar sil
      for (final e in newEvents) {
        if (_deletedEventIds.contains(e.id)) {
          _firestoreDeleteEvent(e.id);
        }
      }
      final filtered = newEvents
          .where((e) => !_deletedEventIds.contains(e.id))
          .toList();
      final oldJson = json.encode(_events.map((e) => e.toJson()).toList());
      final newJson = json.encode(filtered.map((e) => e.toJson()).toList());
      if (oldJson != newJson) {
        _events = filtered;
        _cleanDuplicateEvents();
        await _saveEvents();
        notifyListeners();
      }
    });

    _projectsSubscription = _firestoreService.getProjects(userId).listen((
      newProjects,
    ) async {
      // Silinmiş projeleri Firestore'dan gelen listeden filtrele
      final filtered = newProjects
          .where((p) => !_deletedProjectIds.contains(p.id))
          .toList();
      // Firestore'da hâlâ duran silinmiş projeleri tekrar sil
      for (final p in newProjects) {
        if (_deletedProjectIds.contains(p.id)) {
          _firestoreDeleteProject(p.id);
        }
      }
      final oldJson = json.encode(_projects.map((p) => p.toJson()).toList());
      final newJson = json.encode(filtered.map((p) => p.toJson()).toList());
      if (oldJson != newJson) {
        _projects = filtered;
        await _saveProjects();
        _initSelectedProjectIdsIfNeeded();
        notifyListeners();
      } else {
        _initSelectedProjectIdsIfNeeded();
      }
    });

    _evaluationsSubscription = _firestoreService.getEvaluations(userId).listen((
      newEvals,
    ) async {
      final oldJson = json.encode(_evaluations.map((e) => e.toJson()).toList());
      final newJson = json.encode(newEvals.map((e) => e.toJson()).toList());
      if (oldJson != newJson) {
        _evaluations = newEvals;
        await _saveEvaluations();
        notifyListeners();
      }
    });

    _dayNotesSubscription = _firestoreService.getDayNotes(userId).listen((
      newNotes,
    ) async {
      // Silinmiş notları Firestore'dan gelen listeden filtrele
      final filtered = newNotes
          .where((n) => !_deletedDayNoteIds.contains(n.id))
          .toList();
      // Firestore'da hâlâ duran silinmiş notları tekrar sil
      for (final n in newNotes) {
        if (_deletedDayNoteIds.contains(n.id)) {
          _firestoreDeleteDayNote(n.id);
        }
      }
      final oldJson = json.encode(_dayNotes.map((n) => n.toJson()).toList());
      final newJson = json.encode(filtered.map((n) => n.toJson()).toList());
      if (oldJson != newJson) {
        _dayNotes = filtered;
        await _saveDayNotes();
        notifyListeners();
      }
    });

    _seritsSubscription = _firestoreService.getSerits(userId).listen((
      newSerits,
    ) async {
      final oldJson = json.encode(_serits.map((s) => s.toJson()).toList());
      final newJson = json.encode(newSerits.map((s) => s.toJson()).toList());
      if (oldJson != newJson) {
        _serits = newSerits;
        await _saveSerits();
        notifyListeners();
      }
    });

    _topicsSubscription = _firestoreService.getTopics(userId).listen((
      newTopics,
    ) async {
      final oldJson = json.encode(_topics.map((t) => t.toJson()).toList());
      final newJson = json.encode(newTopics.map((t) => t.toJson()).toList());
      if (oldJson != newJson) {
        _topics = newTopics;
        await _saveTopics();
        notifyListeners();
      }
    });

    _topicPlansSubscription = _firestoreService.getTopicPlans(userId).listen((
      newPlans,
    ) async {
      final oldJson = json.encode(_topicPlans.map((p) => p.toJson()).toList());
      final newJson = json.encode(newPlans.map((p) => p.toJson()).toList());
      if (oldJson != newJson) {
        _topicPlans = newPlans;
        _runWaitingPlansCatchUp();
        await _saveTopicPlans();
        notifyListeners();
      }
    });
  }

  void _cancelFirestoreListeners() {
    _tasksSubscription?.cancel();
    _eventsSubscription?.cancel();
    _projectsSubscription?.cancel();
    _evaluationsSubscription?.cancel();
    _dayNotesSubscription?.cancel();
    _seritsSubscription?.cancel();
    _topicsSubscription?.cancel();
    _topicPlansSubscription?.cancel();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _autoSync = prefs.getBool('autoSync') ?? true;
    _deletedTaskIds = prefs.getStringList('deletedTaskIds') ?? [];
    _deletedEventIds = prefs.getStringList('deletedEventIds') ?? [];
    _deletedDayNoteIds = prefs.getStringList('deletedDayNoteIds') ?? [];
    _deletedProjectIds = prefs.getStringList('deletedProjectIds') ?? [];

    final eventsJson = prefs.getStringList('events') ?? [];
    _events = [];
    for (final e in eventsJson) {
      try {
        _events.add(Event.fromJson(json.decode(e)));
      } catch (err) {
        debugPrint('Error loading event: $err');
      }
    }

    final tasksJson = prefs.getStringList('tasks') ?? [];
    _tasks = [];
    for (final t in tasksJson) {
      try {
        _tasks.add(TaskItem.fromJson(json.decode(t)));
      } catch (err) {
        debugPrint('Error loading task: $err');
      }
    }

    final projectsJson = prefs.getStringList('projects') ?? [];
    _projects = [];
    for (final p in projectsJson) {
      try {
        _projects.add(Project.fromJson(json.decode(p)));
      } catch (err) {
        debugPrint('Error loading project: $err');
      }
    }

    final evaluationsJson = prefs.getStringList('evaluations') ?? [];
    _evaluations = [];
    for (final ev in evaluationsJson) {
      try {
        _evaluations.add(ProjectEvaluation.fromJson(json.decode(ev)));
      } catch (err) {
        debugPrint('Error loading evaluation: $err');
      }
    }

    final dayNotesJson = prefs.getStringList('dayNotes') ?? [];
    _dayNotes = [];
    for (final n in dayNotesJson) {
      try {
        _dayNotes.add(DayNote.fromJson(json.decode(n)));
      } catch (err) {
        debugPrint('Error loading day note: $err');
      }
    }

    final keepNotesJson = prefs.getStringList('keepNotes') ?? [];
    _notes = [];
    for (final n in keepNotesJson) {
      try {
        _notes.add(Note.fromJson(json.decode(n)));
      } catch (err) {
        debugPrint('Error loading note: $err');
      }
    }

    _quickNote = prefs.getString('quickNote') ?? '';
    _customTaskOrder = prefs.getStringList('customTaskOrder') ?? [];
    _firstDayOfWeek = prefs.getInt('firstDayOfWeek') ?? 1;
    final savedProjects = prefs.getStringList('selectedProjectIds');
    if (savedProjects != null) {
      _selectedProjectIds = savedProjects;
      _selectedProjectIdsNeedsInit = false;
    } else {
      _selectedProjectIds = ['no_project', ..._projects.map((p) => p.id)];
      _selectedProjectIdsNeedsInit = true;
    }
    _showHiddenEvents = prefs.getBool('showHiddenEvents') ?? false;
    _fontSizeMultiplier = prefs.getDouble('fontSizeMultiplier') ?? 1.0;
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    _initSelectedProjectIdsIfNeeded();

    final eventExpandedJson = prefs.getString('eventTagsExpandedState');
    if (eventExpandedJson != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(eventExpandedJson);
        decoded.forEach((key, value) {
          _eventTagsExpandedState[key] = value as bool;
        });
      } catch (e) {
        debugPrint('Error loading event expanded states: $e');
      }
    }

    final taskExpandedJson = prefs.getString('taskTagsExpandedState');
    if (taskExpandedJson != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(taskExpandedJson);
        decoded.forEach((key, value) {
          _taskTagsExpandedState[key] = value as bool;
        });
      } catch (e) {
        debugPrint('Error loading task expanded states: $e');
      }
    }

    // ---- Yeni etkinlik kategorileri ----
    final savedEventTags = prefs.getStringList('eventTags');
    final savedEventSubTagsJson = prefs.getString('eventSubTags');

    // ---- Yeni görev kategorileri ----
    final savedTaskTags = prefs.getStringList('taskTags');
    final savedTaskSubTagsJson = prefs.getString('taskSubTags');

    // ---- MIGRATION: eski 'availableTags' var mı? ----
    final legacyTags = prefs.getStringList('availableTags');
    final legacySubTagsJson = prefs.getString('categorySubTags');
    Map<String, List<String>> legacySubTagsMap = {};
    if (legacySubTagsJson != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(legacySubTagsJson);
        legacySubTagsMap = decoded.map(
          (key, value) => MapEntry(key, List<String>.from(value)),
        );
      } catch (e) {
        debugPrint('Error loading legacy tags: $e');
      }
    }

    // Etkinlik kategorileri yükleme
    if (savedEventTags != null) {
      _eventTags = savedEventTags;
      _selectedEventTags = List<String>.from(savedEventTags);
    } else if (legacyTags != null) {
      // Migration: eski listeyi kopyala
      _eventTags = List<String>.from(legacyTags);
      _selectedEventTags = List<String>.from(legacyTags);
    }
    if (savedEventSubTagsJson != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(savedEventSubTagsJson);
        _eventSubTags = decoded.map(
          (key, value) => MapEntry(key, List<String>.from(value)),
        );
      } catch (e) {
        debugPrint('Error loading eventSubTags: $e');
      }
    } else if (legacySubTagsMap.isNotEmpty) {
      _eventSubTags = Map<String, List<String>>.from(legacySubTagsMap);
    }
    // Alt etiketleri seçili yap
    _selectedEventSubTags.clear();
    _eventSubTags.forEach((tag, list) {
      for (var sub in list) {
        _selectedEventSubTags.add('$tag:$sub');
      }
    });

    // Görev kategorileri yükleme
    if (savedTaskTags != null) {
      _taskTags = savedTaskTags;
      _selectedTaskTags = List<String>.from(savedTaskTags);
    } else if (legacyTags != null) {
      // Migration: eski listeyi kopyala; ayrıca görevlerde kullanılan tag'ları ekle
      _taskTags = List<String>.from(legacyTags);
      // Görevlerdeki benzersiz tag'ları da ekle
      for (var task in _tasks) {
        if (task.tag.isNotEmpty && !_taskTags.contains(task.tag)) {
          _taskTags.add(task.tag);
        }
      }
      _selectedTaskTags = List<String>.from(_taskTags);
    }
    if (savedTaskSubTagsJson != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(savedTaskSubTagsJson);
        _taskSubTags = decoded.map(
          (key, value) => MapEntry(key, List<String>.from(value)),
        );
      } catch (e) {
        debugPrint('Error loading taskSubTags: $e');
      }
    } else if (legacySubTagsMap.isNotEmpty) {
      _taskSubTags = Map<String, List<String>>.from(legacySubTagsMap);
    }
    // Alt etiketleri seçili yap
    _selectedTaskSubTags.clear();
    _taskSubTags.forEach((tag, list) {
      for (var sub in list) {
        _selectedTaskSubTags.add('$tag:$sub');
      }
    });

    // Migration tamamlandıysa eski anahtarları temizle
    if (legacyTags != null) {
      await prefs.remove('availableTags');
      await prefs.remove('categorySubTags');
      debugPrint('Category migration completed: legacy keys removed.');
    }

    // Kategori renk haritalarını yükle
    await _loadTagColors(prefs);
    _syncTaskTagsAndSubTags();

    final paintedJson = prefs.getString('paintedDays');
    if (paintedJson != null) {
      try {
        final Map<String, dynamic> decoded = json.decode(paintedJson);
        _paintedDays = decoded.map(
          (key, value) => MapEntry(key, value.toString()),
        );
      } catch (e) {
        debugPrint('Error loading painted days: $e');
      }
    }

    final seritsJson =
        prefs.getStringList('serits') ?? prefs.getStringList('macros') ?? [];
    _serits = [];
    for (final m in seritsJson) {
      try {
        _serits.add(Serit.fromJson(json.decode(m)));
      } catch (err) {
        debugPrint('Error loading serit: $err');
      }
    }

    final topicsJson = prefs.getStringList('topics') ?? [];
    _topics = [];
    for (final t in topicsJson) {
      try {
        _topics.add(Topic.fromJson(json.decode(t)));
      } catch (err) {
        debugPrint('Error loading topic: $err');
      }
    }

    final plansJson = prefs.getStringList('topicPlans') ?? [];
    _topicPlans = [];
    for (final p in plansJson) {
      try {
        _topicPlans.add(TopicPlan.fromJson(json.decode(p)));
      } catch (err) {
        debugPrint('Error loading topicPlan: $err');
      }
    }

    _runWaitingPlansCatchUp();
    _cleanDuplicateTasks();
    _cleanDuplicateEvents();

    notifyListeners();
  }

  void _cleanDuplicateTasks() {
    final Map<String, TaskItem> uniqueActiveTasks = {};
    final Map<String, TaskItem> uniqueCompletedTasks = {};
    final List<TaskItem> duplicatesToRemove = [];

    for (var t in _tasks) {
      if (t.isCompleted) {
        if (t.from != null) {
          final dateKey = "${t.from!.year}-${t.from!.month}-${t.from!.day}";
          final uniqueKey =
              "${t.title.trim()}_${t.details.trim()}_${t.tag}_$dateKey";
          if (uniqueCompletedTasks.containsKey(uniqueKey)) {
            duplicatesToRemove.add(t);
          } else {
            uniqueCompletedTasks[uniqueKey] = t;
          }
        }
      } else {
        final hasRecurrence =
            t.recurrenceRule != null && t.recurrenceRule!.isNotEmpty;
        final fromKey = (t.from != null && !hasRecurrence)
            ? "${t.from!.year}-${t.from!.month}-${t.from!.day}"
            : "no_date";
        final ruleKey = t.recurrenceRule ?? "no_rule";
        final uniqueKey =
            "${t.title.trim()}_${t.details.trim()}_${t.tag}_${fromKey}_$ruleKey";
        if (uniqueActiveTasks.containsKey(uniqueKey)) {
          duplicatesToRemove.add(t);
        } else {
          uniqueActiveTasks[uniqueKey] = t;
        }
      }
    }

    // Force cleanup the specifically bugged task if it exists
    final buggedTasks = _tasks
        .where(
          (t) =>
              t.id == '9b30376b-41ba-4cb7-900b-6bf8086b829d' ||
              t.title.trim() ==
                  'Change the bed sheets and let the bed air out.',
        )
        .toList();
    if (buggedTasks.isNotEmpty) {
      for (var t in buggedTasks) {
        _tasks.removeWhere((item) => item.id == t.id);
        _firestoreDeleteTask(t.id);
      }
      _saveTasks();
    }

    if (duplicatesToRemove.isNotEmpty) {
      debugPrint('Cleaning up ${duplicatesToRemove.length} duplicate tasks...');
      for (var t in duplicatesToRemove) {
        _tasks.removeWhere((item) => item.id == t.id);
        _firestoreDeleteTask(t.id);
      }
      _saveTasks();
    }
  }

  void _syncTaskTagsAndSubTags() {
    bool changed = false;
    for (var task in _tasks) {
      if (task.tag.isNotEmpty) {
        if (!_taskTags.contains(task.tag)) {
          _taskTags.add(task.tag);
          changed = true;
        }
        if (task.subTag != null && task.subTag!.trim().isNotEmpty) {
          final subList = _taskSubTags.putIfAbsent(task.tag, () => []);
          if (!subList.contains(task.subTag)) {
            subList.add(task.subTag!);
            changed = true;
          }
        }
      }
    }

    // Ensure all subTags in the map are selected in memory
    _taskSubTags.forEach((tag, list) {
      for (var sub in list) {
        final key = '$tag:$sub';
        if (!_selectedTaskSubTags.contains(key)) {
          _selectedTaskSubTags.add(key);
        }
      }
    });

    if (changed) {
      _saveTaskTagsAndSubTagsToPrefs();
    }
  }

  Future<void> _saveTaskTagsAndSubTagsToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('taskTags', _taskTags);
    await prefs.setString('taskSubTags', json.encode(_taskSubTags));
  }

  void _cleanDuplicateEvents() {
    final Map<String, Event> uniqueEvents = {};
    final List<Event> duplicatesToRemove = [];

    for (var e in _events) {
      final hasRecurrence =
          e.recurrenceRule != null && e.recurrenceRule!.isNotEmpty;
      final fromKey = !hasRecurrence
          ? "${e.from.year}-${e.from.month}-${e.from.day}"
          : "no_date";
      final ruleKey = e.recurrenceRule ?? "no_rule";
      final uniqueKey =
          "${e.title.trim()}_${e.description.trim()}_${e.tag}_${fromKey}_$ruleKey";
      if (uniqueEvents.containsKey(uniqueKey)) {
        duplicatesToRemove.add(e);
      } else {
        uniqueEvents[uniqueKey] = e;
      }
    }

    if (duplicatesToRemove.isNotEmpty) {
      debugPrint(
        'Cleaning up ${duplicatesToRemove.length} duplicate events...',
      );
      for (var e in duplicatesToRemove) {
        _events.removeWhere((item) => item.id == e.id);
        _firestoreDeleteEvent(e.id);
      }
      _saveEvents();
    }
  }

  Future<void> _saveEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final eventsJson = _events.map((e) => json.encode(e.toJson())).toList();
    await prefs.setStringList('events', eventsJson);
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final tasksJson = _tasks.map((t) => json.encode(t.toJson())).toList();
    await prefs.setStringList('tasks', tasksJson);
  }

  Future<void> _saveProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final projectsJson = _projects.map((p) => json.encode(p.toJson())).toList();
    await prefs.setStringList('projects', projectsJson);
  }

  Future<void> _saveEvaluations() async {
    final prefs = await SharedPreferences.getInstance();
    final evalsJson = _evaluations.map((e) => json.encode(e.toJson())).toList();
    await prefs.setStringList('evaluations', evalsJson);
  }

  Future<void> _saveDayNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final notesJson = _dayNotes.map((n) => json.encode(n.toJson())).toList();
    await prefs.setStringList('dayNotes', notesJson);
  }

  void addEvent(Event event) {
    _deletedEventIds.remove(event.id);
    _saveDeletedIds();
    _events.add(event);
    notifyListeners();
    _saveEvents();
    _firestoreSaveEvent(event);
    NotificationService.scheduleEventNotifications(event);
  }

  void updateEvent(Event event) {
    _deletedEventIds.remove(event.id);
    _saveDeletedIds();
    final index = _events.indexWhere((e) => e.id == event.id);
    if (index != -1) {
      _events[index] = event;
      notifyListeners();
      _saveEvents();
      _firestoreSaveEvent(event);
      NotificationService.scheduleEventNotifications(event);
    }
  }

  void deleteEvent(String id) {
    if (!_deletedEventIds.contains(id)) {
      _deletedEventIds.add(id);
      _saveDeletedIds();
    }
    final index = _events.indexWhere((e) => e.id == id);
    if (index != -1) {
      final oldEvent = _events[index];
      NotificationService.cancelEventNotifications(oldEvent);
      _events.removeAt(index);
      notifyListeners();
      _saveEvents();
      _firestoreDeleteEvent(id);
    }
  }

  void toggleShowHiddenEvents() async {
    _showHiddenEvents = !_showHiddenEvents;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showHiddenEvents', _showHiddenEvents);
  }

  void hideEvent(String id, bool hide) {
    final index = _events.indexWhere((e) => e.id == id);
    if (index != -1) {
      _events[index] = _events[index].copyWith(isHidden: hide);
      notifyListeners();
      _saveEvents();
      _firestoreSaveEvent(_events[index]);
    }
  }

  void hideTask(String id, bool hide) {
    if (id.startsWith('rollover_')) {
      id = id.substring(9);
    }
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index != -1) {
      _tasks[index] = _tasks[index].copyWith(isHidden: hide);
      notifyListeners();
      _saveTasks();
      _firestoreSaveTask(_tasks[index]);
    }
  }

  void bulkHideEvents(List<String> ids, bool hide) {
    for (final id in ids) {
      if (id.contains('_')) {
        final parts = id.split('_');
        final parentId = parts[0];
        final timestampStr = parts[1];
        final timestamp = int.tryParse(timestampStr);
        if (timestamp != null) {
          final occDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
          final parentIndex = _events.indexWhere((e) => e.id == parentId);
          if (parentIndex != -1) {
            final parentEvent = _events[parentIndex];
            List<DateTime> exceptions = List.from(
              parentEvent.recurrenceExceptionDates ?? [],
            );
            exceptions.add(occDate);
            _events[parentIndex] = parentEvent.copyWith(
              recurrenceExceptionDates: exceptions,
            );
            _firestoreSaveEvent(_events[parentIndex]);

            DateTime originalStart = parentEvent.from;
            DateTime occurrenceStart = DateTime(
              occDate.year,
              occDate.month,
              occDate.day,
              originalStart.hour,
              originalStart.minute,
              originalStart.second,
            );
            DateTime originalEnd = parentEvent.to;
            Duration duration = originalEnd.difference(originalStart);
            DateTime occurrenceEnd = occurrenceStart.add(duration);

            final clone = parentEvent.copyWith(
              id: IdGenerator.generate(
                '${parentEvent.title}_istisna_tekrar',
                date: occurrenceStart,
              ),
              from: occurrenceStart,
              to: occurrenceEnd,
              clearRecurrenceRule: true,
              clearRecurrenceExceptionDates: true,
              isHidden: hide,
            );
            _events.add(clone);
            _firestoreSaveEvent(clone);
          }
        }
      } else {
        final index = _events.indexWhere((e) => e.id == id);
        if (index != -1) {
          _events[index] = _events[index].copyWith(isHidden: hide);
          _firestoreSaveEvent(_events[index]);
        }
      }
    }
    notifyListeners();
    _saveEvents();
  }

  void bulkDeleteEvents(List<String> ids) {
    for (final id in ids) {
      if (id.contains('_')) {
        final parts = id.split('_');
        final parentId = parts[0];
        final timestampStr = parts[1];
        final timestamp = int.tryParse(timestampStr);
        if (timestamp != null) {
          final occDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
          final parentIndex = _events.indexWhere((e) => e.id == parentId);
          if (parentIndex != -1) {
            final parentEvent = _events[parentIndex];
            List<DateTime> exceptions = List.from(
              parentEvent.recurrenceExceptionDates ?? [],
            );
            exceptions.add(occDate);
            _events[parentIndex] = parentEvent.copyWith(
              recurrenceExceptionDates: exceptions,
            );
            _firestoreSaveEvent(_events[parentIndex]);
            NotificationService.scheduleEventNotifications(
              _events[parentIndex],
            );
          }
        }
      } else {
        final index = _events.indexWhere((e) => e.id == id);
        if (index != -1) {
          NotificationService.cancelEventNotifications(_events[index]);
          _events.removeAt(index);
          _firestoreDeleteEvent(id);
        }
      }
    }
    notifyListeners();
    _saveEvents();
  }

  void bulkEditEvents({
    required List<String> ids,
    String? title,
    String? description,
    String? tag,
    String? subTag,
    int? importance,
    String? projectId,
    int? colorValue,
    DateTime? newFrom,
    DateTime? newTo,
    bool? newIsAllDay,
    bool? newIsTrackingEnabled,
  }) {
    for (final id in ids) {
      if (id.contains('_')) {
        final parts = id.split('_');
        final parentId = parts[0];
        final timestampStr = parts[1];
        final timestamp = int.tryParse(timestampStr);
        if (timestamp != null) {
          final occDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
          final parentIndex = _events.indexWhere((e) => e.id == parentId);
          if (parentIndex != -1) {
            final parentEvent = _events[parentIndex];

            List<DateTime> exceptions = List.from(
              parentEvent.recurrenceExceptionDates ?? [],
            );
            exceptions.add(occDate);
            _events[parentIndex] = parentEvent.copyWith(
              recurrenceExceptionDates: exceptions,
            );
            _firestoreSaveEvent(_events[parentIndex]);

            DateTime originalStart = parentEvent.from;
            DateTime occurrenceStart = DateTime(
              occDate.year,
              occDate.month,
              occDate.day,
              originalStart.hour,
              originalStart.minute,
              originalStart.second,
            );
            DateTime originalEnd = parentEvent.to;
            Duration duration = originalEnd.difference(originalStart);
            DateTime occurrenceEnd = occurrenceStart.add(duration);

            final finalTitle = title ?? parentEvent.title;
            final finalDescription = description ?? parentEvent.description;
            final finalTag = tag ?? parentEvent.tag;

            String? finalSubTag = subTag;
            if (tag != null && subTag == null) {
              final allowedSubTags = _eventSubTags[finalTag] ?? [];
              if (parentEvent.subTag != null &&
                  allowedSubTags.contains(parentEvent.subTag)) {
                finalSubTag = parentEvent.subTag;
              } else {
                finalSubTag = null;
              }
            } else if (subTag == null) {
              finalSubTag = parentEvent.subTag;
            }

            final finalImportance = importance ?? parentEvent.importance;
            final finalProjectId = projectId == 'clear_project'
                ? null
                : (projectId ?? parentEvent.projectId);
            final finalColorValue = colorValue ?? parentEvent.colorValue;

            DateTime cloneFrom = newFrom ?? occurrenceStart;
            DateTime cloneTo = newTo ?? occurrenceEnd;
            bool cloneIsAllDay = newIsAllDay ?? parentEvent.isAllDay;
            bool cloneIsTrackingEnabled =
                newIsTrackingEnabled ?? parentEvent.isTrackingEnabled;

            final clone = Event(
              id: IdGenerator.generate(
                '${finalTitle}_istisna_tekrar',
                date: cloneFrom,
              ),
              title: finalTitle,
              description: finalDescription,
              from: cloneFrom,
              to: cloneTo,
              isAllDay: cloneIsAllDay,
              colorValue: finalColorValue,
              tag: finalTag,
              subTag: finalSubTag,
              importance: finalImportance,
              reminderTime: parentEvent.reminderTime,
              recurrenceRule: null,
              recurrenceExceptionDates: null,
              projectId: finalProjectId,
              isTrackingEnabled: cloneIsTrackingEnabled,
            );
            _events.add(clone);
            _firestoreSaveEvent(clone);
            NotificationService.scheduleEventNotifications(clone);
            NotificationService.scheduleEventNotifications(
              _events[parentIndex],
            );
          }
        }
      } else {
        final index = _events.indexWhere((e) => e.id == id);
        if (index != -1) {
          final existing = _events[index];
          String finalTag = tag ?? existing.tag;
          String? finalSubTag = subTag;
          if (tag != null && subTag == null) {
            final allowedSubTags = _eventSubTags[finalTag] ?? [];
            if (existing.subTag != null &&
                allowedSubTags.contains(existing.subTag)) {
              finalSubTag = existing.subTag;
            } else {
              finalSubTag = null;
            }
          } else if (subTag == null) {
            finalSubTag = existing.subTag;
          }

          _events[index] = existing.copyWith(
            title: title ?? existing.title,
            description: description ?? existing.description,
            tag: finalTag,
            subTag: finalSubTag,
            importance: importance ?? existing.importance,
            projectId: projectId == 'clear_project'
                ? null
                : (projectId ?? existing.projectId),
            colorValue: colorValue ?? existing.colorValue,
            from: newFrom ?? existing.from,
            to: newTo ?? existing.to,
            isAllDay: newIsAllDay ?? existing.isAllDay,
            isTrackingEnabled:
                newIsTrackingEnabled ?? existing.isTrackingEnabled,
          );
          _firestoreSaveEvent(_events[index]);
          NotificationService.scheduleEventNotifications(_events[index]);
        }
      }
    }
    notifyListeners();
    _saveEvents();
  }

  List<TaskItem> get expandedTasks {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime endLimit = today.add(const Duration(days: 365));

    final List<TaskItem> result = [];

    for (var t in filteredTasks) {
      if (t.recurrenceRule == null ||
          t.recurrenceRule!.isEmpty ||
          t.from == null) {
        result.add(t);
        continue;
      }

      if (t.isCompleted) {
        result.add(t);
        continue;
      }
      try {
        final List<DateTime> occurrences = RecurrenceHelper.getOccurrences(
          rrule: t.recurrenceRule!,
          startDate: t.from!,
          specificStartDate: t.from!,
          specificEndDate: t.from!.isUtc
              ? endLimit.toUtc()
              : endLimit.toLocal(),
        );

        final List<DateTime> filteredOccurrences = [];
        for (var occ in occurrences) {
          bool isException =
              t.recurrenceExceptionDates?.any(
                (ex) =>
                    ex.year == occ.year &&
                    ex.month == occ.month &&
                    ex.day == occ.day,
              ) ??
              false;
          if (!isException) {
            filteredOccurrences.add(occ);
          }
        }

        final List<DateTime> pastOccs = [];
        final List<DateTime> futureOccs = [];

        for (var occ in filteredOccurrences) {
          if (occ.isBefore(now)) {
            pastOccs.add(occ);
          } else {
            futureOccs.add(occ);
          }
        }

        // Add all past occurrences
        for (var occ in pastOccs) {
          final duration = t.to != null
              ? t.to!.difference(t.from!)
              : const Duration(hours: 1);
          final occEnd = occ.add(duration);

          result.add(
            t.copyWith(
              id: 'occ_${t.id}_${occ.millisecondsSinceEpoch}',
              from: occ,
              to: occEnd,
              parentTaskId: t.id,
              clearRecurrenceRule: true,
              clearRecurrenceExceptionDates: true,
            ),
          );
        }

        // Add ONLY the single next future occurrence
        if (futureOccs.isNotEmpty) {
          futureOccs.sort();
          final nextOcc = futureOccs.first;
          final duration = t.to != null
              ? t.to!.difference(t.from!)
              : const Duration(hours: 1);
          final occEnd = nextOcc.add(duration);

          result.add(
            t.copyWith(
              id: 'occ_${t.id}_${nextOcc.millisecondsSinceEpoch}',
              from: nextOcc,
              to: occEnd,
              parentTaskId: t.id,
              recurrenceRuleForDisplay: t.recurrenceRule,
              clearRecurrenceRule: true,
              clearRecurrenceExceptionDates: true,
            ),
          );
        }
      } catch (e) {
        debugPrint('Error expanding recurrence rule: $e');
        result.add(t);
      }
    }

    result.sort((a, b) {
      if (a.from == null && b.from == null) return 0;
      if (a.from == null) return -1; // Null (tarihsiz) görevler en üste
      if (b.from == null) return 1;
      return a.from!.compareTo(b.from!);
    });

    return result;
  }

  List<TaskItem> get allExpandedTasks {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime endLimit = today.add(const Duration(days: 365));

    final List<TaskItem> result = [];

    final unfilteredTasks = _tasks.where((t) {
      final matchesSearch =
          _searchQuery.isEmpty ||
          t.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          t.details.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesImportance = _selectedImportances.contains(t.importance);
      final projectKey = t.projectId ?? 'no_project';
      final matchesProject = _selectedProjectIds.contains(projectKey);
      final matchesHidden = _showHiddenEvents || !t.isHidden;
      return matchesSearch &&
          matchesImportance &&
          matchesProject &&
          matchesHidden;
    }).toList();

    for (var t in unfilteredTasks) {
      if (t.recurrenceRule == null ||
          t.recurrenceRule!.isEmpty ||
          t.from == null) {
        result.add(t);
        continue;
      }

      if (t.isCompleted) {
        result.add(t);
        continue;
      }
      try {
        final List<DateTime> occurrences = RecurrenceHelper.getOccurrences(
          rrule: t.recurrenceRule!,
          startDate: t.from!,
          specificStartDate: t.from!,
          specificEndDate: t.from!.isUtc
              ? endLimit.toUtc()
              : endLimit.toLocal(),
        );

        final List<DateTime> filteredOccurrences = [];
        for (var occ in occurrences) {
          bool isException =
              t.recurrenceExceptionDates?.any(
                (ex) =>
                    ex.year == occ.year &&
                    ex.month == occ.month &&
                    ex.day == occ.day,
              ) ??
              false;
          if (!isException) {
            filteredOccurrences.add(occ);
          }
        }

        final List<DateTime> pastOccs = [];
        final List<DateTime> futureOccs = [];

        for (var occ in filteredOccurrences) {
          if (occ.isBefore(now)) {
            pastOccs.add(occ);
          } else {
            futureOccs.add(occ);
          }
        }

        // Add all past occurrences
        for (var occ in pastOccs) {
          final duration = t.to != null
              ? t.to!.difference(t.from!)
              : const Duration(hours: 1);
          final occEnd = occ.add(duration);

          result.add(
            t.copyWith(
              id: 'occ_${t.id}_${occ.millisecondsSinceEpoch}',
              from: occ,
              to: occEnd,
              parentTaskId: t.id,
              clearRecurrenceRule: true,
              clearRecurrenceExceptionDates: true,
            ),
          );
        }

        // Add ONLY the single next future occurrence
        if (futureOccs.isNotEmpty) {
          futureOccs.sort();
          final nextOcc = futureOccs.first;
          final duration = t.to != null
              ? t.to!.difference(t.from!)
              : const Duration(hours: 1);
          final occEnd = nextOcc.add(duration);

          result.add(
            t.copyWith(
              id: 'occ_${t.id}_${nextOcc.millisecondsSinceEpoch}',
              from: nextOcc,
              to: occEnd,
              parentTaskId: t.id,
              recurrenceRuleForDisplay: t.recurrenceRule,
              clearRecurrenceRule: true,
              clearRecurrenceExceptionDates: true,
            ),
          );
        }
      } catch (e) {
        debugPrint('Error expanding recurrence rule: $e');
        result.add(t);
      }
    }

    result.sort((a, b) {
      if (a.from == null && b.from == null) return 0;
      if (a.from == null) return -1; // Null (tarihsiz) görevler en üste
      if (b.from == null) return 1;
      return a.from!.compareTo(b.from!);
    });

    return result;
  }

  void addTask(TaskItem task) {
    _deletedTaskIds.remove(task.id);
    _saveDeletedIds();
    _tasks.add(task);
    _syncTaskTagsAndSubTags();
    NotificationService.scheduleTaskNotifications(task);
    notifyListeners();
    _saveTasks();
    _firestoreSaveTask(task);
  }

  void updateTask(TaskItem task) {
    _deletedTaskIds.remove(task.id);
    _saveDeletedIds();
    final index = _tasks.indexWhere((t) => t.id == task.id);
    if (index != -1) {
      _tasks[index] = task;
      _syncTaskTagsAndSubTags();
      NotificationService.scheduleTaskNotifications(task);
      notifyListeners();
      _saveTasks();
      _firestoreSaveTask(task);
    }
  }

  void toggleTaskCompletion(String id) {
    if (id.startsWith('rollover_')) {
      id = id.substring(9);
    }
    if (id.startsWith('occ_')) {
      final lastUnderscore = id.lastIndexOf('_');
      if (lastUnderscore > 4) {
        final parentId = id.substring(4, lastUnderscore);
        final timestampStr = id.substring(lastUnderscore + 1);
        final timestamp = int.tryParse(timestampStr);
        if (timestamp != null) {
          final occDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
          final parentIndex = _tasks.indexWhere((t) => t.id == parentId);
          if (parentIndex != -1) {
            final parentTask = _tasks[parentIndex];
            final exceptions = List<DateTime>.from(
              parentTask.recurrenceExceptionDates ?? [],
            );
            exceptions.add(occDate);
            _tasks[parentIndex] = parentTask.copyWith(
              recurrenceExceptionDates: exceptions,
            );

            final uuid = const Uuid();
            final duration = parentTask.to != null
                ? parentTask.to!.difference(parentTask.from!)
                : const Duration(hours: 1);
            final occEnd = occDate.add(duration);

            final completedClone = TaskItem(
              id: uuid.v4(),
              title: parentTask.title,
              details: parentTask.details,
              isCompleted: true,
              from: occDate,
              to: occEnd,
              isAllDay: parentTask.isAllDay,
              colorValue: parentTask.colorValue,
              tag: parentTask.tag,
              importance: parentTask.importance,
              projectId: parentTask.projectId,
              recurrenceRule: null,
              recurrenceExceptionDates: null,
              seriesId: parentTask.seriesId,
            );
            _tasks.add(completedClone);
            notifyListeners();
            _saveTasks();
            _firestoreSaveTask(
              parentTask.copyWith(recurrenceExceptionDates: exceptions),
            );
            _firestoreSaveTask(completedClone);
            return;
          }
        }
      }
    }

    final index = _tasks.indexWhere((t) => t.id == id);
    if (index != -1) {
      final newCompleted = !_tasks[index].isCompleted;
      _tasks[index] = _tasks[index].copyWith(
        isCompleted: newCompleted,
        isInProgress: newCompleted ? false : _tasks[index].isInProgress,
      );
      if (_tasks[index].isCompleted) {
        NotificationService.cancelTaskNotifications(_tasks[index]);
      } else {
        NotificationService.scheduleTaskNotifications(_tasks[index]);
      }
      notifyListeners();
      _saveTasks();
      _firestoreSaveTask(_tasks[index]);
    }
  }

  void _initSelectedProjectIdsIfNeeded() {
    if (_selectedProjectIdsNeedsInit && _projects.isNotEmpty) {
      _selectedProjectIds = ['no_project', ..._projects.map((p) => p.id)];
      _selectedProjectIdsNeedsInit = false;
      _saveSelectedProjectIds();
    }
  }

  void toggleTaskInProgress(String id) {
    if (id.startsWith('rollover_')) {
      id = id.substring(9);
    }
    if (id.startsWith('occ_')) {
      final lastUnderscore = id.lastIndexOf('_');
      if (lastUnderscore > 4) {
        final parentId = id.substring(4, lastUnderscore);
        final timestampStr = id.substring(lastUnderscore + 1);
        final timestamp = int.tryParse(timestampStr);
        if (timestamp != null) {
          final occDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
          final parentIndex = _tasks.indexWhere((t) => t.id == parentId);
          if (parentIndex != -1) {
            final parentTask = _tasks[parentIndex];
            final exceptions = List<DateTime>.from(
              parentTask.recurrenceExceptionDates ?? [],
            );
            exceptions.add(occDate);
            _tasks[parentIndex] = parentTask.copyWith(
              recurrenceExceptionDates: exceptions,
            );

            final uuid = const Uuid();
            final duration = parentTask.to != null
                ? parentTask.to!.difference(parentTask.from!)
                : const Duration(hours: 1);
            final occEnd = occDate.add(duration);

            final clone = TaskItem(
              id: uuid.v4(),
              title: parentTask.title,
              details: parentTask.details,
              isCompleted: false,
              isInProgress: true,
              from: occDate,
              to: occEnd,
              isAllDay: parentTask.isAllDay,
              colorValue: parentTask.colorValue,
              tag: parentTask.tag,
              importance: parentTask.importance,
              projectId: parentTask.projectId,
              recurrenceRule: null,
              recurrenceExceptionDates: null,
              seriesId: parentTask.seriesId,
            );
            _tasks.add(clone);
            notifyListeners();
            _saveTasks();
            _firestoreSaveTask(
              parentTask.copyWith(recurrenceExceptionDates: exceptions),
            );
            _firestoreSaveTask(clone);
            return;
          }
        }
      }
    }

    final index = _tasks.indexWhere((t) => t.id == id);
    if (index != -1) {
      final t = _tasks[index];
      _tasks[index] = t.copyWith(
        isInProgress: !t.isInProgress,
        isCompleted: false,
      );
      notifyListeners();
      _saveTasks();
      _firestoreSaveTask(_tasks[index]);
    }
  }

  void deleteTask(String id, {bool forceDeleteParent = false}) {
    final taskIndex = _tasks.indexWhere((t) => t.id == id);
    if (taskIndex != -1) {
      NotificationService.cancelTaskNotifications(_tasks[taskIndex]);
    }
    if (id.startsWith('rollover_')) {
      id = id.substring(9);
    }
    // Only intercept occ_ IDs when NOT force-deleting the parent
    if (!forceDeleteParent && id.startsWith('occ_')) {
      final lastUnderscore = id.lastIndexOf('_');
      if (lastUnderscore > 4) {
        final parentId = id.substring(4, lastUnderscore);
        final timestampStr = id.substring(lastUnderscore + 1);
        final timestamp = int.tryParse(timestampStr);
        if (timestamp != null) {
          final occDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
          final parentIndex = _tasks.indexWhere((t) => t.id == parentId);
          if (parentIndex != -1) {
            final parentTask = _tasks[parentIndex];
            final exceptions = List<DateTime>.from(
              parentTask.recurrenceExceptionDates ?? [],
            );
            exceptions.add(occDate);
            _tasks[parentIndex] = parentTask.copyWith(
              recurrenceExceptionDates: exceptions,
            );
            notifyListeners();
            _saveTasks();
            _firestoreSaveTask(_tasks[parentIndex]);
            return;
          }
        }
      }
    }

    // Also remove any completed occurrence clones linked to this parent
    final cloneIds = _tasks
        .where((t) => t.parentTaskId == id && t.recurrenceRule == null)
        .map((t) => t.id)
        .toList();
    for (final cloneId in cloneIds) {
      if (!_deletedTaskIds.contains(cloneId)) {
        _deletedTaskIds.add(cloneId);
      }
      _tasks.removeWhere((t) => t.id == cloneId);
      _firestoreDeleteTask(cloneId);
    }

    if (!_deletedTaskIds.contains(id)) {
      _deletedTaskIds.add(id);
      _saveDeletedIds();
    }
    _tasks.removeWhere((t) => t.id == id);
    notifyListeners();
    _saveTasks();
    _firestoreDeleteTask(id);
  }

  void deleteCompletedTasksInSeries(String? seriesId) {
    if (seriesId == null || seriesId.isEmpty) return;
    final toRemove = _tasks
        .where((t) => t.seriesId == seriesId && t.isCompleted)
        .toList();
    for (final t in toRemove) {
      _tasks.remove(t);
      if (!_deletedTaskIds.contains(t.id)) {
        _deletedTaskIds.add(t.id);
      }
      _firestoreDeleteTask(t.id);
    }
    _saveDeletedIds();
    _saveTasks();
    notifyListeners();
  }

  void deleteTaskSeries(String? seriesId) {
    if (seriesId == null || seriesId.isEmpty) return;
    final toRemove = _tasks.where((t) => t.seriesId == seriesId).toList();
    for (final t in toRemove) {
      _tasks.remove(t);
      if (!_deletedTaskIds.contains(t.id)) {
        _deletedTaskIds.add(t.id);
      }
      _firestoreDeleteTask(t.id);
    }
    _saveDeletedIds();
    _saveTasks();
    notifyListeners();
  }

  void deleteEventSeries(String? seriesId) {
    if (seriesId == null || seriesId.isEmpty) return;
    final toRemove = _events.where((e) => e.seriesId == seriesId).toList();
    for (final e in toRemove) {
      _events.remove(e);
      if (!_deletedEventIds.contains(e.id)) {
        _deletedEventIds.add(e.id);
      }
      _firestoreDeleteEvent(e.id);
    }
    _saveDeletedIds();
    _saveEvents();
    notifyListeners();
  }

  void addProject(Project project) {
    _projects.add(project);
    if (!_selectedProjectIds.contains(project.id)) {
      _selectedProjectIds.add(project.id);
      _saveSelectedProjectIds();
    }
    notifyListeners();
    _saveProjects();
    _firestoreSaveProject(project);
  }

  void updateProject(Project project) {
    final index = _projects.indexWhere((p) => p.id == project.id);
    if (index != -1) {
      _projects[index] = project;
      notifyListeners();
      _saveProjects();
      _firestoreSaveProject(project);
    }
  }

  void deleteProject(String id) {
    final projectIndex = _projects.indexWhere((p) => p.id == id);
    if (projectIndex != -1) {
      final project = _projects[projectIndex];
      final deletedMarker = 'deleted:${project.title}';

      // Update all events with this projectId to deletedMarker
      for (int i = 0; i < _events.length; i++) {
        if (_events[i].projectId == id) {
          _events[i] = _events[i].copyWith(projectId: deletedMarker);
          _firestoreSaveEvent(_events[i]);
        }
      }

      // Update all tasks with this projectId to deletedMarker
      for (int i = 0; i < _tasks.length; i++) {
        if (_tasks[i].projectId == id) {
          _tasks[i] = _tasks[i].copyWith(projectId: deletedMarker);
          _firestoreSaveTask(_tasks[i]);
        }
      }

      _projects.removeAt(projectIndex);
      _selectedProjectIds.remove(id);
      _saveSelectedProjectIds();
      _evaluations.removeWhere((e) => e.projectId == id);

      if (!_deletedProjectIds.contains(id)) {
        _deletedProjectIds.add(id);
        _saveDeletedIds();
      }

      notifyListeners();
      _saveEvents();
      _saveTasks();
      _saveProjects();
      _saveEvaluations();
      _firestoreDeleteProject(id);
    }
  }

  void toggleProjectArchive(String id) {
    final index = _projects.indexWhere((p) => p.id == id);
    if (index != -1) {
      _projects[index] = _projects[index].copyWith(
        isArchived: !_projects[index].isArchived,
      );
      notifyListeners();
      _saveProjects();
      _firestoreSaveProject(_projects[index]);
    }
  }

  void toggleProjectSelection(String projectId) {
    if (_selectedProjectIds.contains(projectId)) {
      _selectedProjectIds.remove(projectId);
    } else {
      _selectedProjectIds.add(projectId);
    }
    notifyListeners();
    _saveSelectedProjectIds();
  }

  void selectAllProjects() {
    _selectedProjectIds = ['no_project', ..._projects.map((p) => p.id)];
    notifyListeners();
    _saveSelectedProjectIds();
  }

  void deselectAllProjects() {
    _selectedProjectIds = [];
    notifyListeners();
    _saveSelectedProjectIds();
  }

  Future<void> _saveSelectedProjectIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('selectedProjectIds', _selectedProjectIds);
  }

  void addOrUpdateEvaluation(ProjectEvaluation evaluation) {
    final index = _evaluations.indexWhere(
      (e) =>
          e.projectId == evaluation.projectId &&
          e.sessionDate == evaluation.sessionDate,
    );

    String? oldStepId;
    if (index != -1) {
      oldStepId = _evaluations[index].stepId;
      _evaluations[index] = evaluation;
    } else {
      _evaluations.add(evaluation);
    }

    // Limit to latest 100 evaluations for this project
    final projectEvals = _evaluations
        .where((e) => e.projectId == evaluation.projectId)
        .toList();
    if (projectEvals.length > 100) {
      projectEvals.sort(
        (a, b) => a.sessionDate.compareTo(b.sessionDate),
      ); // oldest first
      final toRemoveCount = projectEvals.length - 100;
      for (int i = 0; i < toRemoveCount; i++) {
        _evaluations.remove(projectEvals[i]);
      }
    }

    // Synchronize daily reports of associated Steps
    final dayKey =
        '${evaluation.sessionDate.year}-${evaluation.sessionDate.month.toString().padLeft(2, '0')}-${evaluation.sessionDate.day.toString().padLeft(2, '0')}';

    // If step changed, remove report from old step
    if (oldStepId != null && oldStepId != evaluation.stepId) {
      final oldStepIdx = _topicPlans.indexWhere((p) => p.id == oldStepId);
      if (oldStepIdx != -1) {
        final Map<String, PlanDayReport> updatedReports = Map.from(
          _topicPlans[oldStepIdx].dayReports,
        );
        updatedReports.remove(dayKey);
        final updatedPlan = _topicPlans[oldStepIdx].copyWith(
          dayReports: updatedReports,
        );
        _topicPlans[oldStepIdx] = updatedPlan;
        _firestoreSaveTopicPlan(updatedPlan);
      }
    }

    // Add or update report in new step
    if (evaluation.stepId != null) {
      final stepIdx = _topicPlans.indexWhere((p) => p.id == evaluation.stepId);
      if (stepIdx != -1) {
        final Map<String, PlanDayReport> updatedReports = Map.from(
          _topicPlans[stepIdx].dayReports,
        );
        updatedReports[dayKey] = PlanDayReport(
          offset: evaluation.isSkipped ? 1 : 0,
          note: evaluation.note ?? '',
          performancePercent: evaluation.performancePercent ?? evaluation.score,
        );
        final updatedPlan = _topicPlans[stepIdx].copyWith(
          dayReports: updatedReports,
        );
        _topicPlans[stepIdx] = updatedPlan;
        _firestoreSaveTopicPlan(updatedPlan);
      }
    }

    notifyListeners();
    _saveEvaluations();
    _saveTopicPlans();
    _firestoreSaveEvaluation(evaluation);
  }

  void addOrUpdateDayNote(DateTime date, String noteText, {int? rating, String? emoji}) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final idx = _dayNotes.indexWhere(
      (n) {
        final localDate = n.date.toLocal();
        return localDate.year == normalizedDate.year &&
               localDate.month == normalizedDate.month &&
               localDate.day == normalizedDate.day;
      },
    );

    if (noteText.trim().isEmpty && rating == null && emoji == null) {
      if (idx != -1) {
        final existingId = _dayNotes[idx].id;
        _dayNotes.removeAt(idx);
        if (!_deletedDayNoteIds.contains(existingId)) {
          _deletedDayNoteIds.add(existingId);
          _saveDeletedIds();
        }
        notifyListeners();
        _saveDayNotes();
        _firestoreDeleteDayNote(existingId);
      }
      return;
    }

    final newNote = DayNote(
      id: idx != -1
          ? _dayNotes[idx].id
          : IdGenerator.generate(
              'gunluknot_${normalizedDate.year}${normalizedDate.month.toString().padLeft(2, "0")}${normalizedDate.day.toString().padLeft(2, "0")}',
            ),
      date: normalizedDate,
      note: noteText,
      rating: rating,
      emoji: emoji,
    );

    _deletedDayNoteIds.remove(newNote.id);
    _saveDeletedIds();

    if (idx != -1) {
      _dayNotes[idx] = newNote;
    } else {
      _dayNotes.add(newNote);
    }
    notifyListeners();
    _saveDayNotes();
    _firestoreSaveDayNote(newNote);
  }

  Future<void> _firestoreSaveDayNote(DayNote note) async {
    if (_user != null && _autoSync) {
      try {
        await _firestoreService.saveDayNote(_user!.uid, note);
      } catch (e) {
        debugPrint('Firestore save dayNote error: $e');
      }
    }
  }

  Future<void> _firestoreDeleteDayNote(String noteId) async {
    if (_user != null && _autoSync) {
      try {
        await _firestoreService.deleteDayNote(_user!.uid, noteId);
      } catch (e) {
        debugPrint('Firestore delete dayNote error: $e');
      }
    }
  }

  void deleteEvaluation(String projectId, DateTime sessionDate) {
    final idx = _evaluations.indexWhere(
      (e) => e.projectId == projectId && e.sessionDate == sessionDate,
    );
    if (idx != -1) {
      final evaluation = _evaluations[idx];
      if (evaluation.stepId != null) {
        final stepIdx = _topicPlans.indexWhere(
          (p) => p.id == evaluation.stepId,
        );
        if (stepIdx != -1) {
          final dayKey =
              '${evaluation.sessionDate.year}-${evaluation.sessionDate.month.toString().padLeft(2, '0')}-${evaluation.sessionDate.day.toString().padLeft(2, '0')}';
          final Map<String, PlanDayReport> updatedReports = Map.from(
            _topicPlans[stepIdx].dayReports,
          );
          updatedReports.remove(dayKey);
          final updatedPlan = _topicPlans[stepIdx].copyWith(
            dayReports: updatedReports,
          );
          _topicPlans[stepIdx] = updatedPlan;
          _firestoreSaveTopicPlan(updatedPlan);
        }
      }
      _evaluations.removeAt(idx);
    }
    notifyListeners();
    _saveEvaluations();
    _saveTopicPlans();
    _firestoreDeleteEvaluation(projectId, sessionDate);
  }

  void importEvaluations(List<ProjectEvaluation> newEvaluations) {
    for (var eval in newEvaluations) {
      final index = _evaluations.indexWhere(
        (e) =>
            e.projectId == eval.projectId &&
            e.sessionDate.year == eval.sessionDate.year &&
            e.sessionDate.month == eval.sessionDate.month &&
            e.sessionDate.day == eval.sessionDate.day,
      );
      if (index != -1) {
        _evaluations[index] = eval;
      } else {
        _evaluations.add(eval);
      }
    }
    notifyListeners();
    _saveEvaluations();
  }

  // --- Firebase & Sync Service Methods ---

  Future<void> toggleAutoSync(bool value) async {
    _autoSync = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoSync', _autoSync);
    notifyListeners();
    if (_user != null) {
      if (_autoSync) {
        await syncDataWithFirebase();
        _startFirestoreListeners(_firestoreUserId ?? _user!.uid);
      } else {
        _cancelFirestoreListeners();
      }
    }
  }

  Future<void> loginWithGoogle() async {
    try {
      final credential = await _authService.signInWithGoogle();
      if (credential != null && credential.user != null) {
        _user = credential.user;
        notifyListeners();
        if (_autoSync) {
          await syncDataWithFirebase();
        }
      } else {
        throw Exception('Giriş başarısız oldu veya iptal edildi.');
      }
    } catch (e) {
      debugPrint('Error logging in with Google: $e');
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await _authService.signOut();
      _user = null;
      _firestoreUserId = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Error logging out: $e');
      rethrow;
    }
  }

  Future<void> clearAllUserData() async {
    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();

    try {
      // 1. Clear local memory
      _events.clear();
      _tasks.clear();
      _projects.clear();
      _evaluations.clear();
      _dayNotes.clear();
      _serits.clear();
      _paintedDays.clear();
      _deletedTaskIds.clear();
      _deletedEventIds.clear();
      _deletedProjectIds.clear();
      _topics.clear();
      _topicPlans.clear();

      // 2. Clear local device cache (SharedPreferences)
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('events');
      await prefs.remove('tasks');
      await prefs.remove('projects');
      await prefs.remove('evaluations');
      await prefs.remove('dayNotes');
      await prefs.remove('serits');
      await prefs.remove('macros');
      await prefs.remove('paintedDays');
      await prefs.remove('deletedTaskIds');
      await prefs.remove('deletedEventIds');
      await prefs.remove('deletedProjectIds');
      await prefs.remove('topics');
      await prefs.remove('topicPlans');
      await prefs.remove('eventTags');
      await prefs.remove('eventSubTags');
      await prefs.remove('taskTags');
      await prefs.remove('taskSubTags');

      // 3. Clear remote Firestore data
      if (_user != null) {
        _firestoreUserId ??= await _firestoreService
            .getOrCreateSiralId(_user!.uid, email: _user!.email)
            .timeout(const Duration(seconds: 5));
        if (_firestoreUserId != null) {
          final userId = _firestoreUserId!;
          final firestore = FirebaseFirestore.instance;
          final collections = [
            'events',
            'tasks',
            'projects',
            'evaluations',
            'serits',
            'macros',
            'day_notes',
            'settings',
            'topics',
            'topicPlans',
          ];

          for (final col in collections) {
            try {
              final snap = await firestore
                  .collection('users')
                  .doc(userId)
                  .collection(col)
                  .get()
                  .timeout(const Duration(seconds: 5));
              if (snap.docs.isNotEmpty) {
                final batch = firestore.batch();
                for (final doc in snap.docs) {
                  batch.delete(doc.reference);
                }
                await batch.commit().timeout(const Duration(seconds: 5));
              }
            } catch (e) {
              debugPrint('Error clearing collection $col in Firestore: $e');
            }
          }
        }
      }
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> deleteUserAccount() async {
    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();

    try {
      final userId = _firestoreUserId;
      final user = _user;

      // 1. Clear Firestore User subcollections
      if (user != null && userId != null) {
        final firestore = FirebaseFirestore.instance;
        final collections = [
          'events',
          'tasks',
          'projects',
          'evaluations',
          'serits',
          'macros',
          'day_notes',
          'settings',
          'topics',
          'topicPlans',
        ];

        for (final col in collections) {
          try {
            final snap = await firestore
                .collection('users')
                .doc(userId)
                .collection(col)
                .get()
                .timeout(const Duration(seconds: 5));
            if (snap.docs.isNotEmpty) {
              final batch = firestore.batch();
              for (final doc in snap.docs) {
                batch.delete(doc.reference);
              }
              await batch.commit().timeout(const Duration(seconds: 5));
            }
          } catch (e) {
            debugPrint(
              'Error deleting collection $col during account delete: $e',
            );
          }
        }

        // 2. Delete the mapping document from 'users' collection
        try {
          await firestore
              .collection('users')
              .doc(userId)
              .delete()
              .timeout(const Duration(seconds: 5));
        } catch (e) {
          debugPrint('Error deleting user mapping doc: $e');
        }
      }

      // 3. Clear local memory
      _events.clear();
      _tasks.clear();
      _projects.clear();
      _evaluations.clear();
      _dayNotes.clear();
      _serits.clear();
      _paintedDays.clear();
      _deletedTaskIds.clear();
      _deletedEventIds.clear();
      _deletedProjectIds.clear();
      _topics.clear();
      _topicPlans.clear();

      // 4. Clear local device cache completely
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // 5. Delete Firebase Auth account
      if (user != null) {
        await _authService.deleteAccount().timeout(const Duration(seconds: 5));
      }

      _user = null;
      _firestoreUserId = null;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> syncDataWithFirebase() async {
    if (_user == null) return;
    _firestoreUserId ??= await _firestoreService.getOrCreateSiralId(
      _user!.uid,
      email: _user!.email,
    );
    if (_firestoreUserId == null) return;

    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();

    try {
      final userId = _firestoreUserId!;
      final firestore = FirebaseFirestore.instance;

      Future<List<Map<String, dynamic>>> getDocs(String path) async {
        final snap = await firestore
            .collection('users')
            .doc(userId)
            .collection(path)
            .get();
        return snap.docs.map((d) => d.data()).toList();
      }

      final remoteEventsJson = await getDocs('events');
      final remoteTasksJson = await getDocs('tasks');
      final remoteProjectsJson = await getDocs('projects');
      final remoteEvalsJson = await getDocs('evaluations');

      final List<Event> remoteEvents = remoteEventsJson
          .map((j) => Event.fromJson(j))
          .toList();
      final List<TaskItem> remoteTasks = remoteTasksJson
          .map((j) => TaskItem.fromJson(j))
          .toList();
      final List<Project> remoteProjects = remoteProjectsJson
          .map((j) => Project.fromJson(j))
          .toList();
      final List<ProjectEvaluation> remoteEvals = remoteEvalsJson
          .map((j) => ProjectEvaluation.fromJson(j))
          .toList();

      // Sync Events
      for (var localEvent in _events) {
        final remote = remoteEvents.firstWhere(
          (re) => re.id == localEvent.id,
          orElse: () => localEvent,
        );
        final localJson = json.encode(localEvent.toJson());
        final remoteJson = json.encode(remote.toJson());
        if (localJson != remoteJson) {
          final mergedExceptions = <DateTime>{};
          if (localEvent.recurrenceExceptionDates != null) {
            mergedExceptions.addAll(localEvent.recurrenceExceptionDates!);
          }
          if (remote.recurrenceExceptionDates != null) {
            mergedExceptions.addAll(remote.recurrenceExceptionDates!);
          }
          final updated = remote.copyWith(
            recurrenceExceptionDates: mergedExceptions.isEmpty
                ? null
                : mergedExceptions.toList(),
          );
          await _firestoreService.saveEvent(userId, updated);
          final idx = _events.indexWhere((e) => e.id == localEvent.id);
          if (idx != -1) {
            _events[idx] = updated;
          }
        }
      }
      for (var remoteEvent in remoteEvents) {
        if (_deletedEventIds.contains(remoteEvent.id)) {
          await _firestoreService.deleteEvent(userId, remoteEvent.id);
          _deletedEventIds.remove(remoteEvent.id);
        } else if (!_events.any((le) => le.id == remoteEvent.id)) {
          _events.add(remoteEvent);
        }
      }
      // Clean up local event tombstones that are no longer in remoteEvents (meaning they are successfully deleted from Firestore)
      _deletedEventIds.removeWhere(
        (id) => !remoteEvents.any((re) => re.id == id),
      );
      await _saveDeletedIds();

      // Sync Tasks
      for (var localTask in _tasks) {
        final remote = remoteTasks.firstWhere(
          (rt) => rt.id == localTask.id,
          orElse: () => localTask,
        );
        final localJson = json.encode(localTask.toJson());
        final remoteJson = json.encode(remote.toJson());
        if (localJson != remoteJson) {
          final mergedExceptions = <DateTime>{};
          if (localTask.recurrenceExceptionDates != null) {
            mergedExceptions.addAll(localTask.recurrenceExceptionDates!);
          }
          if (remote.recurrenceExceptionDates != null) {
            mergedExceptions.addAll(remote.recurrenceExceptionDates!);
          }
          final updated = remote.copyWith(
            recurrenceExceptionDates: mergedExceptions.isEmpty
                ? null
                : mergedExceptions.toList(),
          );
          await _firestoreService.saveTask(userId, updated);
          final idx = _tasks.indexWhere((t) => t.id == localTask.id);
          if (idx != -1) {
            _tasks[idx] = updated;
          }
        }
      }
      for (var remoteTask in remoteTasks) {
        if (_deletedTaskIds.contains(remoteTask.id)) {
          await _firestoreService.deleteTask(userId, remoteTask.id);
          _deletedTaskIds.remove(remoteTask.id);
        } else if (!_tasks.any((lt) => lt.id == remoteTask.id)) {
          _tasks.add(remoteTask);
        }
      }
      // Clean up local task tombstones that are no longer in remoteTasks (meaning they are successfully deleted from Firestore)
      _deletedTaskIds.removeWhere(
        (id) => !remoteTasks.any((rt) => rt.id == id),
      );
      await _saveDeletedIds();

      // Sync Projects
      for (var localProj in _projects) {
        if (!remoteProjects.any((rp) => rp.id == localProj.id)) {
          await _firestoreService.saveProject(userId, localProj);
        }
      }
      for (var remoteProj in remoteProjects) {
        if (_deletedProjectIds.contains(remoteProj.id)) {
          await _firestoreService.deleteProject(userId, remoteProj.id);
          _deletedProjectIds.remove(remoteProj.id);
        } else if (!_projects.any((lp) => lp.id == remoteProj.id)) {
          _projects.add(remoteProj);
        }
      }
      _deletedProjectIds.removeWhere(
        (id) => !remoteProjects.any((rp) => rp.id == id),
      );
      await _saveDeletedIds();

      // Sync Evaluations
      for (var localEval in _evaluations) {
        final docId =
            '${localEval.projectId}_${localEval.sessionDate.millisecondsSinceEpoch}';
        if (!remoteEvals.any(
          (re) =>
              '${re.projectId}_${re.sessionDate.millisecondsSinceEpoch}' ==
              docId,
        )) {
          await _firestoreService.saveEvaluation(userId, localEval);
        }
      }
      for (var remoteEval in remoteEvals) {
        final docId =
            '${remoteEval.projectId}_${remoteEval.sessionDate.millisecondsSinceEpoch}';
        if (!_evaluations.any(
          (le) =>
              '${le.projectId}_${le.sessionDate.millisecondsSinceEpoch}' ==
              docId,
        )) {
          _evaluations.add(remoteEval);
        }
      }

      // Sync Serits
      final remoteSeritsJson = await getDocs('serits');
      final List<Serit> remoteSerits = remoteSeritsJson
          .map((j) => Serit.fromJson(j))
          .toList();
      for (var localSerit in _serits) {
        if (!remoteSerits.any((rm) => rm.id == localSerit.id)) {
          await _firestoreService.saveSerit(userId, localSerit);
        }
      }
      for (var remoteSerit in remoteSerits) {
        if (!_serits.any((lm) => lm.id == remoteSerit.id)) {
          _serits.add(remoteSerit);
        }
      }

      // Sync Day Notes
      final remoteNotesJson = await getDocs('day_notes');
      final List<DayNote> remoteNotes = remoteNotesJson
          .map((j) => DayNote.fromJson(j))
          .toList();
      for (var localNote in _dayNotes) {
        if (!remoteNotes.any((rn) => rn.id == localNote.id)) {
          await _firestoreService.saveDayNote(userId, localNote);
        }
      }
      for (var remoteNote in remoteNotes) {
        if (_deletedDayNoteIds.contains(remoteNote.id)) {
          await _firestoreService.deleteDayNote(userId, remoteNote.id);
          _deletedDayNoteIds.remove(remoteNote.id);
        } else if (!_dayNotes.any((ln) => ln.id == remoteNote.id)) {
          _dayNotes.add(remoteNote);
        }
      }
      _deletedDayNoteIds.removeWhere(
        (id) => !remoteNotes.any((rn) => rn.id == id),
      );
      await _saveDeletedIds();

      // Sync Categories — Yeni format (eventCategories / taskCategories)
      void mergeRemoteTags(
        Map<String, dynamic> remoteCats,
        String tagsKey,
        String subTagsKey,
        List<String> localTags,
        Map<String, List<String>> localSubTags,
        List<String> selectedTags,
        List<String> selectedSubTags,
      ) {
        final List<dynamic>? remoteTags = remoteCats[tagsKey] as List<dynamic>?;
        final Map<String, dynamic>? remoteSubs =
            remoteCats[subTagsKey] as Map<String, dynamic>?;
        if (remoteTags != null) {
          for (var tag in remoteTags) {
            final tagStr = tag.toString();
            if (!localTags.contains(tagStr)) {
              localTags.add(tagStr);
            }
          }
          selectedTags
            ..clear()
            ..addAll(localTags);
        }
        if (remoteSubs != null) {
          remoteSubs.forEach((key, value) {
            final List<String> remoteSub = List<String>.from(value as List);
            if (localSubTags.containsKey(key)) {
              for (var sub in remoteSub) {
                if (!localSubTags[key]!.contains(sub)) {
                  localSubTags[key]!.add(sub);
                }
              }
            } else {
              localSubTags[key] = remoteSub;
            }
          });
        }
        // Ensure all subtags are selected
        localSubTags.forEach((tag, list) {
          for (var sub in list) {
            final key = '$tag:$sub';
            if (!selectedSubTags.contains(key)) {
              selectedSubTags.add(key);
            }
          }
        });
      }

      final remoteEventCats = await _firestoreService.getEventCategories(
        userId,
      );
      if (remoteEventCats != null) {
        mergeRemoteTags(
          remoteEventCats,
          'eventTags',
          'eventSubTags',
          _eventTags,
          _eventSubTags,
          _selectedEventTags,
          _selectedEventSubTags,
        );
      }
      final remoteTaskCats = await _firestoreService.getTaskCategories(userId);
      if (remoteTaskCats != null) {
        mergeRemoteTags(
          remoteTaskCats,
          'taskTags',
          'taskSubTags',
          _taskTags,
          _taskSubTags,
          _selectedTaskTags,
          _selectedTaskSubTags,
        );
      }

      // [LEGACY] Eski birleşik format varsa da merge et
      final remoteLegacyCats = await _firestoreService.getLegacyCategories(
        userId,
      );
      if (remoteLegacyCats != null) {
        mergeRemoteTags(
          remoteLegacyCats,
          'availableTags',
          'categorySubTags',
          _eventTags,
          _eventSubTags,
          _selectedEventTags,
          _selectedEventSubTags,
        );
        mergeRemoteTags(
          remoteLegacyCats,
          'availableTags',
          'categorySubTags',
          _taskTags,
          _taskSubTags,
          _selectedTaskTags,
          _selectedTaskSubTags,
        );
      }

      cleanUnusedDefaultCategories();
      await _firestoreService.saveEventCategories(
        userId,
        _eventTags,
        _eventSubTags,
      );
      await _firestoreService.saveTaskCategories(
        userId,
        _taskTags,
        _taskSubTags,
      );

      // Sync Painted Days
      final remotePaintedData = await _firestoreService.getPaintedDays(userId);
      if (remotePaintedData != null &&
          remotePaintedData['paintedDays'] != null) {
        final Map<String, dynamic> remotePainted =
            remotePaintedData['paintedDays'] as Map<String, dynamic>;
        remotePainted.forEach((key, value) {
          _paintedDays[key] = value.toString();
        });
      } else {
        await _firestoreService.savePaintedDays(userId, _paintedDays);
      }

      // Sync Quick Note
      try {
        final remoteQuickNoteData = await _firestoreService.getQuickNote(
          userId,
        );
        if (remoteQuickNoteData != null &&
            remoteQuickNoteData['note'] != null) {
          final String remoteNote = remoteQuickNoteData['note'].toString();
          if (remoteNote.isNotEmpty && _quickNote.isEmpty) {
            _quickNote = remoteNote;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('quickNote', _quickNote);
          } else if (_quickNote.isNotEmpty) {
            await _firestoreService.saveQuickNote(userId, _quickNote);
          }
        } else if (_quickNote.isNotEmpty) {
          await _firestoreService.saveQuickNote(userId, _quickNote);
        }
      } catch (e) {
        debugPrint('Sync quickNote error: $e');
      }

      // Sync Notes
      try {
        final remoteNotesData = await _firestoreService.getNotes(userId);
        if (remoteNotesData != null && remoteNotesData['notes'] != null) {
          final List<dynamic> remoteList = remoteNotesData['notes'] as List<dynamic>;
          if (remoteList.isNotEmpty && _notes.isEmpty) {
            _notes = remoteList.map((n) => Note.fromJson(Map<String, dynamic>.from(n as Map))).toList();
            final prefs = await SharedPreferences.getInstance();
            final List<String> notesJson = _notes.map((n) => json.encode(n.toJson())).toList();
            await prefs.setStringList('keepNotes', notesJson);
          } else if (_notes.isNotEmpty) {
            await _firestoreService.saveNotes(userId, _notes.map((n) => n.toJson()).toList());
          }
        } else if (_notes.isNotEmpty) {
          await _firestoreService.saveNotes(userId, _notes.map((n) => n.toJson()).toList());
        }
      } catch (e) {
        debugPrint('Sync notes error: $e');
      }

      // Sync Category Colors
      try {
        final remoteColorsData = await _firestoreService.getCategoryColors(
          userId,
        );
        if (remoteColorsData != null) {
          final Map<String, dynamic>? remoteEventColors =
              remoteColorsData['eventTagColors'] as Map<String, dynamic>?;
          final Map<String, dynamic>? remoteTaskColors =
              remoteColorsData['taskTagColors'] as Map<String, dynamic>?;

          final prefs = await SharedPreferences.getInstance();
          bool updated = false;

          if (remoteEventColors != null) {
            remoteEventColors.forEach((key, value) {
              if (value is int && !_eventTagColors.containsKey(key)) {
                _eventTagColors[key] = value;
                updated = true;
              }
            });
          }
          if (remoteTaskColors != null) {
            remoteTaskColors.forEach((key, value) {
              if (value is int && !_taskTagColors.containsKey(key)) {
                _taskTagColors[key] = value;
                updated = true;
              }
            });
          }

          if (updated) {
            await prefs.setString(
              'eventTagColors',
              json.encode(_eventTagColors),
            );
            await prefs.setString('taskTagColors', json.encode(_taskTagColors));
            notifyListeners();
          } else {
            await _firestoreService.saveCategoryColors(
              userId,
              _eventTagColors,
              _taskTagColors,
            );
          }
        } else {
          await _firestoreService.saveCategoryColors(
            userId,
            _eventTagColors,
            _taskTagColors,
          );
        }
      } catch (e) {
        debugPrint('Sync category colors error: $e');
      }

      // Sync Task Order
      try {
        final remoteOrderData = await _firestoreService.getTaskOrder(userId);
        if (remoteOrderData != null && remoteOrderData['order'] != null) {
          final List<dynamic> remoteList =
              remoteOrderData['order'] as List<dynamic>;
          final List<String> remoteOrder = remoteList
              .map((e) => e.toString())
              .toList();
          if (remoteOrder.isNotEmpty && _customTaskOrder.isEmpty) {
            _customTaskOrder = remoteOrder;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setStringList('customTaskOrder', _customTaskOrder);
            notifyListeners();
          } else if (_customTaskOrder.isNotEmpty) {
            await _firestoreService.saveTaskOrder(userId, _customTaskOrder);
          }
        } else if (_customTaskOrder.isNotEmpty) {
          await _firestoreService.saveTaskOrder(userId, _customTaskOrder);
        }
      } catch (e) {
        debugPrint('Sync taskOrder error: $e');
      }

      // Sync Topics
      final remoteTopicsJson = await getDocs('topics');
      final List<Topic> remoteTopics = remoteTopicsJson
          .map((j) => Topic.fromJson(j))
          .toList();
      for (var localTopic in _topics) {
        if (!remoteTopics.any((rt) => rt.id == localTopic.id)) {
          await _firestoreService.saveTopic(userId, localTopic);
        }
      }
      for (var remoteTopic in remoteTopics) {
        if (!_topics.any((lt) => lt.id == remoteTopic.id)) {
          _topics.add(remoteTopic);
        }
      }

      // Sync Topic Plans
      var remotePlansJson = await getDocs('steps');
      if (remotePlansJson.isEmpty) {
        final legacyPlansJson = await getDocs('topic_plans');
        if (legacyPlansJson.isNotEmpty) {
          debugPrint(
            'Migrating ${legacyPlansJson.length} plans from legacy topic_plans to steps...',
          );
          for (var planJson in legacyPlansJson) {
            final plan = TopicPlan.fromJson(planJson);
            await _firestoreService.saveTopicPlan(userId, plan);
          }
          remotePlansJson = await getDocs('steps');
        }
      }

      final List<TopicPlan> remoteTopicPlans = remotePlansJson
          .map((j) => TopicPlan.fromJson(j))
          .toList();
      for (var localPlan in _topicPlans) {
        final remote = remoteTopicPlans.firstWhere(
          (rp) => rp.id == localPlan.id,
          orElse: () => localPlan,
        );
        final localJson = json.encode(localPlan.toJson());
        final remoteJson = json.encode(remote.toJson());
        if (localJson != remoteJson) {
          await _firestoreService.saveTopicPlan(userId, localPlan);
        }
      }
      for (var remotePlan in remoteTopicPlans) {
        if (!_topicPlans.any((lp) => lp.id == remotePlan.id)) {
          _topicPlans.add(remotePlan);
        }
      }

      _cleanDuplicateTasks();
      _syncTaskTagsAndSubTags();
      _cleanDuplicateEvents();

      await _saveEvents();
      await _saveTasks();
      await _saveProjects();
      await _saveEvaluations();
      await _saveDayNotes();
      await _saveSerits();
      await _saveCategories();
      await _savePaintedDays();
      await _saveTopics();
      await _saveTopicPlans();
    } catch (e) {
      debugPrint('Sync error: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> restoreBackup({
    required List<Project> projects,
    required List<ProjectEvaluation> evaluations,
    required List<Event> events,
    required List<TaskItem> tasks,
  }) async {
    _projects = projects;
    _evaluations = evaluations;
    _events = events;
    _tasks = tasks;

    // Reset selection to include all projects
    _selectedProjectIds = ['no_project', ..._projects.map((p) => p.id)];

    notifyListeners();

    // Save locally
    await _saveEvents();
    await _saveTasks();
    await _saveProjects();
    await _saveEvaluations();
    await _saveSelectedProjectIds();

    // Sync to Firestore if logged in
    if (_user != null && _autoSync) {
      await syncDataWithFirebase();
    }
  }

  // Firestore Async Helpers
  Future<void> _firestoreSaveEvent(Event event) async {
    if (_user != null && _autoSync) {
      try {
        _firestoreUserId ??= await _firestoreService.getOrCreateSiralId(
          _user!.uid,
        );
        await _firestoreService.saveEvent(_firestoreUserId!, event);
      } catch (e) {
        debugPrint('Firestore save event error: $e');
      }
    }
  }

  Future<void> _firestoreDeleteEvent(String id) async {
    if (_user != null && _autoSync) {
      try {
        _firestoreUserId ??= await _firestoreService.getOrCreateSiralId(
          _user!.uid,
        );
        await _firestoreService.deleteEvent(_firestoreUserId!, id);
      } catch (e) {
        debugPrint('Firestore delete event error: $e');
      }
    }
  }

  Future<void> _firestoreSaveTask(TaskItem task) async {
    if (_user != null && _autoSync) {
      try {
        _firestoreUserId ??= await _firestoreService.getOrCreateSiralId(
          _user!.uid,
        );
        await _firestoreService.saveTask(_firestoreUserId!, task);
      } catch (e) {
        debugPrint('Firestore save task error: $e');
      }
    }
  }

  Future<void> _firestoreDeleteTask(String id) async {
    if (_user != null && _autoSync) {
      try {
        _firestoreUserId ??= await _firestoreService.getOrCreateSiralId(
          _user!.uid,
        );
        await _firestoreService.deleteTask(_firestoreUserId!, id);
      } catch (e) {
        debugPrint('Firestore delete task error: $e');
      }
    }
  }

  Future<void> _firestoreSaveProject(Project project) async {
    if (_user != null && _autoSync) {
      try {
        _firestoreUserId ??= await _firestoreService.getOrCreateSiralId(
          _user!.uid,
        );
        await _firestoreService.saveProject(_firestoreUserId!, project);
      } catch (e) {
        debugPrint('Firestore save project error: $e');
      }
    }
  }

  Future<void> _firestoreDeleteProject(String id) async {
    if (_user != null && _autoSync) {
      try {
        _firestoreUserId ??= await _firestoreService.getOrCreateSiralId(
          _user!.uid,
        );
        await _firestoreService.deleteProject(_firestoreUserId!, id);
      } catch (e) {
        debugPrint('Firestore delete project error: $e');
      }
    }
  }

  Future<void> _firestoreSaveTopic(Topic topic) async {
    if (_user != null && _autoSync) {
      try {
        _firestoreUserId ??= await _firestoreService.getOrCreateSiralId(
          _user!.uid,
        );
        await _firestoreService.saveTopic(_firestoreUserId!, topic);
      } catch (e) {
        debugPrint('Firestore save topic error: $e');
      }
    }
  }

  Future<void> _firestoreDeleteTopic(String id) async {
    if (_user != null && _autoSync) {
      try {
        _firestoreUserId ??= await _firestoreService.getOrCreateSiralId(
          _user!.uid,
        );
        await _firestoreService.deleteTopic(_firestoreUserId!, id);
      } catch (e) {
        debugPrint('Firestore delete topic error: $e');
      }
    }
  }

  Future<void> _firestoreSaveTopicPlan(TopicPlan plan) async {
    if (_user != null && _autoSync) {
      try {
        _firestoreUserId ??= await _firestoreService.getOrCreateSiralId(
          _user!.uid,
        );
        await _firestoreService.saveTopicPlan(_firestoreUserId!, plan);
      } catch (e) {
        debugPrint('Firestore save topic plan error: $e');
      }
    }
  }

  Future<void> _firestoreDeleteTopicPlan(String id) async {
    if (_user != null && _autoSync) {
      try {
        _firestoreUserId ??= await _firestoreService.getOrCreateSiralId(
          _user!.uid,
        );
        await _firestoreService.deleteTopicPlan(_firestoreUserId!, id);
      } catch (e) {
        debugPrint('Firestore delete topic plan error: $e');
      }
    }
  }

  Future<void> _firestoreSaveEvaluation(ProjectEvaluation evaluation) async {
    if (_user != null && _autoSync) {
      try {
        _firestoreUserId ??= await _firestoreService.getOrCreateSiralId(
          _user!.uid,
        );
        await _firestoreService.saveEvaluation(_firestoreUserId!, evaluation);
      } catch (e) {
        debugPrint('Firestore save evaluation error: $e');
      }
    }
  }

  Future<void> _firestoreDeleteEvaluation(
    String projectId,
    DateTime sessionDate,
  ) async {
    if (_user != null && _autoSync) {
      try {
        _firestoreUserId ??= await _firestoreService.getOrCreateSiralId(
          _user!.uid,
        );
        await _firestoreService.deleteEvaluation(
          _firestoreUserId!,
          projectId,
          sessionDate,
        );
      } catch (e) {
        debugPrint('Firestore delete evaluation error: $e');
      }
    }
  }

  // --- Filtering & Search ---

  void setSearchQuery(String query) {
    _searchQuery = query;
    _updateSearchResults();
    notifyListeners();
  }

  void _updateSearchResults() {
    if (_searchQuery.isEmpty) {
      _searchResults = [];
      _searchResultIndex = 0;
      return;
    }

    _searchResults = [
      ...filteredEvents,
      ...filteredTasks.where((t) => t.from != null),
    ];
    _searchResults.sort((a, b) {
      DateTime dateA = a is Event ? a.from : (a as TaskItem).from!;
      DateTime dateB = b is Event ? b.from : (b as TaskItem).from!;
      return dateA.compareTo(dateB);
    });

    _searchResultIndex = 0;
    if (_searchResults.isNotEmpty) {
      _jumpToCurrentSearchResult();
    }
  }

  void nextSearchResult() {
    if (_searchResults.isEmpty) return;
    _searchResultIndex = (_searchResultIndex + 1) % _searchResults.length;
    _jumpToCurrentSearchResult();
    notifyListeners();
  }

  void prevSearchResult() {
    if (_searchResults.isEmpty) return;
    _searchResultIndex =
        (_searchResultIndex - 1 + _searchResults.length) %
        _searchResults.length;
    _jumpToCurrentSearchResult();
    notifyListeners();
  }

  void _jumpToCurrentSearchResult() {
    final item = _searchResults[_searchResultIndex];
    DateTime targetDate = item is Event ? item.from : (item as TaskItem).from!;
    calendarController.displayDate = targetDate;
  }

  void toggleTag(String tag) {
    // [LEGACY COMPAT] Etkinlik tag'larını toggle eder
    toggleEventTag(tag);
  }

  void toggleSubTag(String tag, String subTag) {
    // [LEGACY COMPAT] Etkinlik subtag'larını toggle eder
    toggleEventSubTag(tag, subTag);
  }

  void toggleEventTag(String tag) {
    if (_selectedEventTags.contains(tag)) {
      _selectedEventTags.remove(tag);
    } else {
      _selectedEventTags.add(tag);
    }
    notifyListeners();
  }

  void toggleEventSubTag(String tag, String subTag) {
    final key = '$tag:$subTag';
    if (_selectedEventSubTags.contains(key)) {
      _selectedEventSubTags.remove(key);
    } else {
      _selectedEventSubTags.add(key);
    }
    notifyListeners();
  }

  void toggleTaskTag(String tag) {
    if (_selectedTaskTags.contains(tag)) {
      _selectedTaskTags.remove(tag);
    } else {
      _selectedTaskTags.add(tag);
    }
    notifyListeners();
  }

  void toggleTaskSubTag(String tag, String subTag) {
    final key = '$tag:$subTag';
    if (_selectedTaskSubTags.contains(key)) {
      _selectedTaskSubTags.remove(key);
    } else {
      _selectedTaskSubTags.add(key);
    }
    notifyListeners();
  }

  void toggleImportance(int importance) {
    if (_selectedImportances.contains(importance)) {
      _selectedImportances.remove(importance);
    } else {
      _selectedImportances.add(importance);
    }
    notifyListeners();
  }

  void clearTagFilters() {
    _selectedEventTags.clear();
    _selectedTaskTags.clear();
    notifyListeners();
  }

  void selectAllEventTags() {
    _selectedEventTags.clear();
    _selectedEventTags.addAll(_eventTags);
    _selectedEventSubTags.clear();
    _eventSubTags.forEach((tag, subTags) {
      for (var sub in subTags) {
        _selectedEventSubTags.add('$tag:$sub');
      }
    });
    notifyListeners();
  }

  void deselectAllEventTags() {
    _selectedEventTags.clear();
    _selectedEventSubTags.clear();
    notifyListeners();
  }

  void selectAllTaskTags() {
    _selectedTaskTags.clear();
    _selectedTaskTags.addAll(_taskTags);
    _selectedTaskSubTags.clear();
    _taskSubTags.forEach((tag, subTags) {
      for (var sub in subTags) {
        _selectedTaskSubTags.add('$tag:$sub');
      }
    });
    notifyListeners();
  }

  void deselectAllTaskTags() {
    _selectedTaskTags.clear();
    _selectedTaskSubTags.clear();
    notifyListeners();
  }

  Future<void> _saveCategories() async {
    final prefs = await SharedPreferences.getInstance();
    // Etkinlik kategorileri
    await prefs.setStringList('eventTags', _eventTags);
    await prefs.setString('eventSubTags', json.encode(_eventSubTags));
    // Görev kategorileri
    await prefs.setStringList('taskTags', _taskTags);
    await prefs.setString('taskSubTags', json.encode(_taskSubTags));

    if (_user != null && _autoSync) {
      try {
        _firestoreUserId ??= await _firestoreService.getOrCreateSiralId(
          _user!.uid,
        );
        await _firestoreService.saveEventCategories(
          _firestoreUserId!,
          _eventTags,
          _eventSubTags,
        );
        await _firestoreService.saveTaskCategories(
          _firestoreUserId!,
          _taskTags,
          _taskSubTags,
        );
      } catch (e) {
        debugPrint('Firestore save categories error: $e');
      }
    }
  }

  // ---- Etkinlik kategori yönetimi ----
  void addEventCategory(String category) {
    if (!_eventTags.contains(category)) {
      _eventTags.add(category);
      _selectedEventTags.add(category);
      _eventSubTags[category] = [];
      notifyListeners();
      _saveCategories();
    }
  }

  void deleteEventCategory(String category) {
    _eventTags.remove(category);
    _selectedEventTags.remove(category);
    _eventSubTags.remove(category);
    notifyListeners();
    _saveCategories();
  }

  void reorderEventCategories(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final String item = _eventTags.removeAt(oldIndex);
    _eventTags.insert(newIndex, item);
    notifyListeners();
    _saveCategories();
  }

  void addEventSubTag(String tag, String subTag) {
    if (_eventSubTags.containsKey(tag)) {
      if (!_eventSubTags[tag]!.contains(subTag)) {
        _eventSubTags[tag]!.add(subTag);
        _selectedEventSubTags.add('$tag:$subTag');
        notifyListeners();
        _saveCategories();
      }
    }
  }

  void deleteEventSubTag(String category, String subTag) {
    final subTags = _eventSubTags[category];
    if (subTags != null) {
      subTags.remove(subTag);
      _selectedEventSubTags.remove('$category:$subTag');
      _selectedEventSubTags.remove(subTag);
      notifyListeners();
      _saveCategories();
    }
  }

  // ---- Görev kategori yönetimi ----
  void addTaskCategory(String category) {
    if (!_taskTags.contains(category)) {
      _taskTags.add(category);
      _selectedTaskTags.add(category);
      _taskSubTags[category] = [];
      notifyListeners();
      _saveCategories();
    }
  }

  void deleteTaskCategory(String category) {
    _taskTags.remove(category);
    _selectedTaskTags.remove(category);
    _taskSubTags.remove(category);
    notifyListeners();
    _saveCategories();
  }

  void reorderTaskCategories(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final String item = _taskTags.removeAt(oldIndex);
    _taskTags.insert(newIndex, item);
    notifyListeners();
    _saveCategories();
  }

  void addTaskSubTag(String tag, String subTag) {
    if (_taskSubTags.containsKey(tag)) {
      if (!_taskSubTags[tag]!.contains(subTag)) {
        _taskSubTags[tag]!.add(subTag);
        _selectedTaskSubTags.add('$tag:$subTag');
        notifyListeners();
        _saveCategories();
      }
    }
  }

  void deleteTaskSubTag(String category, String subTag) {
    final subTags = _taskSubTags[category];
    if (subTags != null) {
      subTags.remove(subTag);
      _selectedTaskSubTags.remove('$category:$subTag');
      _selectedTaskSubTags.remove(subTag);
      notifyListeners();
      _saveCategories();
    }
  }

  // ---- Görev kategori isim düzenleme ----
  void renameTaskCategory(String oldName, String newName) {
    if (oldName == newName || newName.trim().isEmpty) return;
    if (_taskTags.contains(newName)) return; // Zaten var

    final idx = _taskTags.indexOf(oldName);
    if (idx == -1) return;

    _taskTags[idx] = newName;

    // Seçili taglar güncelle
    final selIdx = _selectedTaskTags.indexOf(oldName);
    if (selIdx != -1) _selectedTaskTags[selIdx] = newName;

    // Alt tag haritasını taşı
    if (_taskSubTags.containsKey(oldName)) {
      _taskSubTags[newName] = _taskSubTags.remove(oldName) ?? [];
    }

    // Seçili alt tagları güncelle
    final keysToUpdate = _selectedTaskSubTags
        .where((k) => k.startsWith('$oldName:'))
        .toList();
    for (var k in keysToUpdate) {
      _selectedTaskSubTags.remove(k);
      _selectedTaskSubTags.add('$newName:${k.substring(oldName.length + 1)}');
    }

    // Tüm görevlerin tag'ını güncelle
    for (int i = 0; i < _tasks.length; i++) {
      if (_tasks[i].tag == oldName) {
        _tasks[i] = _tasks[i].copyWith(tag: newName);
        _firestoreSaveTask(_tasks[i]);
      }
    }

    notifyListeners();
    _saveCategories();
    _saveTasks();
  }

  // ---- Görev alt kategori isim düzenleme ----
  void renameTaskSubTag(String category, String oldSubTag, String newSubTag) {
    if (oldSubTag == newSubTag || newSubTag.trim().isEmpty) return;
    final subTags = _taskSubTags[category];
    if (subTags == null) return;
    if (subTags.contains(newSubTag)) return;

    final idx = subTags.indexOf(oldSubTag);
    if (idx == -1) return;
    subTags[idx] = newSubTag;

    if (_selectedTaskSubTags.remove('$category:$oldSubTag')) {
      _selectedTaskSubTags.add('$category:$newSubTag');
    }
    _selectedTaskSubTags.remove(oldSubTag);

    for (int i = 0; i < _tasks.length; i++) {
      if (_tasks[i].tag == category && _tasks[i].subTag == oldSubTag) {
        _tasks[i] = _tasks[i].copyWith(subTag: newSubTag);
        _firestoreSaveTask(_tasks[i]);
      }
    }

    notifyListeners();
    _saveCategories();
    _saveTasks();
  }

  // ---- Etkinlik alt kategori isim düzenleme ----
  void renameEventSubTag(String category, String oldSubTag, String newSubTag) {
    if (oldSubTag == newSubTag || newSubTag.trim().isEmpty) return;
    final subTags = _eventSubTags[category];
    if (subTags == null) return;
    if (subTags.contains(newSubTag)) return;

    final idx = subTags.indexOf(oldSubTag);
    if (idx == -1) return;
    subTags[idx] = newSubTag;

    if (_selectedEventSubTags.remove('$category:$oldSubTag')) {
      _selectedEventSubTags.add('$category:$newSubTag');
    }
    _selectedEventSubTags.remove(oldSubTag);

    for (int i = 0; i < _events.length; i++) {
      if (_events[i].tag == category && _events[i].subTag == oldSubTag) {
        _events[i] = _events[i].copyWith(subTag: newSubTag);
        _firestoreSaveEvent(_events[i]);
      }
    }

    notifyListeners();
    _saveCategories();
    _saveEvents();
  }



  // ---- Etkinlik kategori isim düzenleme ----
  void renameEventCategory(String oldName, String newName) {
    if (oldName == newName || newName.trim().isEmpty) return;
    if (_eventTags.contains(newName)) return;

    final idx = _eventTags.indexOf(oldName);
    if (idx == -1) return;

    _eventTags[idx] = newName;

    final selIdx = _selectedEventTags.indexOf(oldName);
    if (selIdx != -1) _selectedEventTags[selIdx] = newName;

    if (_eventSubTags.containsKey(oldName)) {
      _eventSubTags[newName] = _eventSubTags.remove(oldName) ?? [];
    }

    final keysToUpdate = _selectedEventSubTags
        .where((k) => k.startsWith('$oldName:'))
        .toList();
    for (var k in keysToUpdate) {
      _selectedEventSubTags.remove(k);
      _selectedEventSubTags.add('$newName:${k.substring(oldName.length + 1)}');
    }

    for (int i = 0; i < _events.length; i++) {
      if (_events[i].tag == oldName) {
        _events[i] = _events[i].copyWith(tag: newName);
        _firestoreSaveEvent(_events[i]);
      }
    }

    notifyListeners();
    _saveCategories();
    _saveEvents();
  }

  // ---- [LEGACY COMPAT] Eski metodlar — etkinlik kategorisine yönlendirildi ----
  void addCategory(String category) => addEventCategory(category);
  void deleteCategory(String category) => deleteEventCategory(category);
  void addSubTag(String tag, String subTag) => addEventSubTag(tag, subTag);
  void deleteSubTagFromCategory(String category, String subTag) =>
      deleteEventSubTag(category, subTag);
  void addNewTag(String tag) => addEventCategory(tag);

  void setCalendarView(CalendarView view) {
    _showSeritView = false;
    _showPlanView = false;
    _showRecentView = false;
    _calendarView = view;
    notifyListeners();
  }

  void setShowSeritView(bool value) {
    _showSeritView = value;
    if (value) {
      _showPlanView = false;
      _showRecentView = false;
    }
    notifyListeners();
  }

  void setShowPlanView(bool value) {
    _showPlanView = value;
    if (value) {
      _showSeritView = false;
      _showRecentView = false;
    }
    notifyListeners();
  }

  void setShowRecentView(bool value) {
    _showRecentView = value;
    if (value) {
      _showPlanView = false;
      _showSeritView = false;
    }
    notifyListeners();
  }

  void startSeritDraft({Serit? existing, DateTime? initialDate}) {
    _isSeritDraftActive = true;
    _draftExistingSerit = existing;
    _draftStartDate = initialDate ?? DateTime.now();
    _showSeritView = true; // Automatically switch to Serit view!
    notifyListeners();
  }

  void stopSeritDraft() {
    _isSeritDraftActive = false;
    _draftExistingSerit = null;
    notifyListeners();
  }

  void jumpToToday() {
    final now = DateTime.now();
    calendarController.displayDate = now;
    _displayDate = now;
    notifyListeners();
  }

  void jumpToDate(DateTime date) {
    calendarController.displayDate = date;
    _displayDate = date;
    notifyListeners();
  }

  void setCurrentTabIndex(int index) {
    _currentTabIndex = index;
    notifyListeners();
  }

  void toggleHideEmptyHours() {
    _hideEmptyHours = !_hideEmptyHours;
    notifyListeners();
  }

  void toggleFitToScreen() {
    _fitToScreen = !_fitToScreen;
    notifyListeners();
  }

  void updateFirstDayOfWeek(int day) async {
    _firstDayOfWeek = day;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('firstDayOfWeek', day);
  }

  void updateFontSizeMultiplier(double value) async {
    _fontSizeMultiplier = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fontSizeMultiplier', value);
  }

  void paintDay(DateTime date, String? color) {
    final key =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    if (color == null) {
      _paintedDays.remove(key);
    } else {
      _paintedDays[key] = color;
    }
    notifyListeners();
    _savePaintedDays();
  }

  void clearAllPaintedDays() {
    _paintedDays.clear();
    notifyListeners();
    _savePaintedDays();
  }

  Future<void> _savePaintedDays() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('paintedDays', json.encode(_paintedDays));
    if (_user != null && _autoSync) {
      try {
        _firestoreUserId ??= await _firestoreService.getOrCreateSiralId(
          _user!.uid,
        );
        await _firestoreService.savePaintedDays(
          _firestoreUserId!,
          _paintedDays,
        );
      } catch (e) {
        debugPrint('Firestore save paintedDays error: $e');
      }
    }
  }

  Future<void> _saveSerits() async {
    final prefs = await SharedPreferences.getInstance();
    final seritsJson = _serits.map((m) => json.encode(m.toJson())).toList();
    await prefs.setStringList('serits', seritsJson);
  }

  void addSerit(Serit serit) async {
    _serits.add(serit);
    notifyListeners();
    await _saveSerits();
    if (_user != null && _autoSync) {
      try {
        _firestoreUserId ??= await _firestoreService.getOrCreateSiralId(
          _user!.uid,
        );
        await _firestoreService.saveSerit(_firestoreUserId!, serit);
      } catch (e) {
        debugPrint('Firestore save serit error: $e');
      }
    }
  }

  void updateSerit(Serit serit, {bool updateChained = false}) async {
    final index = _serits.indexWhere((m) => m.id == serit.id);
    if (index != -1) {
      final oldSerit = _serits[index];
      _serits[index] = serit;

      // Connected postpone shifting logic
      if (updateChained && oldSerit.endDate != serit.endDate) {
        final shiftAmount = serit.endDate.difference(oldSerit.endDate);
        _shiftChainedSerits(serit.id, shiftAmount);
      }

      notifyListeners();
      await _saveSerits();
      if (_user != null && _autoSync) {
        try {
          _firestoreUserId ??= await _firestoreService.getOrCreateSiralId(
            _user!.uid,
          );
          await _firestoreService.saveSerit(_firestoreUserId!, serit);
          if (updateChained && oldSerit.endDate != serit.endDate) {
            for (var m in _serits) {
              await _firestoreService.saveSerit(_firestoreUserId!, m);
            }
          }
        } catch (e) {
          debugPrint('Firestore update serit error: $e');
        }
      }
    }
  }

  void _shiftChainedSerits(String parentId, Duration shiftAmount) {
    for (int i = 0; i < _serits.length; i++) {
      if (_serits[i].parentSeritId == parentId) {
        final newStart = _serits[i].startDate.add(shiftAmount);
        final newEnd = _serits[i].endDate.add(shiftAmount);

        final updated = _serits[i].copyWith(
          startDate: newStart,
          endDate: newEnd,
        );
        _serits[i] = updated;

        // Recursively shift children
        _shiftChainedSerits(updated.id, shiftAmount);
      }
    }
  }

  int countChainedSerits(String parentId) {
    int count = 0;
    for (var m in _serits) {
      if (m.parentSeritId == parentId) {
        count += 1 + countChainedSerits(m.id);
      }
    }
    return count;
  }

  void deleteSerit(String id) async {
    // Clear parent links for chained serits
    for (int i = 0; i < _serits.length; i++) {
      if (_serits[i].parentSeritId == id) {
        _serits[i] = _serits[i].copyWith(parentSeritId: 'clear_parent');
        if (_user != null && _autoSync) {
          try {
            _firestoreUserId ??= await _firestoreService.getOrCreateSiralId(
              _user!.uid,
            );
            await _firestoreService.saveSerit(_firestoreUserId!, _serits[i]);
          } catch (e) {
            debugPrint('Firestore save serit parent link clear error: $e');
          }
        }
      }
    }
    _serits.removeWhere((m) => m.id == id);
    notifyListeners();
    await _saveSerits();
    if (_user != null && _autoSync) {
      try {
        _firestoreUserId ??= await _firestoreService.getOrCreateSiralId(
          _user!.uid,
        );
        await _firestoreService.deleteSerit(_firestoreUserId!, id);
      } catch (e) {
        debugPrint('Firestore delete serit error: $e');
      }
    }
  }

  void cleanUnusedDefaultCategories() {
    final defaultTags = ['Genel', 'İş', 'Kişisel', 'Eğitim'];
    final usedEventTags = <String>{};
    final usedTaskTags = <String>{};
    final usedEventSubTags = <String>{};
    final usedTaskSubTags = <String>{};

    for (var event in _events) {
      if (event.tag.isNotEmpty) usedEventTags.add(event.tag);
      if (event.subTag != null && event.subTag!.isNotEmpty) {
        usedEventSubTags.add(event.subTag!);
      }
    }
    for (var task in _tasks) {
      if (task.tag.isNotEmpty) usedTaskTags.add(task.tag);
      if (task.subTag != null && task.subTag!.isNotEmpty) {
        usedTaskSubTags.add(task.subTag!);
      }
    }
    for (var project in _projects) {
      if (project.tag.isNotEmpty) usedTaskTags.add(project.tag);
      if (project.subTag != null && project.subTag!.isNotEmpty) {
        usedTaskSubTags.add(project.subTag!);
      }
    }

    // 1a. Clean unused default event categories
    final eventTagsToRemove = <String>[];
    for (var tag in defaultTags) {
      if (!usedEventTags.contains(tag) && _eventTags.contains(tag)) {
        eventTagsToRemove.add(tag);
      }
    }
    if (eventTagsToRemove.isNotEmpty) {
      _eventTags.removeWhere((tag) => eventTagsToRemove.contains(tag));
      _selectedEventTags.removeWhere((tag) => eventTagsToRemove.contains(tag));
      for (var tag in eventTagsToRemove) {
        _eventSubTags.remove(tag);
      }
    }

    // 1b. Clean unused default task categories
    final taskTagsToRemove = <String>[];
    for (var tag in defaultTags) {
      if (!usedTaskTags.contains(tag) && _taskTags.contains(tag)) {
        taskTagsToRemove.add(tag);
      }
    }
    if (taskTagsToRemove.isNotEmpty) {
      _taskTags.removeWhere((tag) => taskTagsToRemove.contains(tag));
      _selectedTaskTags.removeWhere((tag) => taskTagsToRemove.contains(tag));
      for (var tag in taskTagsToRemove) {
        _taskSubTags.remove(tag);
      }
    }

    // 2. Clean unused default subtags
    final defaultSubTagsMap = {
      'İş': ['Yazılım', 'Tasarım', 'Toplantı', 'Rutin'],
      'Kişisel': ['Sağlık', 'Finans', 'Kitap Okuma'],
      'Eğitim': ['Flutter', 'İngilizce', 'Üniversite'],
    };

    // Event subtags
    defaultSubTagsMap.forEach((category, defaultSubs) {
      if (_eventSubTags.containsKey(category)) {
        final currentSubs = _eventSubTags[category]!;
        final subsToRemove = defaultSubs
            .where(
              (sub) =>
                  !usedEventSubTags.contains(sub) && currentSubs.contains(sub),
            )
            .toList();
        if (subsToRemove.isNotEmpty) {
          currentSubs.removeWhere((sub) => subsToRemove.contains(sub));
          _selectedEventSubTags.removeWhere(
            (sub) => subsToRemove.contains(sub),
          );
        }
      }
    });

    // Task subtags
    defaultSubTagsMap.forEach((category, defaultSubs) {
      if (_taskSubTags.containsKey(category)) {
        final currentSubs = _taskSubTags[category]!;
        final subsToRemove = defaultSubs
            .where(
              (sub) =>
                  !usedTaskSubTags.contains(sub) && currentSubs.contains(sub),
            )
            .toList();
        if (subsToRemove.isNotEmpty) {
          currentSubs.removeWhere((sub) => subsToRemove.contains(sub));
          _selectedTaskSubTags.removeWhere((sub) => subsToRemove.contains(sub));
        }
      }
    });
  }

  Future<void> _saveTopics() async {
    final prefs = await SharedPreferences.getInstance();
    final topicsJson = _topics.map((t) => json.encode(t.toJson())).toList();
    await prefs.setStringList('topics', topicsJson);
  }

  Future<void> _saveTopicPlans() async {
    final prefs = await SharedPreferences.getInstance();
    final plansJson = _topicPlans.map((p) => json.encode(p.toJson())).toList();
    await prefs.setStringList('topicPlans', plansJson);
  }

  void addTopic(Topic topic) async {
    _topics.add(topic);
    notifyListeners();
    await _saveTopics();
    _firestoreSaveTopic(topic);
  }

  void updateTopic(Topic topic) async {
    final idx = _topics.indexWhere((t) => t.id == topic.id);
    if (idx != -1) {
      _topics[idx] = topic;
      notifyListeners();
      await _saveTopics();
      _firestoreSaveTopic(topic);
    }
  }

  void deleteTopic(String id) async {
    _topics.removeWhere((t) => t.id == id);
    // Delete plans associated with the topic
    final toDelete = _topicPlans.where((p) => p.topicId == id).toList();
    for (final p in toDelete) {
      _firestoreDeleteTopicPlan(p.id);
    }
    _topicPlans.removeWhere((p) => p.topicId == id);
    notifyListeners();
    await _saveTopics();
    await _saveTopicPlans();
    _firestoreDeleteTopic(id);
  }

  void addTopicPlan(TopicPlan plan) async {
    _topicPlans.add(plan);
    _expandParentIfNeeded(plan);
    notifyListeners();
    await _saveTopicPlans();
    for (var p in _topicPlans) {
      _firestoreSaveTopicPlan(p);
    }
    if (!plan.isInPool && plan.projectId != null) {
      await repackColumns(plan.projectId!);
    }
  }

  void _runWaitingPlansCatchUp() {
    bool changedGlobal = false;
    for (int i = 0; i < _topicPlans.length; i++) {
      final planItem = _topicPlans[i];
      if (planItem.status == 'Bekleyenler' && planItem.waitingSince != null) {
        final start = planItem.waitingSince!;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final normalizedStart = DateTime(start.year, start.month, start.day);

        final updatedReports = Map<String, PlanDayReport>.from(
          planItem.dayReports,
        );
        var current = normalizedStart;
        bool changed = false;
        while (!current.isAfter(today)) {
          final key =
              '${current.year}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}';
          if (!updatedReports.containsKey(key)) {
            updatedReports[key] = PlanDayReport(
              offset: 0,
              hoursWorked: 0,
              isWaiting: true,
            );
            changed = true;
          } else if (updatedReports[key]!.hoursWorked == 0 &&
              !updatedReports[key]!.isWaiting) {
            updatedReports[key] = PlanDayReport(
              offset: updatedReports[key]!.offset,
              note: updatedReports[key]!.note,
              hoursWorked: 0,
              isWaiting: true,
            );
            changed = true;
          }
          current = current.add(const Duration(days: 1));
        }
        if (changed) {
          _topicPlans[i] = planItem.copyWith(dayReports: updatedReports);
          changedGlobal = true;
        }
      }
    }
    if (changedGlobal) {
      _saveTopicPlans();
    }
  }

  void updateTopicPlan(TopicPlan plan) async {
    var updatedPlan = plan;
    final hasHours = updatedPlan.dayReports.values.any(
      (r) => r.hoursWorked > 0,
    );
    if (hasHours &&
        (updatedPlan.status == 'Yapılacak' ||
            updatedPlan.status == 'Bekleyenler' ||
            updatedPlan.status == 'Başlanmadı')) {
      updatedPlan = updatedPlan.copyWith(status: 'Yapılıyor');
    } else if (!hasHours &&
        (updatedPlan.status == 'Yapılıyor' ||
            updatedPlan.status == 'Yapılanlar')) {
      updatedPlan = updatedPlan.copyWith(status: 'Yapılacak');
    }

    if (updatedPlan.status == 'Bekleyenler') {
      if (updatedPlan.waitingSince == null) {
        updatedPlan = updatedPlan.copyWith(waitingSince: DateTime.now());
      }
      final start = updatedPlan.waitingSince!;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final normalizedStart = DateTime(start.year, start.month, start.day);

      final updatedReports = Map<String, PlanDayReport>.from(
        updatedPlan.dayReports,
      );
      var current = normalizedStart;
      while (!current.isAfter(today)) {
        final key =
            '${current.year}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}';
        if (!updatedReports.containsKey(key)) {
          updatedReports[key] = PlanDayReport(
            offset: 0,
            hoursWorked: 0,
            isWaiting: true,
          );
        } else if (updatedReports[key]!.hoursWorked == 0 &&
            !updatedReports[key]!.isWaiting) {
          updatedReports[key] = PlanDayReport(
            offset: updatedReports[key]!.offset,
            note: updatedReports[key]!.note,
            hoursWorked: 0,
            isWaiting: true,
          );
        }
        current = current.add(const Duration(days: 1));
      }
      updatedPlan = updatedPlan.copyWith(dayReports: updatedReports);
    } else {
      if (updatedPlan.waitingSince != null) {
        updatedPlan = updatedPlan.copyWith(clearWaitingSince: true);
      }
    }

    if (updatedPlan.id.startsWith('general_plan_')) {
      final projectId = updatedPlan.projectId;
      final generalEvals = _evaluations
          .where(
            (e) =>
                e.projectId == projectId &&
                e.sessionDate.year == updatedPlan.year &&
                e.stepId == null,
          )
          .toList();

      // Add or update evaluations based on plan.dayReports
      for (var entry in plan.dayReports.entries) {
        final dateKey = entry.key;
        final report = entry.value;
        final dateParts = dateKey.split('-');
        final date = DateTime(
          int.parse(dateParts[0]),
          int.parse(dateParts[1]),
          int.parse(dateParts[2]),
        );

        final existingIdx = _evaluations.indexWhere(
          (e) => e.projectId == projectId && e.sessionDate == date,
        );
        if (existingIdx != -1) {
          final old = _evaluations[existingIdx];
          _evaluations[existingIdx] = ProjectEvaluation(
            id: old.id,
            projectId: old.projectId,
            sessionDate: old.sessionDate,
            score: report.performancePercent ?? old.score,
            isSkipped: report.offset == 1,
            durationHours: old.durationHours,
            note: report.note,
            isTimeless: old.isTimeless,
            performancePercent: report.performancePercent,
            trackingValues: old.trackingValues,
            stepId: null,
          );
          _firestoreSaveEvaluation(_evaluations[existingIdx]);
        } else {
          final newEval = ProjectEvaluation(
            id: IdGenerator.generate('degerlendirme_$projectId'),
            projectId: projectId!,
            sessionDate: date,
            score: report.performancePercent ?? 0.0,
            isSkipped: report.offset == 1,
            durationHours: 1.0,
            note: report.note,
            isTimeless: true,
            performancePercent: report.performancePercent,
            trackingValues: const [],
            stepId: null,
          );
          _evaluations.add(newEval);
          _firestoreSaveEvaluation(newEval);
        }
      }

      // Delete evaluations that were removed
      for (var oldEval in generalEvals) {
        final dayKey =
            '${oldEval.sessionDate.year}-${oldEval.sessionDate.month.toString().padLeft(2, '0')}-${oldEval.sessionDate.day.toString().padLeft(2, '0')}';
        if (!plan.dayReports.containsKey(dayKey)) {
          _evaluations.remove(oldEval);
          _firestoreDeleteEvaluation(projectId!, oldEval.sessionDate);
        }
      }

      notifyListeners();
      _saveEvaluations();
      return;
    }

    final idx = _topicPlans.indexWhere((p) => p.id == updatedPlan.id);
    if (idx != -1) {
      final oldPlan = _topicPlans[idx];
      _topicPlans[idx] = updatedPlan;
      _expandParentIfNeeded(updatedPlan);
      _resolveAllDependencies(updatedPlan, oldPlan);
      notifyListeners();
      await _saveTopicPlans();
      for (var p in _topicPlans) {
        _firestoreSaveTopicPlan(p);
      }
      if (!updatedPlan.isInPool && updatedPlan.projectId != null) {
        await repackColumns(updatedPlan.projectId!);
      }
    }
  }

  int _getWeekOfMonth(DateTime date) {
    int day = date.day;
    if (day <= 7) return 1;
    if (day <= 14) return 2;
    if (day <= 21) return 3;
    return 4;
  }

  void _expandParentIfNeeded(TopicPlan childPlan) {
    if (childPlan.parentId == null) return;
    final parentIdx = _topicPlans.indexWhere((p) => p.id == childPlan.parentId);
    if (parentIdx == -1) return;
    final parent = _topicPlans[parentIdx];

    bool parentChanged = false;
    DateTime newStart = parent.startDate;
    DateTime newEnd = parent.endDate;

    if (childPlan.startDate.isBefore(parent.startDate)) {
      newStart = childPlan.startDate;
      parentChanged = true;
    }
    if (childPlan.actualEndDate.isAfter(parent.actualEndDate)) {
      final diff = childPlan.actualEndDate
          .difference(parent.actualEndDate)
          .inDays;
      newEnd = parent.endDate.add(Duration(days: diff));
      parentChanged = true;
    }

    if (parentChanged) {
      final updatedParent = parent.copyWith(
        startDate: newStart,
        endDate: newEnd,
        year: newStart.year,
        startMonth: newStart.month,
        startWeek: _getWeekOfMonth(newStart),
        endMonth: newEnd.month,
        endWeek: _getWeekOfMonth(newEnd),
      );
      _topicPlans[parentIdx] = updatedParent;

      _resolveAllDependencies(updatedParent, parent);
      _expandParentIfNeeded(updatedParent);
    }
  }

  void _resolveAllDependencies(TopicPlan updatedPlan, TopicPlan oldPlan) {
    void propagateShift(TopicPlan parentNew, TopicPlan parentOld) {
      final int deltaDays = parentNew.dependsOnType == 'SS'
          ? parentNew.startDate.difference(parentOld.startDate).inDays
          : parentNew.actualEndDate.difference(parentOld.actualEndDate).inDays;

      for (int i = 0; i < _topicPlans.length; i++) {
        final child = _topicPlans[i];
        if (child.dependsOnPlanId == parentNew.id) {
          if (deltaDays != 0) {
            final newStart = child.startDate.add(Duration(days: deltaDays));
            final newEnd = child.endDate.add(Duration(days: deltaDays));

            final updatedChild = child.copyWith(
              startDate: newStart,
              endDate: newEnd,
              year: newStart.year,
              startMonth: newStart.month,
              startWeek: _getWeekOfMonth(newStart),
              endMonth: newEnd.month,
              endWeek: _getWeekOfMonth(newEnd),
            );

            _topicPlans[i] = updatedChild;
            _expandParentIfNeeded(updatedChild);

            propagateShift(updatedChild, child);
          }
        }
      }
    }

    propagateShift(updatedPlan, oldPlan);
  }

  void deleteTopicPlan(String id) async {
    final targetPlans = _topicPlans
        .where((p) => p.id == id || p.parentId == id)
        .toList();
    final topicIdsToCheck = targetPlans
        .map((p) => p.topicId)
        .where((tid) => tid.isNotEmpty)
        .toSet();
    final projectIdsToRepack = targetPlans
        .map((p) => p.projectId)
        .where((pid) => pid != null)
        .toSet();

    final toDelete = _topicPlans
        .where((p) => p.id == id || p.parentId == id)
        .toList();
    for (final p in toDelete) {
      _firestoreDeleteTopicPlan(p.id);
    }
    _topicPlans.removeWhere((p) => p.id == id || p.parentId == id);
    // Clear dependencies pointing to this plan
    for (int i = 0; i < _topicPlans.length; i++) {
      if (_topicPlans[i].dependsOnPlanId == id) {
        _topicPlans[i] = _topicPlans[i].copyWith(clearDependency: true);
        _firestoreSaveTopicPlan(_topicPlans[i]);
      }
    }
    notifyListeners();
    await _saveTopicPlans();

    for (final topicId in topicIdsToCheck) {
      final hasPlansLeft = _topicPlans.any((p) => p.topicId == topicId);
      if (!hasPlansLeft) {
        deleteTopic(topicId);
      }
    }

    for (final projectId in projectIdsToRepack) {
      if (projectId != null) {
        await repackColumns(projectId);
      }
    }
  }

  bool isPlanActiveOnDate(TopicPlan plan, DateTime date) {
    final targetDate = DateTime(date.year, date.month, date.day);
    final String dateKey =
        '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';
    if (plan.dayReports.containsKey(dateKey) &&
        (plan.dayReports[dateKey]?.hoursWorked ?? 0) > 0) {
      return true;
    }
    if (plan.status == 'Yapılacak' ||
        plan.status == 'Bekleyenler' ||
        plan.status == 'Başlanmadı') {
      return false;
    }

    DateTime? firstEntryDate;
    for (var entry in plan.dayReports.entries) {
      if (entry.value.hoursWorked > 0) {
        try {
          final entryDate = DateTime.parse(entry.key);
          if (firstEntryDate == null || entryDate.isBefore(firstEntryDate)) {
            firstEntryDate = entryDate;
          }
        } catch (_) {}
      }
    }

    final occupationStart =
        firstEntryDate ??
        DateTime(plan.startDate.year, plan.startDate.month, plan.startDate.day);
    final normalizedStart = DateTime(
      occupationStart.year,
      occupationStart.month,
      occupationStart.day,
    );

    if (targetDate.isBefore(normalizedStart)) {
      return false;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (plan.status == 'Tamamlandı') {
      DateTime? lastEntryDate;
      for (var entry in plan.dayReports.entries) {
        if (entry.value.hoursWorked > 0) {
          try {
            final entryDate = DateTime.parse(entry.key);
            if (lastEntryDate == null || entryDate.isAfter(lastEntryDate)) {
              lastEntryDate = entryDate;
            }
          } catch (_) {}
        }
      }
      final occupationEnd =
          lastEntryDate ??
          DateTime(plan.endDate.year, plan.endDate.month, plan.endDate.day);
      final normalizedEnd = DateTime(
        occupationEnd.year,
        occupationEnd.month,
        occupationEnd.day,
      );
      return !targetDate.isAfter(normalizedEnd);
    } else {
      return !targetDate.isAfter(today);
    }
  }

  Future<void> repackColumns(String projectId) async {
    final projectPlans = _topicPlans
        .where((p) => p.projectId == projectId && !p.isInPool)
        .toList();

    DateTime getPlanStart(TopicPlan p) {
      DateTime? firstEntryDate;
      for (var entry in p.dayReports.entries) {
        if (entry.value.hoursWorked > 0) {
          try {
            final entryDate = DateTime.parse(entry.key);
            if (firstEntryDate == null || entryDate.isBefore(firstEntryDate)) {
              firstEntryDate = entryDate;
            }
          } catch (_) {}
        }
      }
      return firstEntryDate ?? p.startDate;
    }

    projectPlans.sort((a, b) => getPlanStart(a).compareTo(getPlanStart(b)));

    final projectTopics = _topics
        .where((t) => t.projectId == projectId)
        .toList();

    bool plansOverlap(TopicPlan a, TopicPlan b) {
      final startA = getPlanStart(a);
      final startB = getPlanStart(b);
      final minStart = startA.isBefore(startB) ? startA : startB;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      DateTime endA;
      if (a.status == 'Tamamlandı' || a.status == 'Yapılanlar') {
        endA = DateTime(a.endDate.year, a.endDate.month, a.endDate.day);
      } else {
        endA = today.isBefore(startB) ? startB : today;
      }

      DateTime endB;
      if (b.status == 'Tamamlandı' || b.status == 'Yapılanlar') {
        endB = DateTime(b.endDate.year, b.endDate.month, b.endDate.day);
      } else {
        endB = today.isBefore(startA) ? startA : today;
      }

      final maxEnd = endA.isAfter(endB) ? endA : endB;

      for (int i = 0; i <= maxEnd.difference(minStart).inDays; i++) {
        final checkDate = minStart.add(Duration(days: i));
        if (isPlanActiveOnDate(a, checkDate) &&
            isPlanActiveOnDate(b, checkDate)) {
          return true;
        }
      }
      return false;
    }

    final List<List<TopicPlan>> columns = [];

    for (final plan in projectPlans) {
      int colIdx = -1;
      for (int i = 0; i < columns.length; i++) {
        bool hasOverlap = false;
        for (final existingPlan in columns[i]) {
          if (plansOverlap(existingPlan, plan)) {
            hasOverlap = true;
            break;
          }
        }
        if (!hasOverlap) {
          colIdx = i;
          break;
        }
      }

      if (colIdx == -1) {
        columns.add([plan]);
        colIdx = columns.length - 1;
      } else {
        columns[colIdx].add(plan);
      }

      while (projectTopics.length <= colIdx) {
        final newTopicNum = projectTopics.length + 1;
        final newTopic = Topic(
          id: IdGenerator.generate('kolon_Kolon'),
          name: 'Kolon $newTopicNum',
          projectId: projectId,
        );
        _topics.add(newTopic);
        _firestoreSaveTopic(newTopic);
        projectTopics.add(newTopic);
      }

      final targetTopicId = projectTopics[colIdx].id;
      if (plan.topicId != targetTopicId) {
        final updatedPlan = plan.copyWith(topicId: targetTopicId);
        final idx = _topicPlans.indexWhere((p) => p.id == plan.id);
        if (idx != -1) {
          _topicPlans[idx] = updatedPlan;
          _firestoreSaveTopicPlan(updatedPlan);
        }
      }
    }

    final topicsToDelete = <Topic>[];
    for (final topic in projectTopics) {
      final hasPlans = _topicPlans.any(
        (p) => p.topicId == topic.id && !p.isInPool,
      );
      if (!hasPlans) {
        topicsToDelete.add(topic);
      }
    }

    for (final t in topicsToDelete) {
      _topics.removeWhere((x) => x.id == t.id);
      _firestoreDeleteTopic(t.id);
    }

    final updatedTopics = _topics
        .where((t) => t.projectId == projectId)
        .toList();
    for (int i = 0; i < updatedTopics.length; i++) {
      final oldTopic = updatedTopics[i];
      final newName = 'Kolon ${i + 1}';
      if (oldTopic.name != newName) {
        final idx = _topics.indexWhere((t) => t.id == oldTopic.id);
        if (idx != -1) {
          _topics[idx] = Topic(
            id: oldTopic.id,
            name: newName,
            projectId: oldTopic.projectId,
          );
          _firestoreSaveTopic(_topics[idx]);
        }
      }
    }

    notifyListeners();
    await _saveTopics();
    await _saveTopicPlans();
  }
}
