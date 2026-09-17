import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:math' as math;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

// المتغير العام لمشغل الإشعارات
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    try {
      // 1. تصحيح اسم الأيقونة
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('ic_launcher');
      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);
      await flutterLocalNotificationsPlugin.initialize(initializationSettings);

      // 2. طلب صلاحية الإشعارات من المستخدم
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      // 3. تشغيل الخدمة الخلفية
      await initializeBackgroundService();
    } catch (e) {
      print('خطأ في تشغيل الخدمة الخلفية: $e');
    }
  }

  runApp(const MasarakApp());
}

// ==========================================
// 1. تهيئة الجاسوس الصامت (الخدمة الخلفية)
// ==========================================
Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStartBackground,
      autoStart: true,
      isForegroundMode: true,
      // 🌟 التعديل هنا: اسم قناة خاص بالخدمة الصامتة فقط
      notificationChannelId: 'masarak_bg_service_channel',
      initialNotificationTitle: 'نظام مسارك نشط',
      initialNotificationContent:
          'يتم الآن تتبع الحافلة في الخلفية لتنبيهك فوراً',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStartBackground,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// ==========================================
// 2. عقل الجاسوس الصامت (ماذا يفعل وهو مغلق؟)
// ==========================================
@pragma('vm:entry-point')
void onStartBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  String? role = prefs.getString('role');
  String? studentId = prefs.getString('studentId');

  if (role == 'parent') {
    IO.Socket backgroundSocket =
        IO.io('https://masarak-aleppo.duckdns.org', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true
    });

    backgroundSocket.on('busNotification', (data) async {
      if (data['studentId'] == null || data['studentId'] == studentId) {
        String type = data['type'];
        String msg = data['msg'];
        String title = 'تحديث من الحافلة';

        if (type == 'approaching')
          title = '⚠️ الحافلة تقترب!';
        else if (type == 'emergency') // 🌟 السطر الجديد
          title = '🚨 حالة طوارئ/تأخير!'; // 🌟 السطر الجديد
        else if (type == 'student_boarded')
          title = '✅ تأكيد صعود';
        else if (type == 'student_dropped_off') // <--- السطر الجديد
          title = '🏠 تأكيد نزول'; // <--- السطر الجديد
        else if (type == 'student_absent')
          title = '❌ غياب الطالب';
        else if (type == 'trip_started')
          title = '🚀 انطلاق الرحلة';
        else if (type == 'trip_ended') title = '🏁 نهاية الرحلة';

        await showLoudNotification(title, msg);
      }
    });
  }
}

// ==========================================
// 3. دالة إطلاق الإشعار الصوتي بقوة (تهز الهاتف)
// ==========================================
Future<void> showLoudNotification(String title, String body) async {
  if (kIsWeb) return;
  // 🌟 التعديل هنا: إنشاء قناة جديدة (v3) لنجبر الهاتف على الرنين والاهتزاز
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'masarak_urgent_channel_v3',
    'إشعارات مسارك العاجلة',
    channelDescription: 'تنبيهات وصول الحافلة وصعود الطلاب',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
    visibility: NotificationVisibility.public,
  );

  const NotificationDetails platformDetails =
      NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecond,
    title,
    body,
    platformDetails,
  );
}

// ==========================================
// قاعدة البيانات المركزية المتصلة بالسيرفر
// ==========================================
final String serverUrl = 'https://masarak-aleppo.duckdns.org';
List<Map<String, dynamic>> globalBuses = [];
List<Map<String, dynamic>> globalStudents = [];
String globalAdminPhone = '0900000000';
final LatLng schoolLocation = const LatLng(36.28086, 37.03758);

// ==========================================
// دوال النظام الذكية (توجيه الشوارع وتصميم الباص)
// ==========================================
double calculateDistance(LatLng p1, LatLng p2) {
  var p = 0.017453292519943295;
  var c = math.cos;
  var a = 0.5 -
      c((p2.latitude - p1.latitude) * p) / 2 +
      c(p1.latitude * p) *
          c(p2.latitude * p) *
          (1 - c((p2.longitude - p1.longitude) * p)) /
          2;
  return 12742 * math.asin(math.sqrt(a)) * 1000;
}

Future<Map<String, dynamic>?> getRouteDetails(LatLng start, LatLng end) async {
  try {
    final url =
        'http://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final geometry = data['routes'][0]['geometry']['coordinates'] as List;
      return {
        'distance': data['routes'][0]['distance'],
        'duration': data['routes'][0]['duration'],
        'points': geometry.map((p) => LatLng(p[1], p[0])).toList()
      };
    }
  } catch (e) {
    print('OSRM Error: $e');
  }
  return null;
}

Future<List<LatLng>> getMultiPointRoute(List<LatLng> waypoints) async {
  if (waypoints.length < 2) return waypoints;
  try {
    String coords =
        waypoints.map((p) => '${p.longitude},${p.latitude}').join(';');
    final url =
        'http://router.project-osrm.org/route/v1/driving/$coords?overview=full&geometries=geojson';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final geometry = data['routes'][0]['geometry']['coordinates'] as List;
      return geometry.map((p) => LatLng(p[1], p[0])).toList();
    }
  } catch (e) {
    print('Multi OSRM Error: $e');
  }
  return waypoints;
}

Widget premiumBusIcon() {
  return Container(
      decoration: BoxDecoration(
          color: Colors.blueAccent,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(
                color: Colors.black54, blurRadius: 6, offset: Offset(0, 3))
          ]),
      child: const Center(
          child: Icon(Icons.directions_bus, color: Colors.white, size: 22)));
}

// ==========================================
// التطبيق الرئيسي
// ==========================================
class MasarakApp extends StatefulWidget {
  const MasarakApp({Key? key}) : super(key: key);
  @override
  _MasarakAppState createState() => _MasarakAppState();
}

class _MasarakAppState extends State<MasarakApp> {
  bool isLoading = true;
  Widget _initialScreen = const LoginScreen(); // الشاشة الافتراضية

  @override
  void initState() {
    super.initState();
    _initializeAppData();
  }

  Future<void> _initializeAppData() async {
    try {
      // 1. جلب البيانات من السيرفر
      final response = await http.get(Uri.parse('$serverUrl/api/data'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        globalBuses = List<Map<String, dynamic>>.from(data['buses'].map((b) => {
              'id': b['_id'],
              'number': b['number'],
              'routeName': b['routeName'],
              'driverName': b['driverName'],
              'driverPhone': b['driverPhone'],
              'isActive': b['isActive'],
              'location': b['location'] != null
                  ? LatLng(b['location']['lat'], b['location']['lng'])
                  : const LatLng(36.21, 37.14)
            }));

        globalStudents =
            List<Map<String, dynamic>>.from(data['students'].map((s) => {
                  'id': s['_id'],
                  'name': s['name'],
                  'seat': s['seat'],
                  'busId': s['busId'],
                  'password': s['password'],
                  'parentPhone': s['parentPhone'],
                  'address': s['address'],
                  'stopNumber': s['stopNumber'],
                  'status': s['status'],
                  'absenceCount':
                      s['absenceCount'] ?? 0, // 🌟 إضافة قراءة عداد الغياب
                  'home': s['home'] != null
                      ? LatLng(s['home']['lat'], s['home']['lng'])
                      : null
                }));
      }

      // 2. التحقق من الذاكرة (هل المستخدم مسجل دخول؟)
      final prefs = await SharedPreferences.getInstance();
      String? role = prefs.getString('role');
      Widget nextScreen = const LoginScreen();

      if (role == 'admin') {
        nextScreen = const AdminDashboard();
      } else if (role == 'driver') {
        String? busId = prefs.getString('busId');
        if (busId != null) {
          nextScreen = DriverDashboard(busId: busId);
        }
      } else if (role == 'parent') {
        String? studentId = prefs.getString('studentId');
        if (studentId != null) {
          var foundStudent = globalStudents
              .firstWhere((s) => s['id'] == studentId, orElse: () => {});
          if (foundStudent.isNotEmpty) {
            var assignedBus =
                globalBuses.firstWhere((b) => b['id'] == foundStudent['busId'],
                    orElse: () => {
                          'number': '؟',
                          'driverName': 'غير محدد',
                          'driverPhone': '',
                          'routeName': 'غير محدد'
                        });
            Map<String, dynamic> completeStudentData = {
              ...foundStudent,
              'busNumber': assignedBus['number'],
              'driverName': assignedBus['driverName'],
              'driverPhone': assignedBus['driverPhone'],
              'routeName': assignedBus['routeName'],
            };
            nextScreen = ParentDashboard(studentData: completeStudentData);
          }
        }
      }

      // 3. فتح التطبيق
      if (mounted) {
        setState(() {
          _initialScreen = nextScreen;
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error initializing data: $e');
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'المدرسة الوطنية الذكية',
      theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          primaryColor: const Color(0xFF2563EB)),
      home: isLoading
          ? const Scaffold(
              body: Center(
                  child: CircularProgressIndicator(color: Colors.blueAccent)))
          : _initialScreen, // فتح الشاشة المناسبة مباشرة
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // نفس دالة تسجيل الدخول السابقة بدون أي تغيير في المنطق
  void _attemptLogin() async {
    String enteredName = _usernameController.text.trim();
    String enteredPass = _passwordController.text.trim();
    final prefs = await SharedPreferences.getInstance();

    if (enteredName.isEmpty || enteredPass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('الرجاء إدخال الاسم وكلمة المرور'),
          backgroundColor: Colors.orange));
      return;
    }

    if (enteredName == 'admin' && enteredPass == 'admin') {
      await prefs.setString('role', 'admin');
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const AdminDashboard()));
      return;
    }

    var foundBus = globalBuses.firstWhere((b) => b['driverName'] == enteredName,
        orElse: () => {});
    if (foundBus.isNotEmpty && enteredPass == '1234') {
      await prefs.setString('role', 'driver');
      await prefs.setString('busId', foundBus['id'].toString());
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  DriverDashboard(busId: foundBus['id'].toString())));
      return;
    }

    var foundStudent = globalStudents
        .firstWhere((s) => s['name'] == enteredName, orElse: () => {});
    if (foundStudent.isNotEmpty) {
      if (foundStudent['password'] == enteredPass) {
        var assignedBus =
            globalBuses.firstWhere((b) => b['id'] == foundStudent['busId'],
                orElse: () => {
                      'number': '؟',
                      'driverName': 'غير محدد',
                      'driverPhone': '',
                      'routeName': 'غير محدد'
                    });
        Map<String, dynamic> completeStudentData = {
          ...foundStudent,
          'busNumber': assignedBus['number'],
          'driverName': assignedBus['driverName'],
          'driverPhone': assignedBus['driverPhone'],
          'routeName': assignedBus['routeName'],
        };

        await prefs.setString('role', 'parent');
        await prefs.setString('studentId', foundStudent['id']);
        await prefs.setString('busId', foundStudent['busId'] ?? '');
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    ParentDashboard(studentData: completeStudentData)));
        return;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('كلمة المرور غير صحيحة!'),
            backgroundColor: Colors.redAccent));
        return;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('بيانات الدخول غير صحيحة!'),
        backgroundColor: Colors.redAccent));
  }

  // 🌟 تصميم الواجهة الجديد كلياً 🌟
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // إضافة تدرج لوني أنيق للخلفية
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 50),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 🌟 الشعار مع تأثير التوهج (مكان الأيقونة القديمة)
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blueAccent.withOpacity(0.3),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/icon.png',
                      height: 160,
                      width: 160,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 50),

                // 🌟 حقل اسم المستخدم
                _buildModernTextField(
                  controller: _usernameController,
                  label: 'اسم المستخدم',
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 20),

                // 🌟 حقل كلمة المرور
                _buildModernTextField(
                  controller: _passwordController,
                  label: 'كلمة المرور',
                  icon: Icons.lock_outline,
                  isPassword: true,
                ),
                const SizedBox(height: 40),

                // 🌟 زر الدخول المتدرج
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Colors.blueAccent, Color(0xFF3B82F6)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blueAccent.withOpacity(0.4),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        )
                      ],
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      onPressed: _attemptLogin,
                      child: const Text(
                        'تسجيل الدخول',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // دالة مساعدة لرسم حقول الإدخال بشكل عصري
  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey.shade400),
        prefixIcon: Icon(icon, color: Colors.blueAccent, size: 22),
        filled: true,
        fillColor: const Color(0xFF1E293B).withOpacity(0.7), // خلفية الحقل
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Colors.blueAccent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 20),
      ),
    );
  }
}

// ==========================================
// 2. شاشة الكابتن (السائق / المشرف)
// ==========================================
class DriverDashboard extends StatefulWidget {
  final String busId;
  const DriverDashboard({Key? key, required this.busId}) : super(key: key);
  @override
  _DriverDashboardState createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  late IO.Socket socket;
  bool isConnected = false;
  bool isTracking = false;
  bool isMorningTrip = true;
  // 🌟 الميزة 3: متغير للتحكم بحجم الخريطة (مغلقة افتراضياً لتوفير المساحة)
  bool isMapExpanded = false; 
  
  double currentSpeed = 0.0;
  LatLng currentPos = const LatLng(36.2150, 37.1450);
  StreamSubscription<Position>? positionStream;
  final MapController mapController = MapController();
  final String serverUrl = 'https://masarak-aleppo.duckdns.org';
  final LatLng schoolLocation = const LatLng(36.28086, 37.03758);
  List<LatLng> streetRoute = [];
  Timer? _routeTimer;

  @override
  void initState() {
    super.initState();
    _initSocket();
    _requestPermissionsAndLocate();

    int currentHour = DateTime.now().hour;
    isMorningTrip = currentHour < 12;
  }

  Future<void> _requestPermissionsAndLocate() async {
    if (kIsWeb) return;

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      try {
        Position pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        if (mounted) {
          setState(() {
            currentPos = LatLng(pos.latitude, pos.longitude);
          });
          mapController.move(currentPos, 15.0);
        }
      } catch (e) {
        print('خطأ في جلب الموقع المبدئي: $e');
      }
    }
  }

  void _initSocket() {
    socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false
    });
    socket.connect();
    socket.onConnect((_) => setState(() => isConnected = true));
    socket.onDisconnect((_) => setState(() => isConnected = false));
  }

  void _sendNotification(String type, String msg, String? studentId) {
    if (isConnected) {
      socket.emit('busEvent', {
        'busId': widget.busId, 
        'type': type,
        'studentId': studentId,
        'msg': msg
      });
    }
  }

  void _updateDriverRoute() async {
    if (!isTracking) return;
    List<LatLng> waypoints = [currentPos];
    List busStudents =
        globalStudents.where((s) => s['busId'] == widget.busId).toList();
    busStudents.sort(
        (a, b) => (a['stopNumber'] ?? 99).compareTo(b['stopNumber'] ?? 99));
    if (!isMorningTrip) busStudents = busStudents.reversed.toList();
    for (var s in busStudents) {
      if (s['home'] != null && s['status'] == 'waiting')
        waypoints.add(s['home']);
    }
    if (isMorningTrip) waypoints.add(schoolLocation);
    final route = await getMultiPointRoute(waypoints);
    if (mounted) setState(() => streetRoute = route);
  }

  void _toggleTracking() async {
    if (isTracking) {
      positionStream?.cancel();
      _routeTimer?.cancel();
      setState(() {
        isTracking = false;
        streetRoute = [];
      });
      _sendNotification(
          'trip_ended',
          isMorningTrip ? 'وصلت الحافلة بسلام.' : 'تم إنهاء رحلة العودة بنجاح.',
          null);
    } else {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('الرجاء تفعيل موقع الهاتف (GPS) أولاً!'),
            backgroundColor: Colors.red));
        return;
      }

      setState(() => isTracking = true);
      _sendNotification('trip_started', 'انطلقت الحافلة.', null);

      try {
        Position initialPosition = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.bestForNavigation);
        setState(() {
          currentPos =
              LatLng(initialPosition.latitude, initialPosition.longitude);
        });
        mapController.move(currentPos, 15.0);

        if (isConnected) {
          socket.emit('updateLocation', {
            'busId': widget.busId,
            'lat': currentPos.latitude,
            'lng': currentPos.longitude
          });
        }
      } catch (e) {
        print("خطأ تحديد الموقع المبدئي: $e");
      }

      for (var s in globalStudents) {
        s['alertSent'] = false;
        s['status'] = 'waiting';
      }

      _updateDriverRoute();
      _routeTimer = Timer.periodic(
          const Duration(seconds: 15), (_) => _updateDriverRoute());

      positionStream = Geolocator.getPositionStream(
              locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.bestForNavigation,
                  distanceFilter: 5))
          .listen((Position position) {
        setState(() {
          currentSpeed = (position.speed * 3.6);
          currentPos = LatLng(position.latitude, position.longitude);
          mapController.move(currentPos, 15.0);
        });

        if (isConnected) {
          socket.emit('updateLocation', {
            'busId': widget.busId,
            'lat': position.latitude,
            'lng': position.longitude
          });
        }

        final busStudents =
            globalStudents.where((s) => s['busId'] == widget.busId).toList();
        for (var student in busStudents) {
          if (student['home'] != null &&
              student['status'] == 'waiting' &&
              student['alertSent'] != true) {
            if (calculateDistance(currentPos, student['home']) < 300) {
              student['alertSent'] = true;
              _sendNotification('approaching',
                  'الحافلة تقترب! المسافة أقل من 300 متر.', student['id']);
            }
          }
        }
      });
    }
  }

  @override
  void dispose() {
    positionStream?.cancel();
    _routeTimer?.cancel();
    socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List busStudents =
        globalStudents.where((s) => s['busId'] == widget.busId).toList();
    busStudents.sort(
        (a, b) => (a['stopNumber'] ?? 99).compareTo(b['stopNumber'] ?? 99));
    if (!isMorningTrip) busStudents = busStudents.reversed.toList();
    List<Marker> mapMarkers = [
      Marker(
          point: schoolLocation,
          width: 50,
          height: 50,
          child: const Text('🏫', style: TextStyle(fontSize: 35))),
      ...busStudents
          .map((s) => Marker(
              point: s['home'] ?? schoolLocation,
              width: 60,
              height: 60,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(
                    radius: 10,
                    backgroundColor: Colors.red,
                    child: Text('${s['stopNumber'] ?? '-'}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10))),
                const Text('📍', style: TextStyle(fontSize: 15))
              ])))
          .toList(),
      Marker(point: currentPos, width: 50, height: 50, child: premiumBusIcon()),
    ];

    bool canEndTrip = false;
    if (isTracking) {
      if (isMorningTrip) {
        canEndTrip = calculateDistance(currentPos, schoolLocation) <= 300;
      } else {
        canEndTrip = busStudents.isEmpty ||
            busStudents.every(
                (s) => s['status'] == 'boarded' || s['status'] == 'absent');
      }
    }
    
    return Scaffold(
      appBar: AppBar(
          backgroundColor: const Color(0xFF1E293B),
          leading: IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear(); 
                Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()));
              }),
          title: Text(
              'المشرف ${globalBuses.firstWhere((b) => b['id'] == widget.busId, orElse: () => {
                    'driverName': ''
                  })['driverName']}',
              style: const TextStyle(fontSize: 14)),
          actions: [
            if (!isTracking)
              TextButton.icon(
                  icon: Icon(
                      isMorningTrip ? Icons.wb_sunny : Icons.nightlight_round,
                      color: Colors.orangeAccent),
                  label: Text(isMorningTrip ? 'ذهاب' : 'عودة',
                      style: const TextStyle(color: Colors.white)),
                  onPressed: () =>
                      setState(() => isMorningTrip = !isMorningTrip)),
            Icon(Icons.circle,
                color: isConnected ? Colors.greenAccent : Colors.redAccent,
                size: 14),
            const SizedBox(width: 15)
          ]),
      body: Column(children: [
        // 🌟 الميزة 3: خريطة مرنة تأخذ 20% افتراضياً (flex: 1) وتكبر عند الحاجة (flex: 3)
        Expanded(
            flex: isMapExpanded ? 3 : 1,
            child: Stack(
              children: [
                FlutterMap(
                    mapController: mapController,
                    options:
                        MapOptions(initialCenter: currentPos, initialZoom: 14.0),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                        subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
                        userAgentPackageName: 'com.example.masarak',
                        maxZoom: 19.0,
                      ),
                      PolylineLayer(polylines: [
                        Polyline(
                            points:
                                streetRoute.isNotEmpty ? streetRoute : [currentPos],
                            strokeWidth: 4.0,
                            color: Colors.blueAccent)
                      ]),
                      MarkerLayer(markers: mapMarkers)
                    ]),
                // زر توسيع / تصغير الخريطة
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: const Color(0xFF1E293B).withOpacity(0.9),
                    child: Icon(
                      isMapExpanded ? Icons.fullscreen_exit : Icons.fullscreen, 
                      color: Colors.blueAccent
                    ),
                    onPressed: () => setState(() => isMapExpanded = !isMapExpanded),
                  ),
                )
              ],
            )),
        // مساحة قائمة الطلاب تتسع تلقائياً عند تصغير الخريطة
        Expanded(
            flex: isMapExpanded ? 2 : 4,
            child: Container(
                padding: const EdgeInsets.all(15),
                decoration: const BoxDecoration(color: Color(0xFF0F172A)),
                child: Column(children: [
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                            onTap: () {
                              if (!isTracking) {
                                _toggleTracking(); 
                              } else if (canEndTrip) {
                                // 🌟 الميزة 2: التسليم الجماعي عند الضغط على إنهاء الرحلة (الذهاب)
                                if (isMorningTrip) {
                                  for (var st in busStudents) {
                                    if (st['status'] == 'boarded') {
                                      _sendNotification(
                                          'student_dropped_off',
                                          'تم تسليم ${st['name']} للمدرسة بنجاح.',
                                          st['id']);
                                    }
                                  }
                                }
                                _toggleTracking(); 
                              } else {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                  content: Text(isMorningTrip
                                      ? '🔒 لا يمكن إنهاء الرحلة! يجب الاقتراب من المدرسة مسافة 300 متر.'
                                      : '🔒 لا يمكن إنهاء الرحلة! يجب إنزال جميع الطلاب أو تسجيل غيابهم.'),
                                  backgroundColor: Colors.orange,
                                ));
                              }
                            },
                            child: Container(
                                height: 55,
                                decoration: BoxDecoration(
                                    color: !isTracking
                                        ? Colors.blueAccent
                                        : (canEndTrip
                                            ? Colors.green // لون أخضر لزر الإنهاء والتسليم
                                            : Colors.grey.shade700),
                                    borderRadius: BorderRadius.circular(15)),
                                child: Center(
                                    child: Text(
                                        !isTracking
                                            ? 'بدء الرحلة والتتبع'
                                            : (canEndTrip
                                                ? (isMorningTrip ? 'تسليم الجميع وإنهاء الرحلة' : 'إنهـاء الرحلـة')
                                                : 'إنهـاء الرحلـة (مقفل)'),
                                        style: TextStyle(
                                            fontSize: 16,
                                            color: !isTracking || canEndTrip
                                                ? Colors.white
                                                : Colors.grey.shade400,
                                            fontWeight: FontWeight.bold))))),
                      ),
                      if (isTracking) ...[
                        const SizedBox(width: 10),
                        Container(
                          height: 55,
                          width: 55,
                          decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(15)),
                          child: IconButton(
                            icon: const Icon(Icons.warning_amber_rounded,
                                color: Colors.white, size: 28),
                            onPressed: () {
                              _sendNotification(
                                  'emergency',
                                  '⚠️ عطل أو تأخير طارئ في مسار الحافلة!',
                                  null);
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(
                                content: Text('تم إرسال تنبيه التأخير لجميع الركاب.'),
                                backgroundColor: Colors.red,
                              ));
                            },
                          ),
                        )
                      ]
                    ],
                  ),
                  const SizedBox(height: 15),
                  Expanded(
                      child: ListView.builder(
                          itemCount: busStudents.length,
                          itemBuilder: (ctx, i) {
                            final st = busStudents[i];
                            double dist = (st['home'] != null)
                                ? calculateDistance(currentPos, st['home'])
                                : 9999;
                            bool isNear = dist <= 300;
                            return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(10)),
                                child: Row(
                                    children: [
                                      CircleAvatar(
                                          radius: 12,
                                          backgroundColor: Colors.blueGrey,
                                          child: Text(
                                              '${st['stopNumber'] ?? '-'}',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10))),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(st['name'],
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 13)),
                                              Text(
                                                  st['status'] == 'boarded'
                                                      ? 'صعد للحافلة'
                                                      : st['status'] == 'absent'
                                                          ? 'غائب'
                                                          : 'في الانتظار',
                                                  style: TextStyle(
                                                      color: st['status'] ==
                                                              'boarded'
                                                          ? Colors.green
                                                          : st['status'] ==
                                                                  'absent'
                                                              ? Colors.red
                                                              : Colors.grey,
                                                      fontSize: 11))
                                            ]),
                                      ),
                                      // 🌟 الميزة 1: أيقونة الاتصال السريع بولي الأمر
                                      if (st['parentPhone'] != null && st['parentPhone'].toString().isNotEmpty)
                                        IconButton(
                                          icon: const Icon(Icons.phone, color: Colors.greenAccent, size: 22),
                                          onPressed: () async {
                                            final url = Uri.parse('tel:${st['parentPhone']}');
                                            try {
                                              await launchUrl(url);
                                            } catch (e) {
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح تطبيق الاتصال')));
                                            }
                                          },
                                        ),
                                        
                                      st['home'] == null
                                          ? ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.orangeAccent,
                                                  shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(10)),
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5)),
                                              icon: const Icon(Icons.add_location_alt, size: 16, color: Colors.white),
                                              label: const Text('تثبيت الموقف', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                              onPressed: () async {
                                                try {
                                                  int currentMaxStop = 0;
                                                  for (var student in globalStudents) {
                                                    if (student['busId'] == widget.busId) {
                                                      int stop = student['stopNumber'] ?? 99;
                                                      if (stop != 99 && stop > currentMaxStop) {
                                                        currentMaxStop = stop;
                                                      }
                                                    }
                                                  }
                                                  int newStopNumber = currentMaxStop + 1;
                                                  final response = await http.put(
                                                    Uri.parse('$serverUrl/api/students/${st['id']}'),
                                                    headers: {'Content-Type': 'application/json'},
                                                    body: json.encode({
                                                      'home': {'lat': currentPos.latitude, 'lng': currentPos.longitude},
                                                      'stopNumber': newStopNumber
                                                    }),
                                                  );

                                                  if (response.statusCode == 200) {
                                                    setState(() {
                                                      st['home'] = LatLng(currentPos.latitude, currentPos.longitude);
                                                      st['stopNumber'] = newStopNumber; 
                                                    });
                                                    _updateDriverRoute(); 
                                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                                      content: Text('📍 تم حفظ موقف ${st['name']} بنجاح!'),
                                                      backgroundColor: Colors.green,
                                                    ));
                                                  }
                                                } catch (e) {
                                                  print('خطأ في حفظ الموقع والترتيب: $e');
                                                }
                                              })
                                          : Row(mainAxisSize: MainAxisSize.min, children: [
                                              IconButton(
                                                  icon: Icon(Icons.check_circle,
                                                      color: st['status'] == 'boarded'
                                                          ? Colors.green
                                                          : (isNear ? Colors.blueAccent : Colors.grey),
                                                      size: 26),
                                                  onPressed: (isNear && st['status'] != 'boarded')
                                                      ? () {
                                                          setState(() => st['status'] = 'boarded');
                                                          _sendNotification(
                                                              isMorningTrip ? 'student_boarded' : 'student_dropped_off',
                                                              isMorningTrip ? 'صعد ${st['name']} إلى الحافلة بنجاح.' : 'نزل ${st['name']} بسلام.',
                                                              st['id']);
                                                          _updateDriverRoute();
                                                        }
                                                      : null),
                                              IconButton(
                                                  icon: Icon(Icons.cancel,
                                                      color: st['status'] == 'absent'
                                                          ? Colors.red
                                                          : (isNear ? Colors.orangeAccent : Colors.grey),
                                                      size: 26),
                                                  onPressed: (isNear && st['status'] != 'absent')
                                                      ? () {
                                                          setState(() => st['status'] = 'absent');
                                                          _sendNotification('student_absent', 'لم يصعد ${st['name']} للحافلة.', st['id']);
                                                          _updateDriverRoute();
                                                        }
                                                      : null)
                                            ])
                                    ]));
                          }))
                ])))
      ]),
    );
  }
}

// ==========================================
// 3. شاشة ولي الأمر المحدثة
// ==========================================
class ParentDashboard extends StatefulWidget {
  final Map<String, dynamic> studentData;
  const ParentDashboard({Key? key, required this.studentData})
      : super(key: key);

  @override
  _ParentDashboardState createState() => _ParentDashboardState();
}

class _ParentDashboardState extends State<ParentDashboard> {
  late IO.Socket socket;
  bool isConnected = false;
  LatLng busPos = const LatLng(36.2150, 37.1450);
  final MapController mapController = MapController();
  final String serverUrl = 'https://masarak-aleppo.duckdns.org';
  bool isReturnTrip = false;
  bool alertSent = false;
  String distanceText = '--';
  String etaText = '--';
  List<LatLng> routePoints = [];
  Timer? _routeTimer;

  @override
  void initState() {
    super.initState();
    _initSocket();
    _routeTimer = Timer.periodic(
        const Duration(seconds: 5), (timer) => _fetchRealRoute());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkBatteryOptimization();
    });
  }

  void _checkBatteryOptimization() async {
    if (kIsWeb) return;
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Row(
            children: [
              Icon(Icons.battery_alert, color: Colors.orange, size: 30),
              SizedBox(width: 10),
              Text('تنبيه هام جداً! ⚠️',
                  style: TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
          content: const Text(
            'لضمان وصول تنبيهات اقتراب الحافلة (الاهتزاز والصوت) في وقتها الدقيق حتى لو كانت شاشة الهاتف مغلقة، يجب السماح للتطبيق بالعمل في الخلفية دون قيود من نظام البطارية.\n\nاضغط "موافق" ثم اختر "السماح" أو "بدون قيود".',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('لاحقاً', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              onPressed: () async {
                Navigator.pop(context);
                await Permission.ignoreBatteryOptimizations.request();
              },
              child: const Text('موافق',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }

  void _fetchRealRoute() async {
    LatLng? home = widget.studentData['home'];
    if (home == null) return;
    LatLng targetLocation = !isReturnTrip
        ? ((widget.studentData['status'] == 'boarded') ? schoolLocation : home)
        : home;
    final routeData = await getRouteDetails(busPos, targetLocation);
    if (routeData != null && mounted) {
      setState(() {
        routePoints = routeData['points'];
        distanceText =
            '${(routeData['distance'] / 1000).toStringAsFixed(1)} كم';
        etaText = '${(routeData['duration'] / 60).ceil()} دقيقة';
        if (targetLocation == home &&
            routeData['distance'] <= 300 &&
            !alertSent) {
          alertSent = true;
          _showNotification('الحافلة تقترب! (أقل من 300 متر)', 'approaching');
        }
      });
    }
  }

  void _initSocket() {
    socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false
    });
    socket.connect();
    socket.onConnect((_) => setState(() => isConnected = true));
    socket.onDisconnect((_) => setState(() => isConnected = false));
    socket.on('locationUpdated', (data) {
      if (data['busId'] == widget.studentData['busId'] && mounted) {
        setState(() {
          busPos = LatLng(data['lat'], data['lng']);
        });
      }
    });
    socket.on('busNotification', (data) {
      if (data['studentId'] == null ||
          data['studentId'] == widget.studentData['id']) {
        _showNotification(data['msg'], data['type']);
        if (data['type'] == 'trip_started') {
          _fetchRealRoute();
        }
      }
    });
  }

  void _showNotification(String message, String type) {
    if (!mounted) return;
    Color bgColor = Colors.blueAccent;
    IconData icon = Icons.info;
    String notificationTitle = 'تحديث من الحافلة';

    if (type == 'approaching') {
      bgColor = Colors.orange;
      icon = Icons.warning_amber_rounded;
      notificationTitle = '⚠️ الحافلة تقترب!';
    } else if (type == 'emergency') {
      bgColor = Colors.red;
      icon = Icons.warning;
      notificationTitle = '🚨 تنبيه طارئ!';
    } else if (type == 'student_boarded') {
      bgColor = Colors.green;
      icon = Icons.check_circle;
      notificationTitle = '✅ تأكيد صعود';
    } else if (type == 'student_dropped_off') {
      bgColor = Colors.teal;
      icon = Icons.home;
      notificationTitle = '🏠 تأكيد نزول';
    } else if (type == 'student_absent') {
      bgColor = Colors.redAccent;
      icon = Icons.cancel;
      notificationTitle = '❌ غياب الطالب';
    } else if (type == 'trip_started') {
      bgColor = Colors.purpleAccent;
      icon = Icons.directions_bus;
      notificationTitle = '🚀 انطلاق الرحلة';
    } else if (type == 'trip_ended') {
      bgColor = Colors.purpleAccent;
      icon = Icons.directions_bus;
      notificationTitle = '🏁 نهاية الرحلة';
    }

    showLoudNotification(notificationTitle, message);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(width: 15),
          Expanded(
              child: Text(message,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)))
        ]),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 20, left: 15, right: 15),
        duration: const Duration(seconds: 5),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))));
  }

  // 🌟 دالة إرسال إشعار الغياب المسبق للسائق
  void _reportAbsence() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('تأكيد الغياب', style: TextStyle(color: Colors.white)),
        content: const Text('هل أنت متأكد من رغبتك في تبليغ السائق بغياب الطالب ليوم غد/اليوم؟', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() {
                widget.studentData['status'] = 'absent';
              });
              if (isConnected) {
                socket.emit('busEvent', {
                  'busId': widget.studentData['busId'],
                  'type': 'student_absent',
                  'studentId': widget.studentData['id'],
                  'msg': 'اعتذار مسبق: ولي أمر ${widget.studentData['name']} أبلغ عن غياب الطالب اليوم.'
                });
              }
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('✅ تم إرسال إشعار الغياب للسائق بنجاح.'),
                backgroundColor: Colors.green,
              ));
            },
            child: const Text('تأكيد الغياب', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _routeTimer?.cancel();
    socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String currentStatus = widget.studentData['status'] ?? 'waiting';

    return Scaffold(
      appBar: AppBar(
          backgroundColor: const Color(0xFF1E293B),
          leading: IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear(); 
                Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()));
              }),
          title: Text('ولي أمر: ${widget.studentData['name']}',
              style: const TextStyle(fontSize: 14)),
          actions: [
            // 🌟 1. زر تبليغ عن غياب مسبق في الشريط العلوي
            IconButton(
              icon: const Icon(Icons.person_off, color: Colors.orangeAccent),
              tooltip: 'تبليغ عن غياب',
              onPressed: _reportAbsence,
            ),
            IconButton(
                icon: Icon(
                    isReturnTrip ? Icons.nightlight_round : Icons.wb_sunny,
                    color: Colors.yellow),
                onPressed: () {
                  setState(() {
                    isReturnTrip = !isReturnTrip;
                    alertSent = false;
                  });
                }),
            Icon(Icons.circle,
                color: isConnected ? Colors.greenAccent : Colors.redAccent,
                size: 14),
            const SizedBox(width: 15)
          ]),
      body: Stack(children: [
        FlutterMap(
            mapController: mapController,
            options: MapOptions(initialCenter: busPos, initialZoom: 14.0),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
                userAgentPackageName: 'com.example.masarak',
                maxZoom: 19.0,
              ),
              PolylineLayer(polylines: [
                Polyline(
                    points: routePoints,
                    strokeWidth: 4.0,
                    color: Colors.blueAccent)
              ]),
              MarkerLayer(markers: [
                if (widget.studentData['home'] != null)
                  Marker(
                      point: widget.studentData['home'],
                      width: 40,
                      height: 40,
                      child: const Text('📍', style: TextStyle(fontSize: 30))),
                Marker(
                    point: schoolLocation,
                    width: 40,
                    height: 40,
                    child: const Text('🏫', style: TextStyle(fontSize: 25))),
                Marker(
                    point: busPos,
                    width: 50,
                    height: 50,
                    child: premiumBusIcon()),
              ]),
            ]),

        // 🌟 2. شريط الحالة البصري (Timeline Tracker) أعلى الخريطة
        Positioned(
          top: 15,
          left: 15,
          right: 15,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withOpacity(0.95),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTimelineStep(
                  title: 'في الانتظار',
                  icon: Icons.hourglass_empty,
                  isActive: currentStatus == 'waiting',
                  isCompleted: currentStatus == 'boarded' || currentStatus == 'absent',
                ),
                _buildTimelineLine(),
                _buildTimelineStep(
                  title: currentStatus == 'absent' ? 'غائب اليوم' : 'صعد للحافلة',
                  icon: currentStatus == 'absent' ? Icons.cancel : Icons.directions_bus,
                  isActive: currentStatus == 'boarded',
                  isCompleted: currentStatus == 'dropped_off',
                  isAlert: currentStatus == 'absent',
                ),
                _buildTimelineLine(),
                _buildTimelineStep(
                  title: 'تم الوصول',
                  icon: Icons.check_circle_outline,
                  isActive: currentStatus == 'dropped_off',
                  isCompleted: false,
                ),
              ],
            ),
          ),
        ),

        // لوحة المعلومات السفلية (المسافة والوقت)
        Positioned(
            bottom: 110,
            left: 15,
            right: 15,
            child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: Colors.blueAccent.withOpacity(0.3))),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(children: [
                        const Text('المسافة',
                            style: TextStyle(color: Colors.grey, fontSize: 11)),
                        Text(distanceText,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16))
                      ]),
                      Column(children: [
                        const Text('الوقت المتوقع',
                            style: TextStyle(color: Colors.grey, fontSize: 11)),
                        Text(etaText,
                            style: const TextStyle(
                                color: Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 16))
                      ]),
                      Column(children: [
                        const Text('الوجهة',
                            style: TextStyle(color: Colors.grey, fontSize: 11)),
                        Text(
                            isReturnTrip
                                ? 'المنزل'
                                : (widget.studentData['status'] == 'boarded'
                                    ? 'المدرسة'
                                    : 'المنزل'),
                            style: const TextStyle(
                                color: Colors.blueAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 14))
                      ])
                    ]))),

        // 🌟 3. بطاقة المشرف المنبثقة السفلية (Driver Info Card)
        Positioned(
          bottom: 15,
          left: 15,
          right: 15,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.blueAccent,
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'المشرف: ${widget.studentData['driverName'] ?? 'غير محدد'}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'حافلة رقم: ${widget.studentData['busNumber'] ?? '؟'}',
                          style: const TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
                // زر الاتصال المباشر بالمشرف
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.phone, color: Colors.white, size: 16),
                  label: const Text('اتصال', style: TextStyle(color: Colors.white, fontSize: 12)),
                  onPressed: () async {
                    final String? phone = widget.studentData['driverPhone'];
                    if (phone != null && phone.isNotEmpty) {
                      final Uri url = Uri.parse('tel:$phone');
                      try {
                        await launchUrl(url);
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('تعذر فتح تطبيق الاتصال'),
                          backgroundColor: Colors.red,
                        ));
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('رقم المشرف غير متوفر حالياً'),
                        backgroundColor: Colors.orange,
                      ));
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // دوال مساعدة لرسم خطوات شريط الحالة البصري
  Widget _buildTimelineStep({required String title, required IconData icon, required bool isActive, required bool isCompleted, bool isAlert = false}) {
    Color color = Colors.grey;
    if (isAlert) color = Colors.redAccent;
    else if (isActive) color = Colors.blueAccent;
    else if (isCompleted) color = Colors.green;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.2),
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(height: 4),
        Text(title, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildTimelineLine() {
    return Expanded(
      child: Container(
        height: 2,
        color: Colors.grey.withOpacity(0.4),
        margin: const EdgeInsets.symmetric(horizontal: 5),
      ),
    );
  }
}

// ==========================================
// 4. شاشة الإدارة المركزية
// ==========================================
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({Key? key}) : super(key: key);
  @override
  _AdminDashboardState createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _currentIndex = 0;
  final MapController mapController = MapController();
  late IO.Socket socket;
  String? selectedTrackedBusId;
  List<LatLng> adminStreetRoute = [];
  List<dynamic> tripLogs = []; // 🌟 قائمة سجل الرحلات

  @override
  void initState() {
    super.initState();
    _initAdminSocket();
    _fetchTripLogs(); // 🌟 جلب السجلات عند فتح لوحة الإدارة
  }

  // 🌟 الدالة الجديدة لجلب سجلات الرحلات من السيرفر
  Future<void> _fetchTripLogs() async {
    try {
      final response = await http.get(Uri.parse('$serverUrl/api/trip-logs'));
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            tripLogs = json.decode(response.body);
          });
        }
      }
    } catch (e) {
      print('Error fetching trip logs: $e');
    }
  }

  void _initAdminSocket() {
    socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false
    });
    socket.connect();
    socket.on('locationUpdated', (data) {
      if (mounted) {
        setState(() {
          var busIndex =
              globalBuses.indexWhere((b) => b['id'] == data['busId']);
          if (busIndex != -1)
            globalBuses[busIndex]['location'] =
                LatLng(data['lat'], data['lng']);
        });
      }
    });
  }

  @override
  void dispose() {
    socket.dispose();
    super.dispose();
  }

  void _showAddBusDialog() {
    String bNum = '';
    String rName = '';
    String dName = '';
    String dPhone = '';
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Text('إضافة حافلة',
                  style: TextStyle(color: Colors.white)),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                        labelText: 'رقم الحافلة',
                        labelStyle: TextStyle(color: Colors.grey)),
                    onChanged: (val) => bNum = val),
                TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                        labelText: 'المسار',
                        labelStyle: TextStyle(color: Colors.grey)),
                    onChanged: (val) => rName = val),
                TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                        labelText: 'اسم المشرف',
                        labelStyle: TextStyle(color: Colors.grey)),
                    onChanged: (val) => dName = val),
                TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                        labelText: 'هاتف المشرف',
                        labelStyle: TextStyle(color: Colors.grey)),
                    keyboardType: TextInputType.phone,
                    onChanged: (val) => dPhone = val),
              ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('إلغاء',
                        style: TextStyle(color: Colors.redAccent))),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent),
                    onPressed: () async {
                      if (bNum.isNotEmpty) {
                        Navigator.pop(ctx);
                        try {
                          final response = await http.post(
                            Uri.parse('$serverUrl/api/buses'),
                            headers: {'Content-Type': 'application/json'},
                            body: json.encode({
                              'number': bNum,
                              'routeName': rName,
                              'driverName': dName,
                              'driverPhone': dPhone,
                              'isActive': false,
                              'location': {'lat': 36.24, 'lng': 37.11}
                            }),
                          );
                          if (response.statusCode == 200) {
                            final savedBus = json.decode(response.body);
                            setState(() {
                              globalBuses.add({
                                'id': savedBus['_id'],
                                'number': savedBus['number'],
                                'routeName': savedBus['routeName'],
                                'driverName': savedBus['driverName'],
                                'driverPhone': savedBus['driverPhone'],
                                'isActive': savedBus['isActive'],
                                'location': const LatLng(36.24, 37.11)
                              });
                            });
                          }
                        } catch (e) {
                          print('خطأ في حفظ الحافلة: $e');
                        }
                      }
                    },
                    child: const Text('حفظ',
                        style: TextStyle(color: Colors.white))),
              ],
            ));
  }

  void _showAddStudentDialog() {
    String sName = '';
    String seat = '';
    String pass = '';
    String phone = '';
    String addr = '';
    String? sBus;
    String stopNum = '';
    LatLng? homeLocation;

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (context, setStateDialog) {
              return AlertDialog(
                backgroundColor: const Color(0xFF1E293B),
                title: const Text('إضافة طالب',
                    style: TextStyle(color: Colors.white)),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                          labelText: 'اسم الطالب',
                          labelStyle: TextStyle(color: Colors.grey)),
                      onChanged: (val) => sName = val),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                                labelText: 'ترتيب الموقف',
                                labelStyle: TextStyle(color: Colors.grey)),
                            keyboardType: TextInputType.number,
                            onChanged: (val) => stopNum = val)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: TextField(
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                                labelText: 'المقعد',
                                labelStyle: TextStyle(color: Colors.grey)),
                            onChanged: (val) => seat = val)),
                  ]),
                  TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                          labelText: 'هاتف الولي',
                          labelStyle: TextStyle(color: Colors.grey)),
                      keyboardType: TextInputType.phone,
                      onChanged: (val) => phone = val),
                  TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                          labelText: 'كلمة المرور',
                          labelStyle: TextStyle(color: Colors.grey)),
                      onChanged: (val) => pass = val),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                                labelText: 'العنوان',
                                labelStyle: TextStyle(color: Colors.grey)),
                            onChanged: (val) => addr = val)),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: homeLocation != null
                                ? Colors.green
                                : Colors.blueAccent),
                        icon: const Icon(Icons.location_on,
                            color: Colors.white, size: 16),
                        label: Text(
                            homeLocation != null ? 'تم التحديد' : 'الخريطة',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12)),
                        onPressed: () async {
                          final LatLng? picked = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => LocationPickerScreen(
                                      initialLocation: homeLocation)));
                          if (picked != null)
                            setStateDialog(() => homeLocation = picked);
                        })
                  ]),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                      dropdownColor: const Color(0xFF0F172A),
                      decoration: const InputDecoration(
                          labelText: 'اختر الحافلة',
                          labelStyle: TextStyle(color: Colors.grey)),
                      value: sBus,
                      items: globalBuses
                          .map((bus) => DropdownMenuItem<String>(
                              value: bus['id'].toString(),
                              child: Text('حافلة ${bus['number']}',
                                  style: const TextStyle(color: Colors.white))))
                          .toList(),
                      onChanged: (val) => setStateDialog(() => sBus = val)),
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('إلغاء',
                          style: TextStyle(color: Colors.redAccent))),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent),
                      onPressed: () async {
                        if (sName.isNotEmpty && sBus != null) {
                          int newStopNum = int.tryParse(stopNum) ?? 99;
// التعديل: استثناء الرقم 99 من فحص التكرار
                          bool stopNumberExists = newStopNum != 99 &&
                              globalStudents.any((s) =>
                                  s['busId'] == sBus &&
                                  s['stopNumber'] == newStopNum);

                          if (stopNumberExists) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        '⚠️ رقم الموقف محجوز مسبقاً لهذه الحافلة!'),
                                    backgroundColor: Colors.orangeAccent,
                                    duration: Duration(seconds: 4)));
                            return;
                          }

                          Navigator.pop(ctx);
                          try {
                            final response = await http.post(
                              Uri.parse('$serverUrl/api/students'),
                              headers: {'Content-Type': 'application/json'},
                              body: json.encode({
                                'name': sName,
                                'seat': seat,
                                'busId': sBus,
                                'password': pass,
                                'parentPhone': phone,
                                'address': addr,
                                'stopNumber': newStopNum,
                                'status': 'waiting',
                                'home': homeLocation != null
                                    ? {
                                        'lat': homeLocation!.latitude,
                                        'lng': homeLocation!.longitude
                                      }
                                    : null
                              }),
                            );
                            if (response.statusCode == 200) {
                              final savedStudent = json.decode(response.body);
                              setState(() {
                                globalStudents.add({
                                  'id': savedStudent['_id'],
                                  'name': savedStudent['name'],
                                  'seat': savedStudent['seat'],
                                  'busId': savedStudent['busId'],
                                  'password': savedStudent['password'],
                                  'parentPhone': savedStudent['parentPhone'],
                                  'address': savedStudent['address'],
                                  'stopNumber': savedStudent['stopNumber'],
                                  'status': savedStudent['status'],
                                  'alertSent': false,
                                  'home': homeLocation ??
                                      const LatLng(36.2150, 37.1450)
                                });
                              });
                            }
                          } catch (e) {
                            print('خطأ في حفظ الطالب: $e');
                          }
                        }
                      },
                      child: const Text('حفظ',
                          style: TextStyle(color: Colors.white))),
                ],
              );
            }));
  }

  void _showEditBusDialog(int index) {
    final bus = globalBuses[index];
    String bNum = bus['number'];
    String rName = bus['routeName'];
    String dName = bus['driverName'];
    String dPhone = bus['driverPhone'];
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Text('تعديل بيانات الحافلة',
                  style: TextStyle(color: Colors.white)),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                    initialValue: bNum,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                        labelText: 'رقم الحافلة',
                        labelStyle: TextStyle(color: Colors.blueAccent)),
                    onChanged: (val) => bNum = val),
                TextFormField(
                    initialValue: rName,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                        labelText: 'المسار',
                        labelStyle: TextStyle(color: Colors.blueAccent)),
                    onChanged: (val) => rName = val),
                TextFormField(
                    initialValue: dName,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                        labelText: 'اسم المشرف',
                        labelStyle: TextStyle(color: Colors.blueAccent)),
                    onChanged: (val) => dName = val),
                TextFormField(
                    initialValue: dPhone,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                        labelText: 'هاتف المشرف',
                        labelStyle: TextStyle(color: Colors.blueAccent)),
                    keyboardType: TextInputType.phone,
                    onChanged: (val) => dPhone = val)
              ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('إلغاء',
                        style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () async {
                      try {
                        final response = await http.put(
                          Uri.parse('$serverUrl/api/buses/${bus['id']}'),
                          headers: {'Content-Type': 'application/json'},
                          body: json.encode({
                            'number': bNum,
                            'routeName': rName,
                            'driverName': dName,
                            'driverPhone': dPhone
                          }),
                        );
                        if (response.statusCode == 200) {
                          setState(() {
                            globalBuses[index] = {
                              ...bus,
                              'number': bNum,
                              'routeName': rName,
                              'driverName': dName,
                              'driverPhone': dPhone
                            };
                          });
                          Navigator.pop(ctx);
                        }
                      } catch (e) {
                        print('خطأ التعديل: $e');
                      }
                    },
                    child: const Text('تحديث',
                        style: TextStyle(color: Colors.white))),
              ],
            ));
  }

  void _showEditStudentDialog(int index) {
    final st = globalStudents[index];
    String sName = st['name'];
    String seat = st['seat'];
    String pass = st['password'];
    String phone = st['parentPhone'];
    String addr = st['address'];
    String? sBus = st['busId'];
    String stopNum = (st['stopNumber'] ?? 99).toString();
    LatLng? homeLocation = st['home'];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Text('تعديل الطالب',
                  style: TextStyle(color: Colors.white)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                        initialValue: sName,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                            labelText: 'اسم الطالب',
                            labelStyle: TextStyle(color: Colors.blueAccent)),
                        onChanged: (val) => sName = val),
                    Row(children: [
                      Expanded(
                          child: TextFormField(
                              initialValue: stopNum,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                  labelText: 'ترتيب الموقف',
                                  labelStyle:
                                      TextStyle(color: Colors.blueAccent)),
                              keyboardType: TextInputType.number,
                              onChanged: (val) => stopNum = val)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: TextFormField(
                              initialValue: seat,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                  labelText: 'المقعد',
                                  labelStyle:
                                      TextStyle(color: Colors.blueAccent)),
                              onChanged: (val) => seat = val)),
                    ]),
                    TextFormField(
                        initialValue: phone,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                            labelText: 'هاتف الولي',
                            labelStyle: TextStyle(color: Colors.blueAccent)),
                        keyboardType: TextInputType.phone,
                        onChanged: (val) => phone = val),
                    TextFormField(
                        initialValue: pass,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                            labelText: 'كلمة المرور',
                            labelStyle: TextStyle(color: Colors.blueAccent)),
                        onChanged: (val) => pass = val),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: TextFormField(
                              initialValue: addr,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                  labelText: 'العنوان',
                                  labelStyle:
                                      TextStyle(color: Colors.blueAccent)),
                              onChanged: (val) => addr = val)),
                      const SizedBox(width: 5),
                      // 🌟 الزر الجديد: يظهر فقط إذا كان للطالب موقع مثبت
                      if (homeLocation != null)
                        IconButton(
                          icon: const Icon(Icons.location_off, color: Colors.redAccent),
                          tooltip: 'حذف الموقع المثبت',
                          onPressed: () => setStateDialog(() => homeLocation = null),
                        ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: homeLocation != null
                                ? Colors.green
                                : Colors.blueAccent),
                        icon: const Icon(Icons.location_on,
                            color: Colors.white, size: 16),
                        label: Text(
                            homeLocation != null ? 'تحديث الموقع' : 'الخريطة',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12)),
                        onPressed: () async {
                          final LatLng? picked = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => LocationPickerScreen(
                                      initialLocation: homeLocation)));
                          if (picked != null)
                            setStateDialog(() => homeLocation = picked);
                        },
                      ),
                    ]),
                    const SizedBox(height: 15),
                    DropdownButtonFormField<String>(
                      dropdownColor: const Color(0xFF0F172A),
                      decoration: const InputDecoration(
                          labelText: 'الحافلة',
                          labelStyle: TextStyle(color: Colors.blueAccent)),
                      value: sBus,
                      items: globalBuses
                          .map((bus) => DropdownMenuItem<String>(
                              value: bus['id'].toString(),
                              child: Text('حافلة ${bus['number']}',
                                  style: const TextStyle(color: Colors.white))))
                          .toList(),
                      onChanged: (val) => setStateDialog(() => sBus = val),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('إلغاء',
                        style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: () async {
                    if (sName.isNotEmpty && sBus != null) {
                      int newStopNum = int.tryParse(stopNum) ?? 99;
// التعديل: استثناء الرقم 99 من فحص التكرار
                      bool stopNumberExists = newStopNum != 99 &&
                          globalStudents.any((s) =>
                              s['busId'] == sBus &&
                              s['stopNumber'] == newStopNum &&
                              s['id'] != st['id']);

                      if (stopNumberExists) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('⚠️ رقم الموقف محجوز مسبقاً!'),
                                backgroundColor: Colors.orangeAccent));
                        return;
                      }

                      try {
                        final response = await http.put(
                          Uri.parse('$serverUrl/api/students/${st['id']}'),
                          headers: {'Content-Type': 'application/json'},
                          body: json.encode({
                            'name': sName,
                            'seat': seat,
                            'busId': sBus,
                            'password': pass,
                            'parentPhone': phone,
                            'address': addr,
                            'stopNumber': newStopNum,
                            'home': homeLocation != null
                                ? {
                                    'lat': homeLocation!.latitude,
                                    'lng': homeLocation!.longitude
                                  }
                                : null
                          }),
                        );
                        if (response.statusCode == 200) {
                          setState(() {
                            globalStudents[index] = {
                              ...st,
                              'name': sName,
                              'seat': seat,
                              'busId': sBus,
                              'password': pass,
                              'parentPhone': phone,
                              'address': addr,
                              'stopNumber': newStopNum,
                              'home': homeLocation
                            };
                          });
                          Navigator.pop(ctx);
                        }
                      } catch (e) {
                        print('خطأ التعديل: $e');
                      }
                    }
                  },
                  child: const Text('تحديث',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMapAndTrackingView() {
    List<Marker> markers = [
      Marker(
          point: schoolLocation,
          width: 40,
          height: 40,
          alignment: Alignment.topCenter,
          child: const Text('🏫', style: TextStyle(fontSize: 25)))
    ];
    List<Polyline> polylines = [];

    if (selectedTrackedBusId != null) {
      final bus = globalBuses.firstWhere((b) => b['id'] == selectedTrackedBusId,
          orElse: () => {});

      if (bus.isNotEmpty && bus['location'] != null) {
        markers.add(Marker(
            point: bus['location'],
            width: 50,
            height: 50,
            alignment: Alignment.center,
            child: premiumBusIcon()));

        final busStudents = globalStudents
            .where((s) => s['busId'] == selectedTrackedBusId)
            .toList();
        busStudents.sort(
            (a, b) => (a['stopNumber'] ?? 99).compareTo(b['stopNumber'] ?? 99));

        for (var st in busStudents) {
          if (st['home'] != null) {
            bool isPassed =
                st['status'] == 'boarded' || st['status'] == 'absent';
            markers.add(Marker(
                point: st['home'],
                width: 40,
                height: 40,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                        radius: 8,
                        backgroundColor:
                            isPassed ? Colors.grey : Colors.orangeAccent,
                        child: Text('${st['stopNumber'] ?? '-'}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 9))),
                    Icon(Icons.location_on,
                        color: isPassed ? Colors.grey : Colors.orangeAccent,
                        size: 20),
                  ],
                )));
          }
        }

        if (adminStreetRoute.isNotEmpty) {
          polylines.add(Polyline(
              points: adminStreetRoute,
              color: Colors.blueAccent,
              strokeWidth: 4.0));
        }
      }
    } else {
      markers.addAll(globalBuses.where((b) => b['location'] != null).map(
          (bus) => Marker(
              point: bus['location'],
              width: 50,
              height: 50,
              alignment: Alignment.center,
              child: premiumBusIcon())));
    }

    return Column(children: [
      Expanded(
          flex: 2,
          child: FlutterMap(
              mapController: mapController,
              options:
                  MapOptions(initialCenter: schoolLocation, initialZoom: 13.0),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                  subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
                  userAgentPackageName: 'com.example.masarak',
                  maxZoom: 19.0,
                ),
                PolylineLayer(polylines: polylines),
                MarkerLayer(markers: markers)
              ])),
      Expanded(
          flex: 3,
          child: Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(color: Color(0xFF0F172A)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12)),
                              icon: const Icon(Icons.directions_bus,
                                  color: Colors.white, size: 18),
                              label: const Text('إضافة حافلة',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                              onPressed: _showAddBusDialog)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12)),
                              icon: const Icon(Icons.person_add,
                                  color: Colors.white, size: 18),
                              label: const Text('إضافة طالب',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                              onPressed: _showAddStudentDialog))
                    ]),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('متابعة مسارات الحافلات:',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
                        if (selectedTrackedBusId != null)
                          TextButton(
                              onPressed: () {
                                setState(() {
                                  selectedTrackedBusId = null;
                                  adminStreetRoute = [];
                                });
                                mapController.move(schoolLocation, 13.0);
                              },
                              child: const Text('عرض الكل',
                                  style: TextStyle(color: Colors.redAccent)))
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                        child: ListView.builder(
                            itemCount: globalBuses.length,
                            itemBuilder: (context, index) {
                              final bus = globalBuses[index];
                              bool isTrackingThis =
                                  selectedTrackedBusId == bus['id'];
                              return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B),
                                      border: isTrackingThis
                                          ? Border.all(color: Colors.blueAccent)
                                          : null,
                                      borderRadius: BorderRadius.circular(10)),
                                  child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                  'حافلة ${bus['number']} - ${bus['routeName']}',
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                              Text(
                                                  'المشرف: ${bus['driverName']}',
                                                  style: const TextStyle(
                                                      color: Colors.grey,
                                                      fontSize: 12))
                                            ]),
                                        ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor: isTrackingThis
                                                    ? Colors.blueAccent
                                                    : Colors.grey
                                                        .withOpacity(0.2),
                                                elevation: 0),
                                            onPressed: () async {
                                              setState(() {
                                                selectedTrackedBusId =
                                                    bus['id'];
                                                adminStreetRoute = [];
                                              });
                                              if (bus['location'] != null) {
                                                mapController.move(
                                                    bus['location'], 14.0);

                                                List<LatLng> waypoints = [
                                                  bus['location']
                                                ];
                                                final bStudents = globalStudents
                                                    .where((s) =>
                                                        s['busId'] == bus['id'])
                                                    .toList();
                                                bStudents.sort((a, b) =>
                                                    (a['stopNumber'] ?? 99)
                                                        .compareTo(
                                                            b['stopNumber'] ??
                                                                99));

                                                for (var st in bStudents) {
                                                  if (st['home'] != null &&
                                                      st['status'] !=
                                                          'boarded' &&
                                                      st['status'] !=
                                                          'absent') {
                                                    waypoints.add(st['home']);
                                                  }
                                                }
                                                waypoints.add(schoolLocation);

                                                final route =
                                                    await getMultiPointRoute(
                                                        waypoints);
                                                if (mounted &&
                                                    selectedTrackedBusId ==
                                                        bus['id']) {
                                                  setState(() =>
                                                      adminStreetRoute = route);
                                                }
                                              }
                                            },
                                            child: Text('متابعة 📍',
                                                style: TextStyle(
                                                    color: isTrackingThis
                                                        ? Colors.white
                                                        : Colors.grey,
                                                    fontSize: 12)))
                                      ]));
                            }))
                  ])))
    ]);
  }

  Widget _buildStudentsDatabaseView() {
    final unassignedStudents = globalStudents
        .where((s) => s['busId'] == null || s['busId'] == '')
        .toList();
    return Container(
        color: const Color(0xFF0F172A),
        padding: const EdgeInsets.all(15),
        child: ListView(children: [
          const Padding(
              padding: EdgeInsets.only(bottom: 15, right: 5),
              child: Text('تصنيف الطلاب حسب الحافلات:',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold))),
          ...globalBuses.map((bus) {
            final busStudents =
                globalStudents.where((s) => s['busId'] == bus['id']).toList();
            busStudents.sort((a, b) =>
                (a['stopNumber'] ?? 99).compareTo(b['stopNumber'] ?? 99));
            return Card(
                color: const Color(0xFF1E293B),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
                child: Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                        iconColor: Colors.blueAccent,
                        collapsedIconColor: Colors.grey,
                        leading: const CircleAvatar(
                            backgroundColor: Colors.blueAccent,
                            child: Icon(Icons.directions_bus,
                                color: Colors.white, size: 20)),
                        title: Text(
                            'حافلة ${bus['number']} - المشرف: ${bus['driverName']}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        subtitle: Text('عدد الطلاب: ${busStudents.length}',
                            style: const TextStyle(
                                color: Colors.greenAccent, fontSize: 12)),
                        children: busStudents.map((student) {
                          int originalIndex = globalStudents.indexOf(student);
                          return Container(
                              margin: const EdgeInsets.symmetric(
                                      horizontal: 15, vertical: 5)
                                  .copyWith(bottom: 10),
                              decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color:
                                          Colors.blueAccent.withOpacity(0.2))),
                              child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 0),
                                  leading: CircleAvatar(
                                      radius: 12,
                                      backgroundColor: Colors.redAccent,
                                      child: Text('${student['stopNumber']}',
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.white))),
                                  title: Text(student['name'],
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14)),
                                  subtitle: Text(
                                      'المقعد: ${student['seat']} | الهاتف: ${student['parentPhone']}',
                                      style: const TextStyle(color: Colors.grey, fontSize: 11)),
                                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                    IconButton(
                                        icon: const Icon(Icons.edit,
                                            color: Colors.blue, size: 18),
                                        onPressed: () => setState(() =>
                                            _showEditStudentDialog(
                                                originalIndex))),
                                    IconButton(
                                        icon: const Icon(Icons.delete,
                                            color: Colors.red, size: 18),
                                        onPressed: () async {
                                          try {
                                            final response = await http.delete(
                                                Uri.parse(
                                                    '$serverUrl/api/students/${student['id']}'));
                                            if (response.statusCode == 200)
                                              setState(() => globalStudents
                                                  .removeAt(originalIndex));
                                          } catch (e) {
                                            print('خطأ الحذف: $e');
                                          }
                                        })
                                  ])));
                        }).toList())));
          }).toList(),
          if (unassignedStudents.isNotEmpty)
            Card(
                color: Colors.redAccent.withOpacity(0.1),
                margin: const EdgeInsets.only(top: 10, bottom: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: const BorderSide(color: Colors.redAccent)),
                child: Theme(
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                        iconColor: Colors.redAccent,
                        collapsedIconColor: Colors.redAccent,
                        leading: const CircleAvatar(
                            backgroundColor: Colors.redAccent,
                            child: Icon(Icons.warning,
                                color: Colors.white, size: 20)),
                        title: const Text('طلاب بدون حافلة مخصصة',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        subtitle: Text('العدد: ${unassignedStudents.length}',
                            style: const TextStyle(
                                color: Colors.orangeAccent, fontSize: 12)),
                        children: unassignedStudents.map((student) {
                          int originalIndex = globalStudents.indexOf(student);
                          return Container(
                              margin: const EdgeInsets.symmetric(
                                      horizontal: 15, vertical: 5)
                                  .copyWith(bottom: 10),
                              decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(10)),
                              child: ListTile(
                                  leading: const Icon(Icons.person,
                                      color: Colors.grey),
                                  title: Text(student['name'],
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                                  trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                            icon: const Icon(Icons.edit,
                                                color: Colors.blue, size: 18),
                                            onPressed: () => setState(() =>
                                                _showEditStudentDialog(
                                                    originalIndex))),
                                        IconButton(
                                            icon: const Icon(Icons.delete,
                                                color: Colors.red, size: 18),
                                            onPressed: () async {
                                              try {
                                                final response =
                                                    await http.delete(Uri.parse(
                                                        '$serverUrl/api/students/${student['id']}'));
                                                if (response.statusCode == 200)
                                                  setState(() => globalStudents
                                                      .removeAt(originalIndex));
                                              } catch (e) {
                                                print('خطأ الحذف: $e');
                                              }
                                            })
                                      ])));
                        }).toList())))
        ]));
  }

  Widget _buildDriversDatabaseView() {
    return Container(
        color: const Color(0xFF0F172A),
        padding: const EdgeInsets.all(15),
        child: ListView.builder(
            itemCount: globalBuses.length,
            itemBuilder: (context, index) {
              final bus = globalBuses[index];
              return Card(
                  color: const Color(0xFF1E293B),
                  margin: const EdgeInsets.only(bottom: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                  child: ListTile(
                      contentPadding: const EdgeInsets.all(15),
                      leading: const CircleAvatar(
                          backgroundColor: Colors.blueAccent,
                          child: Icon(Icons.person, color: Colors.white)),
                      title: Text(bus['driverName'],
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18)),
                      subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            Text(
                                'حافلة: ${bus['number']} (${bus['routeName']})',
                                style: const TextStyle(color: Colors.grey)),
                            const SizedBox(height: 5),
                            Text('الهاتف: ${bus['driverPhone']}',
                                style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontWeight: FontWeight.bold))
                          ]),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () =>
                                setState(() => _showEditBusDialog(index))),
                        IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              try {
                                final response = await http.delete(Uri.parse(
                                    '$serverUrl/api/buses/${bus['id']}'));
                                if (response.statusCode == 200) {
                                  setState(() {
                                    for (var s in globalStudents.where(
                                        (s) => s['busId'] == bus['id'])) {
                                      s['busId'] = '';
                                    }
                                    globalBuses.removeAt(index);
                                  });
                                }
                              } catch (e) {
                                print('خطأ الحذف: $e');
                              }
                            })
                      ])));
            }));
  }

// 🌟 الشاشة الجديدة لعرض التقارير (سجل الرحلات والغياب)
  Widget _buildReportsView() {
    final absentStudents =
        globalStudents.where((s) => (s['absenceCount'] ?? 0) > 0).toList();
    absentStudents.sort(
        (a, b) => (b['absenceCount'] ?? 0).compareTo(a['absenceCount'] ?? 0));

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            indicatorColor: Colors.blueAccent,
            labelColor: Colors.blueAccent,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(icon: Icon(Icons.history), text: 'سجل الرحلات'),
              Tab(icon: Icon(Icons.person_off), text: 'الغياب المتكرر'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                // 1. تبويب سجل الرحلات
                tripLogs.isEmpty
                    ? const Center(
                        child: Text('لا توجد رحلات مسجلة بعد',
                            style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(15),
                        itemCount: tripLogs.length,
                        itemBuilder: (ctx, i) {
                          final log = tripLogs[i];
                          final bus = globalBuses.firstWhere(
                              (b) => b['id'] == log['busId'],
                              orElse: () => {'number': '؟'});

                          DateTime start =
                              DateTime.parse(log['startTime']).toLocal();
                          String startTimeStr =
                              '${start.hour}:${start.minute.toString().padLeft(2, '0')}';
                          String endTimeStr = 'مستمرة الآن..';
                          if (log['endTime'] != null) {
                            DateTime end =
                                DateTime.parse(log['endTime']).toLocal();
                            endTimeStr =
                                '${end.hour}:${end.minute.toString().padLeft(2, '0')}';
                          }

                          return Card(
                            color: const Color(0xFF1E293B),
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: const CircleAvatar(
                                  backgroundColor: Colors.blueAccent,
                                  child: Icon(Icons.directions_bus,
                                      color: Colors.white)),
                              title: Text('حافلة ${bus['number']}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  'انطلاق: $startTimeStr | وصول: $endTimeStr',
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 12)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    log['status'] == 'completed'
                                        ? Icons.check_circle
                                        : Icons.sync,
                                    color: log['status'] == 'completed'
                                        ? Colors.green
                                        : Colors.orangeAccent,
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                                    onPressed: () async {
                                      // إضافة نافذة تأكيد قبل الحذف كإجراء احترافي
                                      bool? confirm = await showDialog(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          backgroundColor: const Color(0xFF1E293B),
                                          title: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white)),
                                          content: const Text('هل أنت متأكد من رغبتك في حذف سجل هذه الرحلة؟', style: TextStyle(color: Colors.grey)),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(ctx, false),
                                              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                              onPressed: () => Navigator.pop(ctx, true),
                                              child: const Text('حذف', style: TextStyle(color: Colors.white)),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (confirm == true) {
                                        try {
                                          final response = await http.delete(
                                              Uri.parse('$serverUrl/api/trip-logs/${log['_id']}'));
                                          if (response.statusCode == 200) {
                                            setState(() {
                                              tripLogs.removeAt(i);
                                            });
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('تم حذف الرحلة بنجاح'),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                          }
                                        } catch (e) {
                                          print('خطأ في حذف الرحلة: $e');
                                        }
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                // 2. تبويب الغياب المتكرر
                absentStudents.isEmpty
                    ? const Center(
                        child: Text('لا يوجد غياب مسجل للطلاب',
                            style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.all(15),
                        itemCount: absentStudents.length,
                        itemBuilder: (ctx, i) {
                          final student = absentStudents[i];
                          return Card(
                            color: const Color(0xFF1E293B),
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: const CircleAvatar(
                                  backgroundColor: Colors.redAccent,
                                  child: Icon(Icons.person_off,
                                      color: Colors.white)),
                              title: Text(student['name'],
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  'رقم الولي: ${student['parentPhone']}',
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 12)),
                              trailing: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: Colors.redAccent.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(10)),
                                child: Text(
                                    'غاب ${student['absenceCount']} مرات',
                                    style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ),
                          );
                        },
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
            backgroundColor: const Color(0xFF1E293B),
            leading: IconButton(
                icon: const Icon(Icons.logout, color: Colors.white),
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.clear(); // هذا الأمر سيمسح الذاكرة ويخرجك نهائياً
                  Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()));
                }),
            title: const Text('لوحة الإدارة المركزية',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        body: IndexedStack(index: _currentIndex, children: [
          _buildMapAndTrackingView(),
          _buildStudentsDatabaseView(),
          _buildDriversDatabaseView(),
          _buildReportsView() // 🌟 إضافة شاشة التقارير هنا
        ]),
        bottomNavigationBar: BottomNavigationBar(
            backgroundColor: const Color(0xFF1E293B),
            type: BottomNavigationBarType
                .fixed, // 🌟 ضروري ليظهر الشريط بشكل صحيح عند إضافة زر رابع
            selectedItemColor: Colors.blueAccent,
            unselectedItemColor: Colors.grey,
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.map), label: 'الخريطة'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.school), label: 'الطلاب'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.drive_eta), label: 'المشرفون'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.analytics),
                  label: 'التقارير') // 🌟 الزر الجديد
            ]));
  }
}

// ==========================================
// 5. شاشة التقاط الموقع من الخريطة
// ==========================================
class LocationPickerScreen extends StatefulWidget {
  final LatLng? initialLocation;
  const LocationPickerScreen({Key? key, this.initialLocation})
      : super(key: key);
  @override
  _LocationPickerScreenState createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late LatLng currentCenter;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    currentCenter = widget.initialLocation ?? const LatLng(36.2150, 37.1450);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('📍 اسحب الخريطة تحت الدبوس',
              style: TextStyle(fontSize: 14)),
          actions: [
            TextButton.icon(
                icon: const Icon(Icons.check_circle, color: Colors.greenAccent),
                label: const Text('تثبيت الموقع',
                    style: TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                onPressed: () {
                  Navigator.pop(context, _mapController.camera.center);
                })
          ]),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: currentCenter,
              initialZoom: 16.0,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
                userAgentPackageName: 'com.example.masarak',
                maxZoom: 19.0,
              ),
            ],
          ),
          const Align(
            alignment: Alignment.center,
            child: Padding(
              padding: EdgeInsets.only(bottom: 35.0),
              child: Icon(Icons.location_on, size: 45, color: Colors.redAccent),
            ),
          ),
          const Align(
            alignment: Alignment.center,
            child: CircleAvatar(radius: 3, backgroundColor: Colors.black),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.only(top: 20),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('حرك الخريطة لاختيار موقع منزل الطالب',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}
