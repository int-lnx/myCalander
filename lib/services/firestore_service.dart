import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/event.dart';
import '../models/task_item.dart';
import '../models/project.dart';
import '../models/project_evaluation.dart';
import '../models/serit.dart';
import '../models/day_note.dart';
import '../models/topic.dart';
import '../models/topic_plan.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Collection references helper
  CollectionReference _userCollection(String userId, String subCollection) {
    return _db.collection('users').doc(userId).collection(subCollection);
  }

  /// Firebase Auth UID'sini sirali Firestore ID'sine donusturur.
  /// Kullanici kayitli degilse siradaki numarayi alarak yeni ID olusturur.
  Future<String> getOrCreateSiralId(String authUid, {String? email}) async {
    return authUid;
  }

  // --- EVENTS ---
  Stream<List<Event>> getEvents(String userId) {
    return _userCollection(userId, 'events').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Event.fromJson(doc.data() as Map<String, dynamic>))
          .toList();
    });
  }

  Future<void> saveEvent(String userId, Event event) async {
    await _userCollection(userId, 'events').doc(event.id).set(event.toJson());
  }

  Future<void> deleteEvent(String userId, String eventId) async {
    await _userCollection(userId, 'events').doc(eventId).delete();
  }

  // --- TASKS ---
  Stream<List<TaskItem>> getTasks(String userId) {
    return _userCollection(userId, 'tasks').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => TaskItem.fromJson(doc.data() as Map<String, dynamic>))
          .toList();
    });
  }

  Future<void> saveTask(String userId, TaskItem task) async {
    await _userCollection(userId, 'tasks').doc(task.id).set(task.toJson());
  }

  Future<void> deleteTask(String userId, String taskId) async {
    await _userCollection(userId, 'tasks').doc(taskId).delete();
  }

  // --- PROJECTS ---
  Stream<List<Project>> getProjects(String userId) {
    return _userCollection(userId, 'projects').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Project.fromJson(doc.data() as Map<String, dynamic>))
          .toList();
    });
  }

  Future<void> saveProject(String userId, Project project) async {
    await _userCollection(
      userId,
      'projects',
    ).doc(project.id).set(project.toJson());
  }

  Future<void> deleteProject(String userId, String projectId) async {
    await _userCollection(userId, 'projects').doc(projectId).delete();
  }

  // --- PROJECT EVALUATIONS ---
  Stream<List<ProjectEvaluation>> getEvaluations(String userId) {
    return _userCollection(userId, 'evaluations').snapshots().map((snapshot) {
      return snapshot.docs
          .map(
            (doc) =>
                ProjectEvaluation.fromJson(doc.data() as Map<String, dynamic>),
          )
          .toList();
    });
  }

  Future<void> saveEvaluation(
    String userId,
    ProjectEvaluation evaluation,
  ) async {
    final docId =
        '${evaluation.projectId}_${evaluation.sessionDate.millisecondsSinceEpoch}';
    await _userCollection(
      userId,
      'evaluations',
    ).doc(docId).set(evaluation.toJson());
  }

  Future<void> deleteEvaluation(
    String userId,
    String projectId,
    DateTime sessionDate,
  ) async {
    final docId = '${projectId}_${sessionDate.millisecondsSinceEpoch}';
    await _userCollection(userId, 'evaluations').doc(docId).delete();
  }

  // --- SERITS ---
  Stream<List<Serit>> getSerits(String userId) {
    return _userCollection(userId, 'serits').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Serit.fromJson(doc.data() as Map<String, dynamic>))
          .toList();
    });
  }

  Future<void> saveSerit(String userId, Serit serit) async {
    await _userCollection(userId, 'serits').doc(serit.id).set(serit.toJson());
  }

  Future<void> deleteSerit(String userId, String seritId) async {
    await _userCollection(userId, 'serits').doc(seritId).delete();
  }

  // --- SETTINGS (CATEGORIES & PAINTED DAYS) ---

  /// Etkinlik kategorilerini Firestore'a kaydeder.
  Future<void> saveEventCategories(
    String userId,
    List<String> eventTags,
    Map<String, List<String>> eventSubTags,
  ) async {
    final Map<String, dynamic> subTagsJson = {};
    eventSubTags.forEach((key, value) {
      subTagsJson[key] = value;
    });
    await _db
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('eventCategories')
        .set({'eventTags': eventTags, 'eventSubTags': subTagsJson});
  }

  /// Etkinlik kategorilerini Firestore'dan okur.
  Future<Map<String, dynamic>?> getEventCategories(String userId) async {
    final doc = await _db
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('eventCategories')
        .get();
    return doc.data();
  }

  /// Görev kategorilerini Firestore'a kaydeder.
  Future<void> saveTaskCategories(
    String userId,
    List<String> taskTags,
    Map<String, List<String>> taskSubTags,
  ) async {
    final Map<String, dynamic> subTagsJson = {};
    taskSubTags.forEach((key, value) {
      subTagsJson[key] = value;
    });
    await _db
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('taskCategories')
        .set({'taskTags': taskTags, 'taskSubTags': subTagsJson});
  }

  /// Görev kategorilerini Firestore'dan okur.
  Future<Map<String, dynamic>?> getTaskCategories(String userId) async {
    final doc = await _db
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('taskCategories')
        .get();
    return doc.data();
  }

  /// [LEGACY] Eski birleşik kategori formatını okur (migration için).
  Future<Map<String, dynamic>?> getLegacyCategories(String userId) async {
    final doc = await _db
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('categories')
        .get();
    return doc.data();
  }

  /// [LEGACY] Eski birleşik kategori kaydı (migration sonrası silinmeli).
  Future<void> saveCategories(
    String userId,
    List<String> availableTags,
    Map<String, List<String>> categorySubTags,
  ) async {
    final Map<String, dynamic> subTagsJson = {};
    categorySubTags.forEach((key, value) {
      subTagsJson[key] = value;
    });
    await _db
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('categories')
        .set({'availableTags': availableTags, 'categorySubTags': subTagsJson});
  }

  Future<Map<String, dynamic>?> getCategories(String userId) async {
    final doc = await _db
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('categories')
        .get();
    return doc.data();
  }

  Future<void> savePaintedDays(
    String userId,
    Map<String, String> paintedDays,
  ) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('paintedDays')
        .set({'paintedDays': paintedDays});
  }

  Future<Map<String, dynamic>?> getPaintedDays(String userId) async {
    final doc = await _db
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('paintedDays')
        .get();
    return doc.data();
  }

  // --- DAY NOTES ---
  Stream<List<DayNote>> getDayNotes(String userId) {
    return _userCollection(userId, 'day_notes').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => DayNote.fromJson(doc.data() as Map<String, dynamic>))
          .toList();
    });
  }

  Future<void> saveDayNote(String userId, DayNote note) async {
    await _userCollection(userId, 'day_notes').doc(note.id).set(note.toJson());
  }

  Future<void> deleteDayNote(String userId, String noteId) async {
    await _userCollection(userId, 'day_notes').doc(noteId).delete();
  }

  // --- TOPICS ---
  Stream<List<Topic>> getTopics(String userId) {
    return _userCollection(userId, 'topics').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Topic.fromJson(doc.data() as Map<String, dynamic>))
          .toList();
    });
  }

  Future<void> saveTopic(String userId, Topic topic) async {
    await _userCollection(userId, 'topics').doc(topic.id).set(topic.toJson());
  }

  Future<void> deleteTopic(String userId, String topicId) async {
    await _userCollection(userId, 'topics').doc(topicId).delete();
  }

  // --- TOPIC PLANS ---
  Stream<List<TopicPlan>> getTopicPlans(String userId) {
    return _userCollection(userId, 'steps').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => TopicPlan.fromJson(doc.data() as Map<String, dynamic>))
          .toList();
    });
  }

  Future<void> saveTopicPlan(String userId, TopicPlan plan) async {
    await _userCollection(userId, 'steps').doc(plan.id).set(plan.toJson());
  }

  Future<void> deleteTopicPlan(String userId, String planId) async {
    await _userCollection(userId, 'steps').doc(planId).delete();
  }

  Future<void> saveQuickNote(String userId, String note) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('quickNote')
        .set({'note': note, 'updatedAt': DateTime.now().toIso8601String()});
  }

  Future<Map<String, dynamic>?> getQuickNote(String userId) async {
    final doc = await _db
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('quickNote')
        .get();
    return doc.data();
  }

  Future<void> saveCategoryColors(
    String userId,
    Map<String, int> eventTagColors,
    Map<String, int> taskTagColors,
  ) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('categoryColors')
        .set({
          'eventTagColors': eventTagColors,
          'taskTagColors': taskTagColors,
        });
  }

  Future<Map<String, dynamic>?> getCategoryColors(String userId) async {
    final doc = await _db
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('categoryColors')
        .get();
    return doc.data();
  }

  Future<void> saveTaskOrder(String userId, List<String> taskOrder) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('taskOrder')
        .set({'order': taskOrder, 'updatedAt': DateTime.now().toIso8601String()});
  }

  Future<Map<String, dynamic>?> getTaskOrder(String userId) async {
    final doc = await _db
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('taskOrder')
        .get();
    return doc.data();
  }
}

