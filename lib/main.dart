import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const MasarakApp());
}

// ==========================================
// قاعدة البيانات المركزية المشتركة (لتحديث البيانات في كل التطبيق)
// ==========================================
List<Map<String, dynamic>> globalBuses = [
  {
    'id': '1',
    'number': '1',
    'routeName': 'مسار السريان',
    'driverName': 'أبو محمود',
    'driverPhone': '0933333333',
    'isActive': true,
    'location': const LatLng(36.2150, 37.1450)
  },
  {
    'id': '2',
    'number': '2',
    'routeName': 'مسار الشهباء',
    'driverName': 'خالد العلي',
    'driverPhone': '0944444444',
    'isActive': true,
    'location': const LatLng(36.2280, 37.1250)
  },
];

List<Map<String, dynamic>> globalStudents = [
  {
    'id': '1',
    'name': 'سارة محمد',
    'seat': 'A2',
    'busId': '1',
    'password': '1234',
    'age': '10',
    'parentPhone': '0911111111',
    'address': 'حي السريان - الشارع العام',
    'home': const LatLng(36.2245, 37.1365)
  },
  {
    'id': '2',
    'name': 'أحمد مصطفى',
    'seat': 'A1',
    'busId': '1',
    'password': '1234',
    'age': '12',
    'parentPhone': '0922222222',
    'address': 'حي السريان - قرب الجامع',
    'home': const LatLng(36.2165, 37.1465)
  },
];

// رقم الإدارة الموحد لجميع حسابات الأهل
String globalAdminPhone = '0900000000';

class MasarakApp extends StatelessWidget {
  const MasarakApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'المدرسة الوطنية الذكية',
      theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0F172A),
          primaryColor: const Color(0xFF2563EB)),
      home: const LoginScreen(),
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
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const DriverDashboard()));
    } else if (selectedRole == 'admin') {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const AdminDashboard()));
    } else if (selectedRole == 'parent') {
      String enteredName = _studentNameController.text.trim();
      String enteredPass = _passwordController.text.trim();

      // البحث عن الطالب في القاعدة المركزية
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
        // جلب بيانات الحافلة والسائق الخاصة بهذا الطالب حصرياً
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
                const Text('🏫', style: TextStyle(fontSize: 50)),
                const SizedBox(height: 10),
                const Text('المدرسة الوطنية الذكية',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 5),
                const Text('نظام النقل الآمن - مسارك',
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
                  // حقل نصي لإدخال اسم الطالب مباشرة لتجنب قوائم الـ 200 طالب
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
// 2. شاشة الكابتن (السائق)
// ==========================================
class DriverDashboard extends StatefulWidget {
  const DriverDashboard({Key? key}) : super(key: key);
  @override
  _DriverDashboardState createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  late IO.Socket socket;
  bool isConnected = false;
  bool isTracking = false;
  double currentSpeed = 0.0;
  LatLng currentPos = const LatLng(36.2150, 37.1450);
  StreamSubscription<Position>? positionStream;
  final MapController mapController = MapController();
  final String serverUrl = 'http://169.58.150.76:3000';

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

  void _toggleTracking() async {
    if (isTracking) {
      positionStream?.cancel();
      setState(() {
        isTracking = false;
        currentSpeed = 0.0;
      });
      socket.emit('busEvent', {'type': 'trip_ended', 'msg': 'تم إنهاء الرحلة'});
    } else {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      setState(() => isTracking = true);
      socket
          .emit('busEvent', {'type': 'trip_started', 'msg': 'انطلقت الحافلة'});
      positionStream = Geolocator.getPositionStream(
              locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.bestForNavigation,
                  distanceFilter: 5))
          .listen((Position position) {
        setState(() {
          currentSpeed = (position.speed * 3.6);
          currentPos = LatLng(position.latitude, position.longitude);
          mapController.move(currentPos, 16.0);
        });
        if (isConnected)
          socket.emit('updateLocation', {
            'lat': position.latitude,
            'lng': position.longitude,
            'speed': currentSpeed.toStringAsFixed(1)
          });
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
    return Scaffold(
      appBar: AppBar(
          backgroundColor: const Color(0xFF1E293B),
          leading: IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: () => Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()))),
          title: const Text('الكابتن أبو محمود - حافلة 1',
              style: TextStyle(fontSize: 14)),
          actions: [
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
                    MapOptions(initialCenter: currentPos, initialZoom: 15.0),
                children: [
                  TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.masarak'),
                  MarkerLayer(markers: [
                    Marker(
                        point: currentPos,
                        width: 40,
                        height: 40,
                        child: const Text('🚌', style: TextStyle(fontSize: 30)))
                  ])
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
                                      ? 'إيقاف الرحلة'
                                      : 'بدء الرحلة والتتبع',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold))))),
                  const SizedBox(height: 15),
                  const Align(
                      alignment: Alignment.centerRight,
                      child: Text('سجل الحضور والصعود:',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold))),
                  const SizedBox(height: 10),
                  Expanded(
                      child: ListView.builder(
                          itemCount: globalStudents.length,
                          itemBuilder: (ctx, i) {
                            final st = globalStudents[i];
                            return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 15, vertical: 10),
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
                                            Text(st['name'],
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            Text('المقعد: ${st['seat']}',
                                                style: const TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 12))
                                          ]),
                                      Row(children: [
                                        IconButton(
                                            icon: const Icon(Icons.check_circle,
                                                color: Colors.green),
                                            onPressed: () {}),
                                        IconButton(
                                            icon: const Icon(Icons.cancel,
                                                color: Colors.orange),
                                            onPressed: () {})
                                      ])
                                    ]));
                          }))
                ])))
      ]),
    );
  }
}

// ==========================================
// 3. شاشة ولي الأمر (مع زر اتصال الإدارة ورقم السائق النصي)
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
  LatLng busPos = const LatLng(36.2150, 37.1450);
  final MapController mapController = MapController();
  final String serverUrl = 'http://169.58.150.76:3000';
  @override
  void initState() {
    super.initState();
    socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true
    });
    socket.on(
        'locationUpdated',
        (data) => setState(() {
              busPos = LatLng(data['lat'], data['lng']);
              mapController.move(busPos, 15.0);
            }));
  }

  @override
  void dispose() {
    socket.dispose();
    super.dispose();
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تعذر إجراء الاتصال'),
            backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    // جلب أحدث البيانات مباشرة من القائمة المركزية لضمان مطابقتها لتعديلات الإدارة
    final currentStudent = globalStudents.firstWhere(
        (s) => s['id'] == widget.studentData['id'],
        orElse: () => widget.studentData);
    final currentBus =
        globalBuses.firstWhere((b) => b['id'] == currentStudent['busId'],
            orElse: () => {
                  'number': widget.studentData['busNumber'],
                  'driverName': widget.studentData['driverName'],
                  'driverPhone': widget.studentData['driverPhone'],
                  'routeName': widget.studentData['routeName']
                });

    final studentName = currentStudent['name'];
    final busNumber = currentBus['number'];
    final driverName = currentBus['driverName'];
    final routeName = currentBus['routeName'];
    final driverPhone = currentBus['driverPhone'];
    final homeLocation = currentStudent['home'];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        leading: IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const LoginScreen()))),
        title: Text('متابعة: $studentName - حافلة $busNumber',
            style: const TextStyle(fontSize: 14)),
        actions: [
          // زر الاتصال الموحد بالإدارة في الشريط العلوي لولي الأمر
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.greenAccent),
            icon: const Icon(Icons.support_agent, size: 18),
            label: const Text('اتصال بالإدارة',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            onPressed: () => _makePhoneCall(globalAdminPhone),
          )
        ],
      ),
      body: Column(children: [
        Expanded(
            flex: 2,
            child: FlutterMap(
                mapController: mapController,
                options:
                    MapOptions(initialCenter: homeLocation, initialZoom: 15.0),
                children: [
                  TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.masarak'),
                  MarkerLayer(markers: [
                    Marker(
                        point: homeLocation,
                        width: 40,
                        height: 40,
                        child:
                            const Text('🏠', style: TextStyle(fontSize: 25))),
                    Marker(
                        point: busPos,
                        width: 40,
                        height: 40,
                        child: const Text('🚌', style: TextStyle(fontSize: 30)))
                  ])
                ])),
        Expanded(
            flex: 3,
            child: Container(
                padding: const EdgeInsets.all(20),
                width: double.infinity,
                decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                    borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20))),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(15)),
                          child: Column(children: [
                            Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('الوقت المتوقع',
                                      style: TextStyle(
                                          color: Colors.grey, fontSize: 12)),
                                  Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                          color: Colors.greenAccent
                                              .withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(20)),
                                      child: const Text('في الطريق 🚍',
                                          style: TextStyle(
                                              color: Colors.greenAccent,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12)))
                                ]),
                            const SizedBox(height: 5),
                            const Align(
                                alignment: Alignment.centerRight,
                                child: Text('08:24 ص',
                                    style: TextStyle(
                                        color: Colors.blueAccent,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold))),
                            const Divider(color: Colors.grey, height: 20),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('السائق: $driverName',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold)),
                                    // عرض رقم السائق نصياً فقط للأهل
                                    Text('هاتف السائق: $driverPhone',
                                        style: const TextStyle(
                                            color: Colors.grey, fontSize: 12)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text('المسار: $routeName',
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 12)),
                              ],
                            )
                          ])),
                      const SizedBox(height: 15),
                      const Text('🔔 سجل الإشعارات:',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      const SizedBox(height: 10),
                      Expanded(
                          child: ListView(children: [
                        _buildNotificationTile('انطلقت الحافلة',
                            'غادرت الحافلة النقطة الأولى.', '07:30 ص'),
                        _buildNotificationTile('اقتراب الحافلة',
                            'الحافلة قريبة من $studentName.', '07:45 ص',
                            isAlert: true)
                      ]))
                    ])))
      ]),
    );
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
                    onPressed: () {
                      if (bNum.isNotEmpty) {
                        setState(() => globalBuses.add({
                              'id': DateTime.now()
                                  .millisecondsSinceEpoch
                                  .toString(),
                              'number': bNum,
                              'routeName': rName,
                              'driverName': dName,
                              'driverPhone': dPhone,
                              'isActive': false,
                              'location': const LatLng(36.24, 37.11)
                            }));
                        Navigator.pop(ctx);
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
    String age = '';
    String phone = '';
    String addr = '';
    String? sBus;
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
                  TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                          labelText: 'العمر',
                          labelStyle: TextStyle(color: Colors.grey)),
                      keyboardType: TextInputType.number,
                      onChanged: (val) => age = val),
                  TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                          labelText: 'العنوان',
                          labelStyle: TextStyle(color: Colors.grey)),
                      onChanged: (val) => addr = val),
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
                          labelText: 'المقعد',
                          labelStyle: TextStyle(color: Colors.grey)),
                      onChanged: (val) => seat = val),
                  TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                          labelText: 'كلمة المرور',
                          labelStyle: TextStyle(color: Colors.grey)),
                      onChanged: (val) => pass = val),
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
                      onPressed: () {
                        if (sName.isNotEmpty && sBus != null) {
                          setState(() => globalStudents.add({
                                'id': DateTime.now()
                                    .millisecondsSinceEpoch
                                    .toString(),
                                'name': sName,
                                'seat': seat,
                                'busId': sBus,
                                'password': pass,
                                'age': age,
                                'parentPhone': phone,
                                'address': addr,
                                'home': const LatLng(36.22, 37.13)
                              }));
                          Navigator.pop(ctx);
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
                    onChanged: (val) => dPhone = val),
              ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('إلغاء',
                        style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () {
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
    String age = st['age'];
    String phone = st['parentPhone'];
    String addr = st['address'];
    String? sBus = st['busId'];
    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (context, setStateDialog) {
              return AlertDialog(
                backgroundColor: const Color(0xFF1E293B),
                title: const Text('تعديل بيانات الطالب',
                    style: TextStyle(color: Colors.white)),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextFormField(
                      initialValue: sName,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                          labelText: 'اسم الطالب',
                          labelStyle: TextStyle(color: Colors.blueAccent)),
                      onChanged: (val) => sName = val),
                  TextFormField(
                      initialValue: age,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                          labelText: 'العمر',
                          labelStyle: TextStyle(color: Colors.blueAccent)),
                      keyboardType: TextInputType.number,
                      onChanged: (val) => age = val),
                  TextFormField(
                      initialValue: addr,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                          labelText: 'العنوان',
                          labelStyle: TextStyle(color: Colors.blueAccent)),
                      onChanged: (val) => addr = val),
                  TextFormField(
                      initialValue: phone,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                          labelText: 'هاتف الولي',
                          labelStyle: TextStyle(color: Colors.blueAccent)),
                      keyboardType: TextInputType.phone,
                      onChanged: (val) => phone = val),
                  TextFormField(
                      initialValue: seat,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                          labelText: 'المقعد',
                          labelStyle: TextStyle(color: Colors.blueAccent)),
                      onChanged: (val) => seat = val),
                  TextFormField(
                      initialValue: pass,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                          labelText: 'كلمة المرور',
                          labelStyle: TextStyle(color: Colors.blueAccent)),
                      onChanged: (val) => pass = val),
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
                      onChanged: (val) => setStateDialog(() => sBus = val)),
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('إلغاء',
                          style: TextStyle(color: Colors.grey))),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green),
                      onPressed: () {
                        setState(() {
                          globalStudents[index] = {
                            ...st,
                            'name': sName,
                            'seat': seat,
                            'busId': sBus,
                            'password': pass,
                            'age': age,
                            'parentPhone': phone,
                            'address': addr
                          };
                        });
                        Navigator.pop(ctx);
                      },
                      child: const Text('تحديث',
                          style: TextStyle(color: Colors.white))),
                ],
              );
            }));
  }

  Widget _buildMapAndTrackingView() {
    return Column(children: [
      Expanded(
          flex: 2,
          child: FlutterMap(
              mapController: mapController,
              options: const MapOptions(
                  initialCenter: LatLng(36.2150, 37.1450), initialZoom: 13.0),
              children: [
                TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.masarak'),
                MarkerLayer(markers: [
                  Marker(
                      point: const LatLng(36.2936, 37.0444),
                      width: 40,
                      height: 40,
                      child: const Text('🏫', style: TextStyle(fontSize: 25))),
                  ...globalBuses
                      .map((bus) => Marker(
                          point: bus['location'],
                          width: 40,
                          height: 40,
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
                                            onPressed: () => mapController.move(
                                                bus['location'], 16.0),
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
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.all(15),
      child: ListView.builder(
        itemCount: globalStudents.length,
        itemBuilder: (context, index) {
          final student = globalStudents[index];
          final studentBus = globalBuses.firstWhere(
              (b) => b['id'] == student['busId'],
              orElse: () => {'number': '؟'});
          return Card(
            color: const Color(0xFF1E293B),
            margin: const EdgeInsets.only(bottom: 15),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('👨‍🎓 ${student['name']}',
                            style: const TextStyle(
                                color: Colors.blueAccent,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                                color: Colors.blueAccent.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10)),
                            child: Text('حافلة: ${studentBus['number']}',
                                style: const TextStyle(
                                    color: Colors.blueAccent,
                                    fontWeight: FontWeight.bold))),
                      ]),
                  const Divider(color: Colors.grey),
                  Text('العمر: ${student['age']} | المقعد: ${student['seat']}',
                      style: const TextStyle(color: Colors.white)),
                  const SizedBox(height: 5),
                  Text('العنوان: ${student['address']}',
                      style: const TextStyle(color: Colors.white)),
                  const SizedBox(height: 5),
                  Text('هاتف ولي الأمر: ${student['parentPhone']}',
                      style: const TextStyle(color: Colors.white)),
                  const SizedBox(height: 5),
                  Text('كلمة المرور: ${student['password']}',
                      style: const TextStyle(color: Colors.greenAccent)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () =>
                              setState(() => _showEditStudentDialog(index))),
                      IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () =>
                              setState(() => globalStudents.removeAt(index))),
                    ],
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
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
                    Text('حافلة: ${bus['number']} (${bus['routeName']})',
                        style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 5),
                    Text('الهاتف: ${bus['driverPhone']}',
                        style: const TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold)),
                  ]),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () =>
                          setState(() => _showEditBusDialog(index))),
                  IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => setState(() {
                            for (var s in globalStudents
                                .where((s) => s['busId'] == bus['id'])) {
                              s['busId'] = '';
                            }
                            globalBuses.removeAt(index);
                          })),
                ],
              ),
            ),
          );
        },
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
            BottomNavigationBarItem(icon: Icon(Icons.school), label: 'الطلاب'),
            BottomNavigationBarItem(
                icon: Icon(Icons.drive_eta), label: 'السائقين')
          ]),
    );
  }
}
