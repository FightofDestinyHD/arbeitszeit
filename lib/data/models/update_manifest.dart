class UpdateManifest {
  const UpdateManifest({
	required this.version,
	required this.apkUrl,
	required this.notes,
	required this.buildNumber,
	this.sha256 = '',
  });

  final String version;
  final String apkUrl;
  final String notes;
  final int buildNumber;
  final String sha256;

  static UpdateManifest fromJson(Map<String, dynamic> json) {
	final rawBuild = json['build_number'];
	final parsedBuild = rawBuild is int
		? rawBuild
		: int.tryParse((rawBuild as String? ?? '').trim()) ?? 0;

	return UpdateManifest(
	  version: (json['version'] as String? ?? '').trim(),
	  apkUrl: (json['apk_url'] as String? ?? '').trim(),
	  notes: (json['notes'] as String? ?? '').trim(),
	  buildNumber: parsedBuild,
	  sha256: (json['sha256'] as String? ?? '').trim(),
	);
  }
}
