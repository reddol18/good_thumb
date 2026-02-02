import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'gallery_server/gallery_server.dart';

Future<String> getLocalIp() async {
  for (var interface in await NetworkInterface.list()) {
    for (var addr in interface.addresses) {
      if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
        return addr.address;
      }
    }
  }
  return '알 수 없음';
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExportHelperApp());
}

class ExportHelperApp extends StatelessWidget {
  const ExportHelperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Export Helper',
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GalleryServer? _server;
  bool _running = false;
  String _status = '';
  String _localIp = '';
  bool _hasGalleryPermission = false;
  bool _checkedPermission = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    getLocalIp().then((ip) => setState(() {
          _localIp = ip;
        }));
  }

  Future<void> _checkPermissions() async {
    // 인터넷 및 네트워크 상태 권한 요청 (Android)
    // INTERNET and ACCESS_NETWORK_STATE permissions are handled in AndroidManifest.xml, not via permission_handler.
    if (Platform.isAndroid) {
      // No runtime request needed for INTERNET or ACCESS_NETWORK_STATE.
    }
    await _checkGalleryPermission();
  }

  Future<void> _checkGalleryPermission() async {
    final perms = await PhotoManager.requestPermissionExtend();
    setState(() {
      _hasGalleryPermission = perms.isAuth;
      _checkedPermission = true;
    });
  }

  Future<void> _requestGalleryPermission() async {
    final perms = await PhotoManager.requestPermissionExtend();
    setState(() {
      _hasGalleryPermission = perms.isAuth;
      _checkedPermission = true;
    });
    if (!perms.isAuth) {
      // 권한 거부 시 안내 메시지 등 추가 가능
      debugPrint('갤러리 접근 권한이 필요합니다.');
    }
  }

  void _startServer() async {
    setState(() {
      _status = '서버 시작 중...';
    });
    _server = GalleryServer();
    await _server!.start();
    setState(() {
      _running = true;
      _status = '서버 실행 중 (포트: 5000)';
    });
  }

  void _stopServer() async {
    setState(() {
      _status = '서버 중지 중...';
    });
    await _server?.stop();
    setState(() {
      _running = false;
      _status = '서버 중지됨';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export Helper')),
      body: Center(
        child: !_checkedPermission
            ? const CircularProgressIndicator()
            : !_hasGalleryPermission
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '갤러리 접근 권한이 필요합니다.',
                        style: TextStyle(fontSize: 16, color: Colors.red),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _requestGalleryPermission,
                        child: const Text('권한 요청'),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: _running ? _stopServer : _startServer,
                        child: Text(_running ? '갤러리 서버 중지' : '갤러리 서버 시작'),
                      ),
                      const SizedBox(height: 16),
                      Text(_status, style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 16),
                      Text('내부 IP: $_localIp',
                          style: const TextStyle(
                              fontSize: 16, color: Colors.blue)),
                    ],
                  ),
      ),
    );
  }
}
