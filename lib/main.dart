import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MasarakApp());
}

// ==========================================
// قاعدة البيانات المركزية المتصلة بالسيرفر
// ==========================================
final String serverUrl = 'https://masarak-aleppo.duckdns.org';
List<Map<String, dynamic>> globalBuses = [];
List<Map<String, dynamic>> globalStudents = [];
String globalAdminPhone = '0900000000';
final LatLng schoolLocation = const LatLng(36.28086, 37.03758);

class MasarakApp extends StatefulWidget {
  const MasarakApp({Key? key}) : super(key: key);
  @override
  _MasarakAppState createState() => _MasarakAppState();
}

class _MasarakAppState extends State<MasarakApp> {
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDataFromServer();
  }

  // دالة جلب البيانات من MongoDB
  Future<void> _fetchDataFromServer() async {
    try {
      final response = await http.get(Uri.parse('$serverUrl/api/data'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          // تحويل البيانات القادمة وتجهيز إحداثيات الخريطة
          globalBuses =
              List<Map<String, dynamic>>.from(data['buses'].map((b) => {
                    'id': b['_id'], // MongoDB تستخدم _id
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
                    'home': s['home'] != null
                        ? LatLng(s['home']['lat'], s['home']['lng'])
                        : null
                  }));
          isLoading = false; // إخفاء دائرة التحميل بعد جلب البيانات
        });
      }
    } catch (e) {
      print('Error fetching data: $e');
      setState(() => isLoading = false);
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
      // إظهار دائرة تحميل ريثما يتم جلب البيانات من السيرفر
      home: isLoading
          ? const Scaffold(
              body: Center(
                  child: CircularProgressIndicator(color: Colors.blueAccent)))
          : const LoginScreen(),
    );
  }
}

// ==========================================
// 1. شاشة تسجيل الدخول (مع حقل نصي للطالب بدل القائمة)
// ==========================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String selectedRole = 'driver';
  final TextEditingController _studentNameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _studentNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _attemptLogin() {
    if (selectedRole == 'driver') {
      // التعديل هنا فقط: إظهار نافذة اختيار الحافلة للسائق
      String? selectedBus;
      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Text('اختيار مسار الحافلة',
                  style: TextStyle(color: Colors.white)),
              content: DropdownButtonFormField<String>(
                dropdownColor: const Color(0xFF0F172A),
                decoration: const InputDecoration(
                    labelText: 'اختر حافلتك',
                    labelStyle: TextStyle(color: Colors.blueAccent)),
                items: globalBuses
                    .map((bus) => DropdownMenuItem<String>(
                          value: bus['id'].toString(),
                          child: Text(
                              'حافلة ${bus['number']} - ${bus['driverName']}',
                              style: const TextStyle(color: Colors.white)),
                        ))
                    .toList(),
                onChanged: (val) => setStateDialog(() => selectedBus = val),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('إلغاء',
                        style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent),
                  onPressed: () {
                    if (selectedBus != null) {
                      Navigator.pop(ctx);
                      // تمرير رقم الحافلة بنجاح لشاشة السائق
                      Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  DriverDashboard(busId: selectedBus!)));
                    }
                  },
                  child:
                      const Text('دخول', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        ),
      );
    } else if (selectedRole == 'admin') {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const AdminDashboard()));
    } else if (selectedRole == 'parent') {
      // كود الأهل الخاص بك كما هو تماماً دون أي مساس
      String enteredName = _studentNameController.text.trim();
      String enteredPass = _passwordController.text.trim();

      var foundStudent = globalStudents.firstWhere(
        (s) => s['name'] == enteredName,
        orElse: () => {},
      );

      if (foundStudent.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('اسم الطالب غير موجود في النظام!'),
            backgroundColor: Colors.redAccent));
      } else if (foundStudent['password'] != enteredPass) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('كلمة المرور غير صحيحة!'),
            backgroundColor: Colors.redAccent));
      } else {
        var assignedBus = globalBuses.firstWhere(
          (b) => b['id'] == foundStudent['busId'],
          orElse: () => {
            'number': '؟',
            'driverName': 'غير محدد',
            'driverPhone': '',
            'routeName': 'غير محدد'
          },
        );

        Map<String, dynamic> completeStudentData = {
          ...foundStudent,
          'busNumber': assignedBus['number'],
          'driverName': assignedBus['driverName'],
          'driverPhone': assignedBus['driverPhone'],
          'routeName': assignedBus['routeName'],
        };

        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    ParentDashboard(studentData: completeStudentData)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blueAccent.withOpacity(0.3))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.directions_bus,
                    size: 80, color: Colors.blueAccent),
                const SizedBox(height: 10),
                const Text('يلا',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 5),
                const Text('نظام النقل الذكي',
                    style: TextStyle(color: Colors.grey, fontSize: 14)),
                const SizedBox(height: 30),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  dropdownColor: const Color(0xFF0F172A),
                  decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                  items: const [
                    DropdownMenuItem(
                        value: 'driver',
                        child: Text('سائق الحافلة',
                            style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(
                        value: 'parent',
                        child: Text('ولي الأمر',
                            style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(
                        value: 'admin',
                        child: Text('الإدارة المركزية',
                            style: TextStyle(color: Colors.white)))
                  ],
                  onChanged: (val) => setState(() {
                    selectedRole = val!;
                    _passwordController.clear();
                    _studentNameController.clear();
                  }),
                ),
                if (selectedRole == 'parent') ...[
                  const SizedBox(height: 15),
                  TextField(
                    controller: _studentNameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      labelText: 'اسم الطالب الثلاثي',
                      labelStyle: const TextStyle(color: Colors.grey),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      labelText: 'كلمة المرور',
                      labelStyle: const TextStyle(color: Colors.grey),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      suffixIcon: IconButton(
                          icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.grey),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword)),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10))),
                        onPressed: _attemptLogin,
                        child: const Text('دخول النظام',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 2. شاشة الكابتن (السائق) - ذكية بالكامل
// ==========================================
class DriverDashboard extends StatefulWidget {
  final String busId; // إضافة متغير لاستقبال رقم الحافلة
  const DriverDashboard({Key? key, required this.busId}) : super(key: key);
  @override
  _DriverDashboardState createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  late IO.Socket socket;
  bool isConnected = false;
  bool isTracking = false;
  bool isMorningTrip = true; // ذهاب (صباحي) أم عودة (مسائي)
  double currentSpeed = 0.0;
  LatLng currentPos = const LatLng(36.2150, 37.1450);
  StreamSubscription<Position>? positionStream;
  final MapController mapController = MapController();
  final String serverUrl = 'https://masarak-aleppo.duckdns.org';
  final LatLng schoolLocation = const LatLng(36.28086, 37.03758);

  @override
  void initState() {
    super.initState();
    _initSocket();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [Permission.location, Permission.locationAlways].request();
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

  // إرسال إشعار عبر السيرفر
  void _sendNotification(String type, String msg, String? studentId) {
    if (isConnected) {
      socket
          .emit('busEvent', {'type': type, 'studentId': studentId, 'msg': msg});
    }
  }

  void _toggleTracking() async {
    if (isTracking) {
      positionStream?.cancel();
      setState(() => isTracking = false);
      // إشعار الوصول للمدرسة أو انتهاء الرحلة
      _sendNotification(
          'trip_ended',
          isMorningTrip
              ? 'وصلت الحافلة إلى المدرسة بسلام.'
              : 'تم إنهاء رحلة العودة بنجاح.',
          null);
    } else {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      setState(() => isTracking = true);
      _sendNotification(
          'trip_started', 'انطلقت الحافلة، يمكنك تتبع المسار الآن.', null);

      // تصفير إشعارات الاقتراب لجميع الطلاب
      for (var s in globalStudents) {
        s['alertSent'] = false;
        s['status'] = 'waiting';
      }

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
        if (isConnected)
          socket.emit('updateLocation',
              {'lat': position.latitude, 'lng': position.longitude});

        // --- رادار الاقتراب ---
        final busStudents =
            globalStudents.where((s) => s['busId'] == '1').toList();
        for (var student in busStudents) {
          if (student['home'] != null &&
              student['status'] == 'waiting' &&
              student['alertSent'] != true) {
            double distance = Geolocator.distanceBetween(
                currentPos.latitude,
                currentPos.longitude,
                student['home'].latitude,
                student['home'].longitude);
            // إذا كانت المسافة أقل من 300 متر، أرسل إشعار اقتراب
            if (distance < 300) {
              student['alertSent'] = true; // لكي لا يرسل الإشعار مئات المرات
              _sendNotification(
                  'approaching',
                  'الحافلة تقترب من موقفك! المسافة أقل من 300 متر.',
                  student['id']);
            }
          }
        }
      });
    }
  }

  @override
  void dispose() {
    positionStream?.cancel();
    socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. جلب الطلاب وترتيبهم حسب رقم الموقف
    List busStudents =
        globalStudents.where((s) => s['busId'] == widget.busId).toList();
    busStudents.sort(
        (a, b) => (a['stopNumber'] ?? 99).compareTo(b['stopNumber'] ?? 99));

    // إذا كانت رحلة عودة (مساءً)، نعكس الترتيب
    if (!isMorningTrip) {
      busStudents = busStudents.reversed.toList();
    }

    // 2. تشكيل المسار والعلامات
    List<LatLng> routePoints = [currentPos];
    if (isMorningTrip) {
      // صباحاً: باص -> طلاب -> مدرسة
      for (var s in busStudents) {
        if (s['home'] != null) routePoints.add(s['home']);
      }
      routePoints.add(schoolLocation);
    } else {
      // مساءً: مدرسة -> طلاب (البداية من المدرسة أو مكان الباص الحالي)
      for (var s in busStudents) {
        if (s['home'] != null) routePoints.add(s['home']);
      }
    }

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
              child: Column(mainAxisSize: MainAxisSize.min, // لحصر المساحة
                  children: [
                    CircleAvatar(
                        radius: 10,
                        backgroundColor: Colors.red,
                        child: Text('${s['stopNumber'] ?? '-'}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10))),
                    const Text('📍', style: TextStyle(fontSize: 15)),
                  ])))
          .toList(),
      Marker(
          point: currentPos,
          width: 50,
          height: 50,
          child: const Text('🚌', style: TextStyle(fontSize: 35))),
    ];

    return Scaffold(
      appBar: AppBar(
          backgroundColor: const Color(0xFF1E293B),
          leading: IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: () => Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()))),
          title: Text(
              'الكابتن ${globalBuses.firstWhere((b) => b['id'] == widget.busId)['driverName']} - حافلة ${globalBuses.firstWhere((b) => b['id'] == widget.busId)['number']}',
              style: const TextStyle(fontSize: 14)),
          actions: [
            // زر تبديل نوع الرحلة
            if (!isTracking)
              TextButton.icon(
                icon: Icon(
                    isMorningTrip ? Icons.wb_sunny : Icons.nightlight_round,
                    color: Colors.orangeAccent),
                label: Text(isMorningTrip ? 'ذهاب' : 'عودة',
                    style: const TextStyle(color: Colors.white)),
                onPressed: () => setState(() => isMorningTrip = !isMorningTrip),
              ),
            Icon(Icons.circle,
                color: isConnected ? Colors.greenAccent : Colors.redAccent,
                size: 14),
            const SizedBox(width: 15)
          ]),
      body: Column(children: [
        Expanded(
            flex: 2,
            child: FlutterMap(
                mapController: mapController,
                options:
                    MapOptions(initialCenter: currentPos, initialZoom: 14.0),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                    subdomains: const ['a', 'b', 'c', 'd'],
                    userAgentPackageName: 'com.example.masarak',
                    maxZoom: 19.0,
                  ),
                  PolylineLayer(polylines: [
                    Polyline(
                        points: routePoints,
                        strokeWidth: 4.0,
                        color: Colors.blueAccent.withOpacity(0.7),
                        isDotted: true)
                  ]),
                  MarkerLayer(markers: mapMarkers),
                ])),
        Expanded(
            flex: 3,
            child: Container(
                padding: const EdgeInsets.all(15),
                decoration: const BoxDecoration(color: Color(0xFF0F172A)),
                child: Column(children: [
                  GestureDetector(
                      onTap: _toggleTracking,
                      child: Container(
                          height: 55,
                          decoration: BoxDecoration(
                              color: isTracking
                                  ? Colors.redAccent
                                  : Colors.blueAccent,
                              borderRadius: BorderRadius.circular(15)),
                          child: Center(
                              child: Text(
                                  isTracking
                                      ? 'إنهـاء الرحلـة'
                                      : 'بدء الرحلة والتتبع',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold))))),
                  const SizedBox(height: 15),
                  Expanded(
                      child: ListView.builder(
                          itemCount: busStudents.length,
                          itemBuilder: (ctx, i) {
                            final st = busStudents[i];
                            return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(10)),
                                child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
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
                                          Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(st['name'],
                                                    style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                                Text(
                                                    st['status'] == 'boarded'
                                                        ? 'صعد للحافلة'
                                                        : st['status'] ==
                                                                'absent'
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
                                        ],
                                      ),
                                      Row(children: [
                                        // زر الحضور
                                        IconButton(
                                            icon: Icon(Icons.check_circle,
                                                color: st['status'] == 'boarded'
                                                    ? Colors.green
                                                    : Colors.grey,
                                                size: 28),
                                            onPressed: () {
                                              setState(() =>
                                                  st['status'] = 'boarded');
                                              _sendNotification(
                                                  'student_boarded',
                                                  isMorningTrip
                                                      ? 'صعد ${st['name']} إلى الحافلة بنجاح.'
                                                      : 'نزل ${st['name']} من الحافلة بسلام.',
                                                  st['id']);
                                            }),
                                        // زر الغياب
                                        IconButton(
                                            icon: Icon(Icons.cancel,
                                                color: st['status'] == 'absent'
                                                    ? Colors.red
                                                    : Colors.grey,
                                                size: 28),
                                            onPressed: () {
                                              setState(() =>
                                                  st['status'] = 'absent');
                                              _sendNotification(
                                                  'student_absent',
                                                  'لم يصعد ${st['name']} للحافلة (تخطى الموقف).',
                                                  st['id']);
                                            })
                                      ])
                                    ]));
                          }))
                ])))
      ]),
    );
  }
}

// ==========================================
// 3. شاشة ولي الأمر - استقبال التنبيهات المباشرة
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
  LatLng busPos = const LatLng(36.2150, 37.1450); // موقع افتراضي للباص
  final MapController mapController = MapController();
  final String serverUrl =
      'https://masarak-aleppo.duckdns.org'; // الآي بي الخاص بك

  @override
  void initState() {
    super.initState();
    _initSocket();
  }

  void _initSocket() {
    socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false
    });

    socket.connect();

    socket.onConnect((_) => setState(() => isConnected = true));
    socket.onDisconnect((_) => setState(() => isConnected = false));

    // 1. استقبال تحديث موقع الباص الحقيقي
    socket.on('locationUpdated', (data) {
      if (mounted) {
        setState(() {
          busPos = LatLng(data['lat'], data['lng']);
          mapController.move(busPos, 15.0); // تحريك الخريطة لتلحق بالباص
        });
      }
    });

    // 2. استقبال الإشعارات الذكية من السيرفر
    socket.on('busNotification', (data) {
      // التحقق مما إذا كان الإشعار يخص هذا الطالب تحديداً (أو إشعار عام للرحلة)
      if (data['studentId'] == null ||
          data['studentId'] == widget.studentData['id']) {
        _showNotification(data['msg'], data['type']);
      }
    });
  }

  // دالة إظهار الإشعار للمستخدم بتصميم عصري
  void _showNotification(String message, String type) {
    if (!mounted) return;

    Color bgColor = Colors.blueAccent;
    IconData icon = Icons.info;

    // تحديد اللون والأيقونة بناءً على نوع الحدث القادم من السائق
    if (type == 'approaching') {
      bgColor = Colors.orange; // اقتراب الباص
      icon = Icons.warning_amber_rounded;
    } else if (type == 'student_boarded') {
      bgColor = Colors.green; // صعود ناجح
      icon = Icons.check_circle;
    } else if (type == 'student_absent') {
      bgColor = Colors.redAccent; // غياب الطالب
      icon = Icons.cancel;
    } else if (type == 'trip_started' || type == 'trip_ended') {
      bgColor = Colors.purpleAccent; // أحداث الرحلة
      icon = Icons.directions_bus;
    }

    final snackBar = SnackBar(
      content: Row(
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(width: 15),
          Expanded(
              child: Text(message,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14))),
        ],
      ),
      backgroundColor: bgColor,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(bottom: 20, left: 15, right: 15),
      elevation: 10,
      duration: const Duration(seconds: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  @override
  void dispose() {
    socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // جلب بيانات الباص المخصص للطالب
    final studentBus = globalBuses.firstWhere(
      (b) => b['id'] == widget.studentData['busId'],
      orElse: () => {'number': '-', 'driverName': 'غير محدد', 'phone': ''},
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        leading: IconButton(
          icon: const Icon(Icons.logout, color: Colors.white),
          onPressed: () => Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => const LoginScreen())),
        ),
        title: Text('ولي أمر: ${widget.studentData['name'].split(' ')[0]}',
            style: const TextStyle(fontSize: 14)),
        actions: [
          // مؤشر الاتصال بالسيرفر
          Icon(Icons.circle,
              color: isConnected ? Colors.greenAccent : Colors.redAccent,
              size: 14),
          const SizedBox(width: 15)
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(initialCenter: busPos, initialZoom: 14.0),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.example.masarak',
                  maxZoom: 19.0,
                ),
                MarkerLayer(markers: [
                  // 1. دبوس موقع منزل الطالب (إن تم تحديده)
                  if (widget.studentData['home'] != null)
                    Marker(
                      point: widget.studentData['home'],
                      width: 40,
                      height: 40,
                      child: const Text('📍', style: TextStyle(fontSize: 30)),
                    ),
                  // 2. أيقونة الحافلة المتحركة
                  Marker(
                    point: busPos,
                    width: 50,
                    height: 50,
                    child: const Text('🚌', style: TextStyle(fontSize: 35)),
                  ),
                ]),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(20),
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('متابعة مسار الحافلة:',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  Card(
                    color: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                    child: ListTile(
                      leading: const CircleAvatar(
                          backgroundColor: Colors.blueAccent,
                          child:
                              Icon(Icons.directions_bus, color: Colors.white)),
                      title: Text('حافلة رقم ${studentBus['number']}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                      subtitle: Text('السائق: ${studentBus['driverName']}',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.call,
                                color: Colors.greenAccent),
                            onPressed: () {
                              // يمكننا ربطها لاحقاً بـ url_launcher للاتصال الهاتفي المباشر بالسائق
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildNotificationTile(String title, String desc, String time,
    {bool isAlert = false}) {
  return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: isAlert
              ? Colors.orangeAccent.withOpacity(0.1)
              : const Color(0xFF1E293B),
          border: Border.all(
              color: isAlert
                  ? Colors.orangeAccent.withOpacity(0.5)
                  : Colors.transparent),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(title,
              style: TextStyle(
                  color: isAlert ? Colors.orangeAccent : Colors.white,
                  fontWeight: FontWeight.bold)),
          Text(time, style: const TextStyle(color: Colors.grey, fontSize: 10))
        ]),
        const SizedBox(height: 4),
        Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 12))
      ]));
}

// ==========================================
// 4. شاشة الإدارة المركزية (مع تحديث البيانات مركزياً)
// ==========================================
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({Key? key}) : super(key: key);
  @override
  _AdminDashboardState createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _currentIndex = 0;
  final MapController mapController = MapController();

  // ==========================================
  // دوال الإضافة (POST)
  // ==========================================
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
                        labelText: 'اسم السائق',
                        labelStyle: TextStyle(color: Colors.grey)),
                    onChanged: (val) => dName = val),
                TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                        labelText: 'هاتف السائق',
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
    String stopNum = '1';
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
                          bool stopNumberExists = globalStudents.any((s) =>
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

  // ==========================================
  // دوال التعديل (PUT)
  // ==========================================
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
                        labelText: 'اسم السائق',
                        labelStyle: TextStyle(color: Colors.blueAccent)),
                    onChanged: (val) => dName = val),
                TextFormField(
                    initialValue: dPhone,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                        labelText: 'هاتف السائق',
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
                      const SizedBox(width: 10),
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
                      bool stopNumberExists = globalStudents.any((s) =>
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

  // ==========================================
  // واجهات العرض (Views)
  // ==========================================
  Widget _buildMapAndTrackingView() {
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
                      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.example.masarak',
                  maxZoom: 19.0,
                ),
                MarkerLayer(markers: [
                  Marker(
                      point: schoolLocation,
                      width: 40,
                      height: 40,
                      alignment: Alignment.topCenter,
                      child: const Text('🏫', style: TextStyle(fontSize: 25))),
                  ...globalBuses
                      .where((b) => b['location'] != null)
                      .map((bus) => Marker(
                          point: bus['location'],
                          width: 40,
                          height: 40,
                          alignment: Alignment.topCenter,
                          child:
                              const Text('🚌', style: TextStyle(fontSize: 25))))
                      .toList()
                ])
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
                    const Text('متابعة مسارات الحافلات:',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    const SizedBox(height: 10),
                    Expanded(
                        child: ListView.builder(
                            itemCount: globalBuses.length,
                            itemBuilder: (context, index) {
                              final bus = globalBuses[index];
                              return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B),
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
                                                  'السائق: ${bus['driverName']}',
                                                  style: const TextStyle(
                                                      color: Colors.grey,
                                                      fontSize: 12))
                                            ]),
                                        ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor: bus['isActive']
                                                    ? Colors.blueAccent
                                                        .withOpacity(0.2)
                                                    : Colors.grey
                                                        .withOpacity(0.2),
                                                elevation: 0),
                                            onPressed: () {
                                              if (bus['location'] != null)
                                                mapController.move(
                                                    bus['location'], 16.0);
                                            },
                                            child: Text('متابعة 📍',
                                                style: TextStyle(
                                                    color: bus['isActive']
                                                        ? Colors.blueAccent
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
            busStudents.sort((a, b) => (a['stopNumber'] ?? 99)
                .compareTo(b['stopNumber'] ?? 99)); // ترتيب حسب الموقف
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
                            'حافلة ${bus['number']} - السائق: ${bus['driverName']}',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
            backgroundColor: const Color(0xFF1E293B),
            leading: IconButton(
                icon: const Icon(Icons.logout, color: Colors.white),
                onPressed: () => Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()))),
            title: const Text('لوحة الإدارة المركزية',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        body: IndexedStack(index: _currentIndex, children: [
          _buildMapAndTrackingView(),
          _buildStudentsDatabaseView(),
          _buildDriversDatabaseView()
        ]),
        bottomNavigationBar: BottomNavigationBar(
            backgroundColor: const Color(0xFF1E293B),
            selectedItemColor: Colors.blueAccent,
            unselectedItemColor: Colors.grey,
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.map), label: 'الخريطة'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.school), label: 'الطلاب'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.drive_eta), label: 'السائقين')
            ]));
  }
}

// ==========================================
// 5. شاشة التقاط الموقع من الخريطة (نظام أوبر الاحترافي)
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
                  // قراءة إحداثيات مركز الخريطة المباشر بدقة 100%
                  Navigator.pop(context, _mapController.camera.center);
                })
          ]),
      body: Stack(
        children: [
          // 1. الخريطة القابلة للسحب
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: currentCenter,
              initialZoom: 16.0,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.masarak',
                maxZoom: 19.0,
              ),
            ],
          ),

          // 2. الدبوس الثابت في منتصف الشاشة تماماً
          const Align(
            alignment: Alignment.center,
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: 35.0), // لرفع الدبوس قليلاً ليكون رأسه في المركز
              child: Icon(Icons.location_on, size: 45, color: Colors.redAccent),
            ),
          ),

          // 3. نقطة سوداء صغيرة للتصويب الدقيق
          const Align(
            alignment: Alignment.center,
            child: CircleAvatar(radius: 3, backgroundColor: Colors.black),
          ),

          // 4. رسالة توضيحية للمستخدم
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
