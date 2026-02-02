import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

// 갤러리 목록 및 썸네일 제공용 서버
class GalleryServer {
  HttpServer? _server;
  final int port;

  GalleryServer({this.port = 5000});

  Future<void> start() async {
    final handler = Pipeline()
        .addMiddleware(corsHeaders())
        .addMiddleware(logRequests())
        .addHandler(_router);
    await _refreshAssetCache();
    // shelf의 serve를 사용하여 handler가 실제로 사용되도록 수정
    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    debugPrint('GalleryServer started on port $port');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  List<Map<String, dynamic>>? _assetCache; // 전체 asset 캐시
  DateTime? _cacheTime;
  static const _cacheDuration = Duration(minutes: 10); // 10분마다 갱신

  Future<void> _refreshAssetCache() async {
    final perms = await PhotoManager.requestPermissionExtend();
    if (!perms.isAuth) {
      _assetCache = null;
      return;
    }
    final List<AssetPathEntity> albums =
        await PhotoManager.getAssetPathList(type: RequestType.common);
    List<AssetEntity> allAssets = [];
    for (final album in albums) {
      final int assetCount = await album.assetCountAsync;
      final assets = await album.getAssetListPaged(page: 0, size: assetCount);
      allAssets.addAll(assets);
    }
    // id 기준 중복 제거
    final uniqueAssets = <String, AssetEntity>{};
    for (final asset in allAssets) {
      uniqueAssets[asset.id] = asset;
    }
    final dedupedAssets = uniqueAssets.values.toList();
    dedupedAssets.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
    // 캐시에 필요한 정보만 저장 (썸네일 제외)
    _assetCache = dedupedAssets
        .map((a) => {
              'id': a.id,
              'title': a.title,
              'type': a.type.toString(),
              'createDate': a.createDateTime.toIso8601String(),
              'width': a.width,
              'height': a.height,
            })
        .toList();
    _cacheTime = DateTime.now();
  }

  // 라우터: 갤러리 목록, 썸네일, 파일 제공
  Future<Response> _router(Request request) async {
    final segments = request.url.pathSegments;
    if (segments.isEmpty) return Response.notFound('Not found');

    if (segments[0] == 'list') {
      debugPrint('[list] 요청 진입');
      // 캐시 만료 또는 없음 시 갱신
      if (_assetCache == null ||
          _cacheTime == null ||
          DateTime.now().difference(_cacheTime!) > _cacheDuration) {
        debugPrint('[list] 캐시 없음/만료, 갱신 시도');
        await _refreshAssetCache();
        debugPrint('[list] 캐시 갱신 완료');
      }
      if (_assetCache == null) {
        debugPrint('[list] 권한 없음 또는 캐시 생성 실패');
        return Response.forbidden('갤러리 접근 권한 필요');
      }
      // 쿼리 파라미터 파싱
      final page =
          int.tryParse(request.url.queryParameters['page'] ?? '0') ?? 0;
      final size =
          int.tryParse(request.url.queryParameters['size'] ?? '30') ?? 30;
      final start = page * size;
      final end = (start + size).clamp(0, _assetCache!.length);
      final pageAssets = (start < _assetCache!.length)
          ? _assetCache!.sublist(start, end)
          : <Map<String, dynamic>>[];
      debugPrint(
          '[list] 응답 직전: page=$page, size=$size, 반환=${pageAssets.length}개');
      // 썸네일은 포함하지 않고 메타데이터만 반환
      return Response.ok(jsonEncode(pageAssets),
          headers: {'Content-Type': 'application/json'});
    }

    if (segments[0] == 'thumbnail' && segments.length > 1) {
      // 썸네일 반환
      final id = segments[1];
      final asset = await AssetEntity.fromId(id);
      if (asset == null) return Response.notFound('No thumbnail');
      final thumb = await asset.thumbnailDataWithSize(ThumbnailSize(128, 128));
      if (thumb == null) return Response.notFound('No thumbnail');
      return Response.ok(
        thumb,
        headers: {
          'Content-Type': 'image/jpeg',
          'Cache-Control': 'public, max-age=31536000, immutable'
        },
      );
    }

    if (segments[0] == 'file' && segments.length > 1) {
      // 원본 파일 반환
      final id = segments[1];
      final asset = await AssetEntity.fromId(id);
      if (asset == null) return Response.notFound('No file');
      final file = await asset.file;
      if (file == null) return Response.notFound('No file');
      // 확장자 추출
      final path = file.path;
      String ext = 'bin';
      final dotIdx = path.lastIndexOf('.');
      if (dotIdx != -1 && dotIdx < path.length - 1) {
        ext = path.substring(dotIdx + 1);
      }
      // 클라이언트에서 전달한 filename 파라미터 사용
      final customTitle = request.url.queryParameters['filename'];
      String filename;
      if (customTitle != null && customTitle.isNotEmpty) {
        filename = '$customTitle.$ext';
      } else {
        filename = asset.title ?? '${asset.id}.$ext';
      }
      return Response.ok(await file.readAsBytes(), headers: {
        'Content-Type': 'application/octet-stream',
        'Content-Disposition':
            'attachment; filename*=UTF-8\'\'${Uri.encodeComponent(filename)}'
      });
    }

    return Response.notFound('Not found');
  }
}
