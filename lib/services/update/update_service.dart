import 'dart:convert';
import 'dart:io';

import 'package:arbeitszeit/data/models/update_manifest.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateCheckResult {
  const UpdateCheckResult({
	required this.message,
	required this.availableUpdate,
	required this.source,
  });

  final String message;
  final UpdateManifest? availableUpdate;
  final String? source;
}

class UpdateInstallResult {
  const UpdateInstallResult({required this.message});

  final String message;
}

class UpdateService {
  UpdateService({
	http.Client? httpClient,
	MethodChannel? installChannel,
  }) : _httpClient = httpClient,
	   _installChannel =
		   installChannel ?? const MethodChannel('arbeitszeit/update_install');

  static const String githubOwner = 'FightofDestinyHD';
  static const String githubRepo = 'arbeitszeit';
  static const String githubLatestReleaseUrl =
	  'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';
  static const String updateManifestUrl =
	  'https://github.com/$githubOwner/$githubRepo/releases/latest/download/update.json';

  final http.Client? _httpClient;
  final MethodChannel _installChannel;

  http.Client get _client => _httpClient ?? http.Client();

  Future<UpdateCheckResult> checkForUpdate() async {
	if (kIsWeb || !Platform.isAndroid) {
	  return const UpdateCheckResult(
		message: 'In-App-Update ist nur auf Android verfuegbar.',
		availableUpdate: null,
		source: null,
	  );
	}

	final packageInfo = await PackageInfo.fromPlatform();
	final currentVersion = packageInfo.version;
	final currentBuildNumber = int.tryParse(packageInfo.buildNumber.trim()) ?? 0;
	final manifestResult = await fetchUpdateManifest();
	final manifest = manifestResult.manifest;

	final hasUpdate = manifest.buildNumber > 0 && currentBuildNumber > 0
		? manifest.buildNumber > currentBuildNumber
		: compareVersions(manifest.version, currentVersion) > 0;

	return UpdateCheckResult(
	  message: hasUpdate
		  ? 'Update ${manifest.version} verfuegbar (Build ${manifest.buildNumber}).'
		  : 'App ist aktuell (Version $currentVersion, Build $currentBuildNumber).',
	  availableUpdate: hasUpdate ? manifest : null,
	  source: manifestResult.source,
	);
  }

  Future<({UpdateManifest manifest, String source})> fetchUpdateManifest() async {
	final client = _client;
	final releaseResponse = await client.get(
	  Uri.parse(githubLatestReleaseUrl),
	  headers: const {
		'Accept': 'application/vnd.github+json',
		'User-Agent': 'arbeitszeit-app',
		'X-GitHub-Api-Version': '2022-11-28',
	  },
	);

	if (releaseResponse.statusCode == 200) {
	  final releaseMap = Map<String, dynamic>.from(
		jsonDecode(releaseResponse.body) as Map,
	  );
	  return (manifest: parseGithubRelease(releaseMap), source: 'GitHub');
	}

	final fallbackResponse = await client.get(Uri.parse(updateManifestUrl));
	if (fallbackResponse.statusCode != 200) {
	  throw Exception(
		'GitHub Release API nicht erreichbar ('
		'${releaseResponse.statusCode}) und Fallback fehlgeschlagen ('
		'${fallbackResponse.statusCode}).',
	  );
	}

	final fallbackMap = Map<String, dynamic>.from(
	  jsonDecode(fallbackResponse.body) as Map,
	);
	final manifest = UpdateManifest.fromJson(fallbackMap);
	if (manifest.version.isEmpty || manifest.apkUrl.isEmpty) {
	  throw Exception('Fallback update.json ist unvollstaendig.');
	}
	return (manifest: manifest, source: 'Fallback');
  }

  UpdateManifest parseGithubRelease(Map<String, dynamic> json) {
	final tagName = (json['tag_name'] as String? ?? '').trim();
	final releaseName = (json['name'] as String? ?? '').trim();
	final releaseBody = (json['body'] as String? ?? '').trim();
	final assets = (json['assets'] as List<dynamic>? ?? [])
		.map((item) => Map<String, dynamic>.from(item as Map))
		.toList();

	String apkUrl = '';
	for (final asset in assets) {
	  final fileName = (asset['name'] as String? ?? '').toLowerCase();
	  final browserUrl = (asset['browser_download_url'] as String? ?? '').trim();
	  if (browserUrl.isEmpty) {
		continue;
	  }
	  if (fileName.endsWith('.apk')) {
		apkUrl = browserUrl;
		break;
	  }
	}

	if (apkUrl.isEmpty) {
	  throw Exception('Kein APK-Asset im letzten GitHub Release gefunden.');
	}

	final version = tagName.isNotEmpty ? tagName : releaseName;
	if (version.isEmpty) {
	  throw Exception('Release-Version in GitHub ist leer.');
	}

	return UpdateManifest(
	  version: version,
	  apkUrl: apkUrl,
	  notes: releaseBody,
	  buildNumber: buildNumberFromVersion(version),
	);
  }

  Future<UpdateInstallResult> installAvailableUpdate(
	UpdateManifest manifest, {
	void Function(String message)? onProgress,
  }) async {
	if (kIsWeb || !Platform.isAndroid) {
	  return const UpdateInstallResult(
		message: 'In-App-Update ist nur auf Android verfuegbar.',
	  );
	}

	final uri = Uri.tryParse(manifest.apkUrl);
	if (uri == null) {
	  throw Exception('APK-URL ist ungültig.');
	}

	onProgress?.call('Update wird heruntergeladen...');
	final client = _client;
	final request = http.Request('GET', uri);
	final response = await client.send(request);
	if (response.statusCode != 200) {
	  throw Exception('Download fehlgeschlagen (${response.statusCode}).');
	}

	final dir = await getTemporaryDirectory();
	final apkFile = File(
	  '${dir.path}/arbeitszeit_${manifest.version.replaceAll('.', '_')}.apk',
	);
	if (await apkFile.exists()) {
	  await apkFile.delete();
	}

	final sink = apkFile.openWrite();
	var received = 0;
	final total = response.contentLength ?? 0;

	await for (final chunk in response.stream) {
	  received += chunk.length;
	  sink.add(chunk);
	  if (total > 0) {
		final progress = ((received / total) * 100).clamp(0, 100).toStringAsFixed(0);
		onProgress?.call('Update wird heruntergeladen... $progress%');
	  }
	}
	await sink.flush();
	await sink.close();

	await _verifyFileHashIfNeeded(apkFile, manifest.sha256);
	onProgress?.call('Download fertig. Android-Installer wird gestartet...');
	await _installChannel.invokeMethod('installApk', {'filePath': apkFile.path});
	return const UpdateInstallResult(
	  message: 'Download fertig. Android-Installer wird gestartet...',
	);
  }

  Future<void> openUpdateInBrowser(UpdateManifest manifest) async {
	final uri = Uri.tryParse(manifest.apkUrl);
	if (uri == null) {
	  throw Exception('APK-URL ist ungültig.');
	}

	final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
	if (!launched) {
	  throw Exception('Konnte APK-Link nicht im Browser öffnen.');
	}
  }

  Future<void> _verifyFileHashIfNeeded(File file, String sha256Hash) async {
	final expected = sha256Hash.trim().toLowerCase();
	if (expected.isEmpty) {
	  return;
	}

	final bytes = await file.readAsBytes();
	final digest = sha256.convert(bytes).toString().toLowerCase();
	if (digest != expected) {
	  await file.delete();
	  throw Exception('APK-Integritätsprüfung fehlgeschlagen (SHA256).');
	}
  }

  int compareVersions(String a, String b) {
	final aParts = normalizedVersion(a)
		.split('.')
		.map((e) => int.tryParse(e) ?? 0)
		.toList();
	final bParts = normalizedVersion(b)
		.split('.')
		.map((e) => int.tryParse(e) ?? 0)
		.toList();
	final maxLen = aParts.length > bParts.length ? aParts.length : bParts.length;

	for (var i = 0; i < maxLen; i++) {
	  final left = i < aParts.length ? aParts[i] : 0;
	  final right = i < bParts.length ? bParts[i] : 0;
	  if (left > right) {
		return 1;
	  }
	  if (left < right) {
		return -1;
	  }
	}
	return 0;
  }

  String normalizedVersion(String raw) {
	var value = raw.trim();
	if (value.startsWith('v') || value.startsWith('V')) {
	  value = value.substring(1);
	}

	final plusIndex = value.indexOf('+');
	if (plusIndex != -1) {
	  value = value.substring(0, plusIndex);
	}

	final clean = value
		.split('.')
		.map((segment) {
		  final digits = segment.replaceAll(RegExp(r'[^0-9]'), '');
		  return digits.isEmpty ? '0' : digits;
		})
		.join('.');

	return clean.isEmpty ? '0' : clean;
  }

  int buildNumberFromVersion(String raw) {
	final parts = normalizedVersion(raw)
		.split('.')
		.map((e) => int.tryParse(e) ?? 0)
		.toList();

	final major = parts.isNotEmpty ? parts[0] : 0;
	final minor = parts.length > 1 ? parts[1] : 0;
	final patch = parts.length > 2 ? parts[2] : 0;

	return major * 10000 + minor * 100 + patch;
  }
}
